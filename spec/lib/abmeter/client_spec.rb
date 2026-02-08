require 'spec_helper'

describe ABMeter::Client do
  include_context 'with valid config'

  let(:client) { described_class.new(config) }

  describe '#get_assignment_config', :vcr do
    context 'when API is available' do
      it 'fetches assignment configuration' do
        result = client.get_assignment_config
        expect(result).to be_a(Hash)
      end

      it 'returns assignment config data' do
        result = client.get_assignment_config
        expect(result).to include(:version, :config)
      end

      it 'returns HashWithIndifferentAccess allowing symbol and string access' do
        result = client.get_assignment_config

        expect(result[:version]).to eq('v1')
        expect(result[:config]).to be_a(String)

        expect(result['version']).to eq('v1')
        expect(result['config']).to be_a(String)
      end
    end

    context 'when unauthorized' do
      subject { client.get_assignment_config }

      it_behaves_like 'raises APIError when unauthorized'
    end
  end

  describe '#submit_exposures', :vcr do
    let(:user_id) { 'user456' }
    let(:exposures) do
      [
        {
          parameter_id: 1,
          space_id: 1,
          resolved_value: 'blue',
          user_id: user_id,
          exposable_type: 'Experiment',
          exposable_id: 1,
          audience_id: 1,
          resolved_at: Time.now.iso8601
        },
        {
          parameter_id: 1,
          space_id: 1,
          resolved_value: 'red',
          user_id: user_id,
          exposable_type: 'Experiment',
          exposable_id: 1,
          audience_id: 2,
          resolved_at: Time.now.iso8601
        }
      ]
    end

    context 'when API is available' do
      it 'submits exposures successfully' do
        expect { client.submit_exposures(exposures) }.not_to raise_error
      end
    end

    context 'with empty exposures array' do
      let(:exposures) { [] }

      it 'returns without making API call' do
        expect(client.instance_variable_get(:@http_client)).not_to receive(:post)
        expect { client.submit_exposures(exposures) }.not_to raise_error
      end
    end

    context 'when unauthorized' do
      subject { client.submit_exposures(exposures) }

      it_behaves_like 'raises APIError when unauthorized'
    end
  end

  describe '#track_events', :vcr do
    let(:events) do
      [
        {
          event_slug: 'test-event',
          user_id: 'user789',
          occurred_at: Time.now.iso8601,
          custom_fields: { color: 'red' }
        },
        {
          event_slug: 'test-event',
          user_id: 'user789',
          occurred_at: Time.now.iso8601,
          custom_fields: { color: 'green' }
        },
        {
          event_slug: 'test-event',
          user_id: 'user789',
          occurred_at: Time.now.iso8601,
          custom_fields: { color: 'blue' }
        }
      ]
    end

    context 'when API is available', :vcr do
      it 'tracks events successfully' do
        expect { client.track_events(events) }.not_to raise_error
      end
    end

    context 'with empty events array' do
      let(:events) { [] }

      it 'returns without making API call' do
        expect(client.instance_variable_get(:@http_client)).not_to receive(:post)
        expect { client.track_events(events) }.not_to raise_error
      end
    end

    context 'when unauthorized' do
      subject { client.track_events(events) }

      it_behaves_like 'raises APIError when unauthorized'
    end
  end
end
