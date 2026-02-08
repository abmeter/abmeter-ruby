module ABMeter
  class ResolverProvider
    attr_reader :last_fetched_at

    def initialize(config:, api_client: nil)
      raise 'Either api_key or static_config must be provided' unless config.api_key || config.static_config

      @api_client = api_client
      @json_config = config.static_config
      @fetch_interval = config.fetch_interval

      @resolver = nil
      @last_fetched_at = nil

      # Build resolver immediately if using JSON config
      @resolver = ABMeter::Core.build_resolver_from_json(@json_config) if @json_config
    end

    def resolver
      refresh_config_if_needed unless @json_config
      raise 'Configuration not loaded' unless @resolver

      @resolver
    end

    def resolve_parameter(user:, parameter_slug:)
      exposure = resolver.exposure_for(user: user, parameter_slug: parameter_slug)

      # Queue the exposure for later submission (only in API mode)
      queue_exposure(exposure) if @api_client && exposure[:exposable_id]

      exposure[:resolved_value]
    end

    def get_exposure(user:, parameter_slug:)
      resolver.exposure_for(user: user, parameter_slug: parameter_slug)
    end

    private

    def refresh_config_if_needed
      return if @json_config # No refresh needed for JSON config

      update_resolver if !@resolver || time_to_refresh_config?
    end

    def time_to_refresh_config?
      @last_fetched_at.nil? || (Time.now - @last_fetched_at > @fetch_interval)
    end

    def update_resolver
      response = @api_client.get_assignment_config
      config_data = response[:config]

      @resolver = ABMeter::Core.build_resolver_from_json(config_data)
      @last_fetched_at = Time.now
    end

    def queue_exposure(exposure)
      AsyncSubmitter.queue_exposure(exposure)
    end
  end
end
