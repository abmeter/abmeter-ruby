require 'active_support/core_ext/hash/indifferent_access'

module ABMeter
  class APIError < StandardError
    attr_reader :code, :details, :status

    def initialize(response)
      @status = response.status
      error_body = response.body

      if error_body.is_a?(Hash)
        body = error_body.with_indifferent_access
        @error_message = body[:error] || 'Unknown error'
        @code = body[:code]
        @details = body[:details] || {}
      else
        @error_message = error_body.to_s
        @code = nil
        @details = {}
      end

      super(@error_message)
    end

    def message
      @error_message
    end

    def to_h
      {
        error: @error_message,
        code: @code,
        details: @details,
        status: @status
      }.compact
    end

    def retryable?
      @status >= 500 || @status == 408 || @status == 429
    end

    def partial_failure?
      @status == 400 && @details.is_a?(Hash) && !@details[:failures].nil? && !@details[:failures].empty?
    end

    def failure_count
      @details&.dig(:invalid_count) || 0
    end
  end
end
