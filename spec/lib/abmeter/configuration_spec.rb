require 'spec_helper'

describe ABMeter do
  before { described_class.reset! }

  describe '.configure' do
    context 'when api key is not provided' do
      it 'raises an error' do
        expect do
          described_class.configure { |_| } # rubocop:disable Lint/EmptyBlock
        end.to raise_error(RuntimeError, 'No API key provided')
      end
    end

    context 'when api key is nil' do
      it 'raises an error' do
        expect do
          described_class.configure { |config| config.api_key = nil }
        end.to raise_error(RuntimeError, 'No API key provided')
      end
    end

    context 'when base_url is not provided' do
      it 'does not raise an error' do
        expect do
          described_class.configure { |config| config.api_key = 'valid_key' }
        end.not_to raise_error
        expect(described_class.config.base_url).to eq('https://api.abmeter.ai')
      end
    end

    context 'when base_url is nil' do
      it 'raises an error' do
        expect do
          described_class.configure do |config|
            config.api_key = 'valid_key'
            config.base_url = nil
          end
        end.to raise_error(RuntimeError, 'No API URL provided')
      end
    end

    context 'when api key and base_url are provided' do
      it 'creates a client instance' do
        described_class.configure do |config|
          config.api_key = 'valid_key'
          config.base_url = 'https://api.example.com'
        end
        expect(described_class.client).to be_a(described_class::Client)
      end
    end

    context 'when using json config' do
      it 'does not validate api_key and base_url' do
        json_config = {
          spaces: [],
          parameters: [],
          feature_flags: [],
          experiments: []
        }.to_json

        expect do
          described_class.configure do |config|
            config.static_config = json_config
          end
        end.not_to raise_error
      end
    end
  end

  describe 'configuration properties' do
    context 'with API-based configuration' do
      it 'accepts flush_interval property' do
        described_class.configure do |config|
          config.api_key = 'test_key'
          config.flush_interval = 30
        end

        expect(described_class.config.flush_interval).to eq(30)
      end

      it 'accepts fetch_interval property' do
        described_class.configure do |config|
          config.api_key = 'test_key'
          config.fetch_interval = 120
        end

        expect(described_class.config.fetch_interval).to eq(120)
      end

      it 'uses default values when properties are not set' do
        described_class.configure do |config|
          config.api_key = 'test_key'
        end

        expect(described_class.config.flush_interval).to eq(60)
        expect(described_class.config.fetch_interval).to eq(60)
      end
    end
  end
end
