module ABMeter
  module ErrorSafety
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # DSL method to wrap methods with error handling
      # Usage: error_safe :method_name
      def error_safe(method_name)
        original_method = instance_method(method_name)

        define_method(method_name) do |*args, **kwargs, &block|
          original_method.bind(self).call(*args, **kwargs, &block)
        rescue StandardError => e
          log_error("Failed to execute #{method_name}", e)
          call_error_callback(e) if @config&.error_callback

          nil
        end
      end
    end

    private

    def log_error(message, error)
      return unless @config&.logger

      @config.logger.error("#{message}: #{error.class} - #{error.message}")
    end

    def call_error_callback(error)
      @config.error_callback&.call(error)
    rescue StandardError => e
      # Don't let callback errors escape either
      log_error('Error in error callback', e)
    end
  end
end
