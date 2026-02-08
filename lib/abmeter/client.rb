require 'faraday'
require 'active_support/core_ext/hash/indifferent_access'
require_relative 'api_error'

module ABMeter
  class Client
    def initialize(config)
      @api_key = config.api_key
      @base_url = config.base_url
      @http_client = setup_http_client
    end

    def get_assignment_config
      response = @http_client.get('/api/v1/assignment-config')
      raise APIError.new(response) unless response.success?

      convert_to_indifferent_access(response.body)
    end

    def submit_exposures(exposures)
      return if exposures.empty?

      response = @http_client.post('/api/v1/exposures', {
                                     exposures: exposures
                                   })

      raise APIError.new(response) unless response.success?

      nil
    end

    def track_events(events)
      return if events.empty?

      response = @http_client.post('/api/v1/events', {
                                     events: events
                                   })

      raise APIError.new(response) unless response.success?

      nil
    end

    private

    def setup_http_client
      Faraday.new(@base_url) do |f|
        f.request :json
        f.response :json
        f.headers['Authorization'] = "Bearer #{@api_key}"
        f.adapter Faraday.default_adapter
      end
    end

    def convert_to_indifferent_access(obj)
      case obj
      when Hash
        HashWithIndifferentAccess.new(obj.transform_values { |v| convert_to_indifferent_access(v) })
      when Array
        obj.map { |item| convert_to_indifferent_access(item) }
      else
        obj
      end
    end
  end
end
