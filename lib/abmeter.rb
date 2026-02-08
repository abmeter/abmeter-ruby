require 'active_support/core_ext/hash/indifferent_access'
require 'digest'
require 'ostruct'

# Core (zero-dependency assignment logic)
require_relative 'abmeter/core'

# SDK
require_relative 'abmeter/constants'
require_relative 'abmeter/version'
require_relative 'abmeter/api_error'
require_relative 'abmeter/client'
require_relative 'abmeter/resolver_provider'
require_relative 'abmeter/async_submitter'
require_relative 'abmeter/error_safety'

module ABMeter
  class << self
    include ErrorSafety
    def config
      raise 'ABMeter not configured. Call ABMeter.configure { |config| ... } first.' unless @config

      @config
    end

    def client
      unless @client
        raise 'ABMeter not configured or configured with "static" JSON. Call ABMeter.configure { |config| ... } first.'
      end

      @client
    end

    def resolver_provider
      raise 'ABMeter not configured. Call ABMeter.configure { |config| ... } first.' unless @resolver_provider

      @resolver_provider
    end

    def configure
      config = Config.new
      config.base_url = DEFAULT_BASE_URL
      yield(config)
      config.validate!
      # Set logger level if both logger and log_level are configured
      config.send(:set_logger_level, config.log_level)
      @config = config

      if config.static_config
        # JSON-based configuration
        @resolver_provider = ResolverProvider.new(config: config)
      else
        # API-based configuration
        @client = Client.new(config)

        @resolver_provider = ResolverProvider.new(config: config, api_client: @client)

        # Configure and start async submitter
        AsyncSubmitter.configure(
          api_client: @client,
          config: config
        )
        AsyncSubmitter.start
      end
    end

    def reset!
      AsyncSubmitter.shutdown

      @config = nil
      @client = nil
      @resolver_provider = nil
    end

    def track_event(event_name, user_id, data)
      # Queue the event for background processing
      AsyncSubmitter.queue_event(event_name, user_id, data)
      nil
    end
    error_safe :track_event

    # resolves paramater and submits parameter exposure to the API
    def resolve_parameter(user:, parameter_slug:)
      resolver_provider.resolve_parameter(user: user, parameter_slug: parameter_slug)
    end
    error_safe :resolve_parameter

    # Only evaluates exposure with all details, including resolved value, without submitting it to the API
    # Useful for testing/debugging
    def get_exposure(user:, parameter_slug:)
      resolver_provider.get_exposure(user: user, parameter_slug: parameter_slug)
    end
    error_safe :get_exposure
  end

  class Config
    # API configuration
    attr_accessor :api_key       # API key for authentication
    attr_accessor :base_url      # Base URL for API endpoints

    # Static configuration (alternative to API)
    attr_accessor :static_config # JSON string with assignment configuration

    # Performance tuning
    attr_accessor :flush_interval # Seconds between async flushes (default: 60)
    attr_accessor :fetch_interval # Seconds between config fetches (default: 60)

    # Logging and error handling
    attr_accessor :logger         # Logger instance (auto-detected by default)
    attr_accessor :log_level      # Log level (:debug, :info, :warn, :error)
    attr_accessor :error_callback # Proc called on errors

    def initialize
      @flush_interval = DEFAULT_FLUSH_INTERVAL
      @fetch_interval = DEFAULT_FETCH_INTERVAL
      @logger = detect_logger
    end

    def validate!
      unless static_config
        raise 'No API key provided' if api_key.nil?
        raise 'No API URL provided' if base_url.nil?
      end
    end

    def inspect
      masked_key = api_key ? "#{api_key[0..3]}...#{api_key[-4..]}" : nil
      config_type = static_config ? 'static' : 'API'

      <<~CONFIG.strip
        #ABMeter::Config {
          type: #{config_type},
          api_key: #{masked_key.inspect},
          base_url: #{base_url.inspect},
          flush_interval: #{flush_interval.inspect},
          fetch_interval: #{fetch_interval.inspect},
          logger: #{logger.class.name}
        }
      CONFIG
    end

    private

    def set_logger_level(log_level)
      return unless @logger

      @logger.level = logger_level_for(@logger, log_level || DEFAULT_LOG_LEVEL) if @logger.respond_to?(:level=)
    end

    def logger_level_for(logger, log_level)
      if defined?(Logger) && (logger.is_a?(Logger) || (defined?(Rails) && logger == Rails.logger))
        return case log_level
               when :debug then Logger::DEBUG
               when :info then Logger::INFO
               when :warn then Logger::WARN
               when :error then Logger::ERROR
               else Logger::WARN # rubocop:disable Lint/DuplicateBranch
               end
      end

      # Default to symbols, many loggers accept them including SemanticLogger
      @log_level
    end

    def detect_logger
      # Try Rails logger first
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger
      # Try Semantic Logger
      elsif defined?(SemanticLogger)
        SemanticLogger['ABMeter']
      # Default to Ruby's Logger
      else
        require 'logger'
        Logger.new($stdout, progname: 'ABMeter')
      end
    end
  end
end
