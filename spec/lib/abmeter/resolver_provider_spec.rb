require 'spec_helper'
require 'active_support/testing/time_helpers'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/object/deep_dup'

describe ABMeter::ResolverProvider do
  include ActiveSupport::Testing::TimeHelpers

  let(:api_config) do
    config = ABMeter::Config.new
    config.api_key = 'test-api-key'
    config.fetch_interval = 300 # 5 minutes
    config
  end

  let(:json_config) do
    config = ABMeter::Config.new
    config.static_config = sample_json_config.to_json
    config
  end

  # single experiment with 100% allocation and a single audience, also having 100% allocation to the variant
  let(:sample_json_config) do
    {
      'parameters' => [
        {
          'id' => 1,
          'slug' => 'button_color',
          'parameter_type' => 'String',
          'default_value' => 'blue',
          'space_id' => 1
        }
      ],
      'spaces' => [
        {
          'id' => 1,
          'salt' => 'test_salt'
        }
      ],
      'experiments' => [
        {
          'id' => 1,
          'space_id' => 1,
          'range' => [1, 100],
          'audience_variants' => [
            {
              'audience' => {
                'id' => 1,
                'type' => 'random',
                'salt' => 'audience_salt',
                'range' => [1, 100]
              },
              'variant' => {
                'id' => 1,
                'parameter_values' => [
                  { 'slug' => 'button_color', 'value' => 'red' }
                ]
              }
            }
          ]
        }
      ],
      'feature_flags' => []
    }
  end

  let(:api_client) { instance_double(ABMeter::Client) }
  let(:api_response) do
    {
      version: '1.0',
      config: sample_json_config.to_json
    }.with_indifferent_access
  end


  let(:test_user) { ABMeter::Core::User.new(user_id: 'user123', email: 'user123@example.com') }

  before do
    ABMeter::AsyncSubmitter.reset!
  end

  around do |example|
    travel_to Time.parse('2026-06-29 12:00:00') do
      example.run
    end
  end

  describe '#initialize' do
    context 'with api_key configuration' do
      it 'initializes successfully' do
        provider = described_class.new(config: api_config, api_client: api_client)
        expect(provider).to be_a(described_class)
      end
    end

    context 'with static JSON configuration' do
      it 'initializes successfully' do
        provider = described_class.new(config: json_config)
        expect(provider).to be_a(described_class)
      end
    end

    context 'without api_key or static_config' do
      it 'raises an error' do
        expect { described_class.new(config: ABMeter::Config.new) }.to raise_error('Either api_key or static_config must be provided')
      end
    end
  end

  describe '#resolver' do
    context 'in API mode' do
      subject(:provider) { described_class.new(config: api_config, api_client: api_client) }

      it 'fetches configuration from API on first call' do
        expect(api_client).to receive(:get_assignment_config).and_return(api_response)
        provider.resolver
      end

      context 'on subsequent calls' do
        before do
          allow(api_client).to receive(:get_assignment_config).and_return(api_response)
          provider.resolver # First call to fetch and cache
        end

        it 'uses cached resolver without fetching again' do
          expect(api_client).not_to receive(:get_assignment_config)
          travel 4.minutes
          provider.resolver
        end

        it 'fetches configuration again' do
          expect(api_client).to receive(:get_assignment_config).and_return(api_response)
          travel 6.minutes
          provider.resolver
        end
      end

      context 'when API call fails' do
        it 'propagates the error' do
          allow(api_client).to receive(:get_assignment_config).and_raise(StandardError.new('API Error'))
          expect { provider.resolver }.to raise_error(StandardError, 'API Error')
        end
      end

      # No longer need a special context for JSON string since it's now the default
      it 'passes the JSON string directly to Core' do
        allow(api_client).to receive(:get_assignment_config).and_return(api_response)

        # Expect Core to receive the JSON string
        expect(ABMeter::Core).to receive(:build_resolver_from_json)
          .with(sample_json_config.to_json)
          .and_call_original

        provider.resolver
      end
    end

    context 'in JSON mode' do
      subject(:provider) { described_class.new(config: json_config) }

      it 'returns resolver without trying to update it' do
        expect(provider).not_to receive(:update_resolver)
        provider.resolver
      end
    end
  end

  describe '#resolve_parameter' do
    let(:parameter_slug) { 'button_color' }

    context 'in API mode' do
      subject(:provider) { described_class.new(config: api_config, api_client: api_client) }

      before do
        allow(api_client).to receive(:get_assignment_config).and_return(api_response)
      end

      context 'when resolver is loaded' do
        it 'returns the resolved value' do
          result = provider.resolve_parameter(user: test_user, parameter_slug: parameter_slug)
          expect(result).to eq('red')
        end

        it 'queues the exposure for reporting' do
          expect { provider.resolve_parameter(user: test_user, parameter_slug: parameter_slug) }
            .to change(ABMeter::AsyncSubmitter, :queue_size).by(1)
        end

        context 'when exposure has no exposable_id' do
          let(:no_experiment_config) do
            config = sample_json_config.deep_dup
            config['experiments'] = []
            config
          end

          before do
            allow(api_client).to receive(:get_assignment_config).and_return({
              version: '1.0',
              config: no_experiment_config.to_json
            }.with_indifferent_access)
          end

          it 'does not queue the exposure' do
            expect { provider.resolve_parameter(user: test_user, parameter_slug: parameter_slug) }
              .not_to(change(ABMeter::AsyncSubmitter, :queue_size))
          end
        end
      end

      context 'when resolver is not loaded and API fails' do
        before do
          allow(api_client).to receive(:get_assignment_config).and_raise(StandardError.new('API Error'))
        end

        it 'raises an error' do
          expect { provider.resolve_parameter(user: test_user, parameter_slug: parameter_slug) }
            .to raise_error(StandardError, 'API Error')
        end
      end
    end

    context 'in JSON mode' do
      subject(:provider) { described_class.new(config: json_config) }

      it 'returns the resolved value' do
        result = provider.resolve_parameter(user: test_user, parameter_slug: parameter_slug)
        expect(result).to eq('red')
      end

      it 'does not queue exposures' do
        expect { provider.resolve_parameter(user: test_user, parameter_slug: parameter_slug) }
          .not_to(change(ABMeter::AsyncSubmitter, :queue_size))
      end
    end
  end

  describe '#get_exposure' do
    let(:parameter_slug) { 'button_color' }

    let(:expected_exposure) do
      {
        parameter_id: 1,
        resolved_value: 'red',
        user_id: test_user.user_id,
        exposable_type: 'Experiment',
        exposable_id: 1,
        audience_id: 1,
        space_id: 1,
        resolved_at: Time.now
      }
    end

    context 'in API mode' do
      subject(:provider) { described_class.new(config: api_config, api_client: api_client) }

      before do
        allow(api_client).to receive(:get_assignment_config).and_return(api_response)
      end

      context 'when resolver is loaded' do
        it 'returns the full exposure data' do
          result = provider.get_exposure(user: test_user, parameter_slug: parameter_slug)
          expect(result).to eq(expected_exposure)
        end

        it 'does not queue the exposure' do
          expect { provider.get_exposure(user: test_user, parameter_slug: parameter_slug) }
            .not_to(change(ABMeter::AsyncSubmitter, :queue_size))
        end
      end

      context 'when resolver is not loaded' do
        before do
          allow(api_client).to receive(:get_assignment_config).and_raise(StandardError.new('API Error'))
        end

        it 'raises an error' do
          expect { provider.get_exposure(user: test_user, parameter_slug: parameter_slug) }
            .to raise_error(StandardError, 'API Error')
        end
      end
    end

    context 'in JSON mode' do
      subject(:provider) { described_class.new(config: json_config) }

      it 'returns the full exposure data' do
        result = provider.get_exposure(user: test_user, parameter_slug: parameter_slug)
        expect(result).to eq(expected_exposure)
      end
    end
  end
end
