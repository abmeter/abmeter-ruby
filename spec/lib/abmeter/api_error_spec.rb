require 'spec_helper'

describe ABMeter::APIError do
  describe '#initialize' do
    context 'with a hash error body' do
      let(:error_body) do
        {
          'error' => 'Bad request',
          'code' => 'VALIDATION_ERROR',
          'details' => { 'field' => ['is required'] }
        }
      end
      let(:response) { instance_double(Faraday::Response, body: error_body, status: 400) }

      it 'returns a hash representation' do
        api_error = described_class.new(response)
        expect(api_error.to_h).to eq(
          error: 'Bad request',
          code: 'VALIDATION_ERROR',
          details: { 'field' => ['is required'] },
          status: 400
        )
      end

      it 'sets the error message' do
        api_error = described_class.new(response)
        expect(api_error.message).to eq('Bad request')
      end

      it 'sets the error code' do
        api_error = described_class.new(response)
        expect(api_error.code).to eq('VALIDATION_ERROR')
      end

      it 'sets the details' do
        api_error = described_class.new(response)
        expect(api_error.details).to eq({ 'field' => ['is required'] })
      end

      it 'sets the status' do
        api_error = described_class.new(response)
        expect(api_error.status).to eq(400)
      end
    end

    context 'with a hash using symbol keys' do
      let(:error_body) do
        {
          error: 'Not found',
          code: 'RESOURCE_NOT_FOUND',
          details: {}
        }
      end
      let(:response) { instance_double(Faraday::Response, body: error_body, status: 404) }

      it 'handles symbol keys' do
        api_error = described_class.new(response)
        expect(api_error.to_h).to eq(
          error: 'Not found',
          code: 'RESOURCE_NOT_FOUND',
          details: {},
          status: 404
        )
      end
    end

    context 'with minimal error body' do
      let(:error_body) { { 'error' => 'Something went wrong', 'details' => {} } }
      let(:response) { instance_double(Faraday::Response, body: error_body, status: 500) }

      it 'uses the provided status' do
        api_error = described_class.new(response)
        expect(api_error.status).to eq(500)
      end

      it 'has nil code' do
        api_error = described_class.new(response)
        expect(api_error.code).to be_nil
      end

      it 'sets the error message' do
        api_error = described_class.new(response)
        expect(api_error.message).to eq('Something went wrong')
      end

      it 'has empty details' do
        api_error = described_class.new(response)
        expect(api_error.details).to eq({})
      end

      it 'returns a compact hash representation' do
        api_error = described_class.new(response)
        expect(api_error.to_h).to eq(
          error: 'Something went wrong',
          details: {},
          status: 500
        )
      end
    end

    context 'with a string error body' do
      let(:error_body) { 'Connection timeout' }
      let(:response) { instance_double(Faraday::Response, body: error_body, status: 503) }

      it 'uses the string as the error message' do
        api_error = described_class.new(response)
        expect(api_error.message).to eq('Connection timeout')
      end

      it 'uses the provided status' do
        api_error = described_class.new(response)
        expect(api_error.status).to eq(503)
      end

      it 'has nil code' do
        api_error = described_class.new(response)
        expect(api_error.code).to be_nil
      end

      it 'has empty details' do
        api_error = described_class.new(response)
        expect(api_error.details).to eq({})
      end
    end

    context 'with malformed error (missing required fields)' do
      let(:error_body) { {} }
      let(:response) { instance_double(Faraday::Response, body: error_body, status: 500) }

      it 'uses a default error message' do
        api_error = described_class.new(response)
        expect(api_error.message).to eq('Unknown error')
      end

      it 'has empty details' do
        api_error = described_class.new(response)
        expect(api_error.details).to eq({})
      end
    end
  end

  describe '#retryable?' do
    context 'with 5xx status codes' do
      it 'returns true for 500' do
        response = instance_double(Faraday::Response, body: 'Server error', status: 500)
        error = described_class.new(response)
        expect(error.retryable?).to be true
      end

      it 'returns true for 503' do
        response = instance_double(Faraday::Response, body: 'Service unavailable', status: 503)
        error = described_class.new(response)
        expect(error.retryable?).to be true
      end
    end

    context 'with 408 Request Timeout' do
      it 'returns true' do
        response = instance_double(Faraday::Response, body: 'Request timeout', status: 408)
        error = described_class.new(response)
        expect(error.retryable?).to be true
      end
    end

    context 'with 429 Too Many Requests' do
      it 'returns true' do
        response = instance_double(Faraday::Response, body: 'Too many requests', status: 429)
        error = described_class.new(response)
        expect(error.retryable?).to be true
      end
    end

    context 'with non-retryable status codes' do
      it 'returns false for 400' do
        response = instance_double(Faraday::Response, body: 'Bad request', status: 400)
        error = described_class.new(response)
        expect(error.retryable?).to be false
      end

      it 'returns false for 401' do
        response = instance_double(Faraday::Response, body: 'Unauthorized', status: 401)
        error = described_class.new(response)
        expect(error.retryable?).to be false
      end

      it 'returns false for 404' do
        response = instance_double(Faraday::Response, body: 'Not found', status: 404)
        error = described_class.new(response)
        expect(error.retryable?).to be false
      end
    end
  end

  describe '#partial_failure?' do
    context 'with 400 status and failures in details' do
      let(:error_body) do
        {
          'error' => 'Partial failure',
          'details' => {
            'failures' => [
              { 'index' => 0, 'error' => 'Invalid parameter' }
            ],
            'invalid_count' => 1
          }
        }
      end

      it 'returns true' do
        response = instance_double(Faraday::Response, body: error_body, status: 400)
        error = described_class.new(response)
        expect(error.partial_failure?).to be true
      end
    end

    context 'with 400 status but no failures' do
      let(:error_body) do
        {
          'error' => 'Bad request',
          'details' => {}
        }
      end

      it 'returns false' do
        response = instance_double(Faraday::Response, body: error_body, status: 400)
        error = described_class.new(response)
        expect(error.partial_failure?).to be false
      end
    end

    context 'with non-400 status' do
      let(:error_body) do
        {
          'error' => 'Server error',
          'details' => {
            'failures' => [{ 'index' => 0 }]
          }
        }
      end

      it 'returns false' do
        response = instance_double(Faraday::Response, body: error_body, status: 500)
        error = described_class.new(response)
        expect(error.partial_failure?).to be false
      end
    end
  end

  describe '#failure_count' do
    context 'with invalid_count in details' do
      let(:error_body) do
        {
          'error' => 'Partial failure',
          'details' => {
            'invalid_count' => 5
          }
        }
      end

      it 'returns the invalid_count' do
        response = instance_double(Faraday::Response, body: error_body, status: 400)
        error = described_class.new(response)
        expect(error.failure_count).to eq(5)
      end
    end

    context 'without invalid_count' do
      it 'returns 0' do
        response = instance_double(Faraday::Response, body: 'Error', status: 400)
        error = described_class.new(response)
        expect(error.failure_count).to eq(0)
      end
    end

    context 'with nil details' do
      it 'returns 0' do
        response = instance_double(Faraday::Response, body: { 'error' => 'Error' }, status: 400)
        error = described_class.new(response)
        expect(error.failure_count).to eq(0)
      end
    end
  end
end
