# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'
require 'securerandom'

describe ABMeter::Core::UserParameterResolver do
  let(:user) { ABMeter::Core::User.new(user_id: 'user-123', email: 'user-123@test.com') }
  let(:internal_user_1) { ABMeter::Core::User.new(user_id: 'internal-user-1', email: 'internal-user-1@test.com') }
  let(:internal_user_2) { ABMeter::Core::User.new(user_id: 'internal-user-2', email: 'internal-user-2@test.com') }

  context 'with different color scheme' do
    let(:config_json) do
      {
        spaces: [{ id: 1, salt: 'main-space-salt' }],
        parameters: [
          { id: 1, slug: 'parameter-color-button', parameter_type: 'String', default_value: 'default-button-color',
            space_id: 1 },
          { id: 2, slug: 'parameter-color-background', parameter_type: 'String',
            default_value: 'default-background-color', space_id: 1 }
        ],
        feature_flags: [
          {
            id: 200,
            audience: { id: 10, type: 'user_list', user_ids: ['internal-user-1', 'internal-user-2'] },
            variant: {
              id: 100,
              parameter_values: [
                { slug: 'parameter-color-button', value: 'blue' },
                { slug: 'parameter-color-background', value: 'yellow' }
              ]
            }
          }
        ],
        experiments: []
      }.to_json
    end

    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }
    let(:resolver) { described_class.new(config: config) }

    describe 'internal users get exposed to feature flag' do
      it 'returns vibrant colors for internal_users' do
        [internal_user_1, internal_user_2].each do |user|
          exposure = resolver.exposure_for(user: user, parameter_slug: 'parameter-color-button')
          expect(exposure[:parameter_id]).to eq(1)
          expect(exposure[:space_id]).to eq(1)
          expect(exposure[:resolved_value]).to eq('blue')
          expect(exposure[:user_id]).to eq(user.user_id)
          expect(exposure[:exposable_type]).to eq('FeatureFlag')
          expect(exposure[:exposable_id]).to eq(200)
          expect(exposure[:audience_id]).to eq(10)
          expect(exposure[:resolved_at]).not_to be_nil
        end
      end
    end

    describe 'everybody else gets exposed to default values' do
      it 'returns default variant' do
        result = resolver.exposure_for(user: user, parameter_slug: 'parameter-color-button')
        expect(result[:resolved_value]).to eq('default-button-color')
      end
    end
  end

  describe 'with experiments' do
    let(:config_json) do
      {
        spaces: [{ id: 1, salt: 'main-space-salt' }],
        parameters: [
          { id: 1, slug: 'color', parameter_type: 'String', default_value: 'default', space_id: 1 }
        ],
        experiments: [
          {
            id: 400,
            space_id: 1,
            range: [1, 100],
            audience_variants: [
              { audience: { id: 100, type: 'random', salt: 'control-salt', range: [1, 20] }, variant: nil },
              {
                audience: { id: 101, type: 'random', salt: 'test_darker-salt', range: [21, 60] },
                variant: { id: 201, parameter_values: [{ slug: 'color', value: 'dark-red' }] }
              },
              {
                audience: { id: 102, type: 'random', salt: 'test_lighter-salt', range: [61, 100] },
                variant: { id: 202, parameter_values: [{ slug: 'color', value: 'light-blue' }] }
              }
            ]
          }
        ],
        feature_flags: []
      }.to_json
    end

    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }
    let(:resolver) { described_class.new(config: config) }

    it 'distributes users across multivariate experiment audiences' do
      users = 1000.times.map { |i| ABMeter::Core::User.new(user_id: "user-#{i}", email: "user-#{i}@test.com") }

      result = []
      time = Benchmark.measure do
        result = users.map { |user| resolver.exposure_for(user: user, parameter_slug: 'color') }
      end

      puts "Exposure for 1000 users took: #{time.real * 1000}ms"

      color_exposures = result

      # All users should be exposed to the experiment (100% range)
      expect(color_exposures.all? { |r| r[:exposable_id] == 400 }).to be true

      # Check distribution across variants
      control = color_exposures.select { |r| r[:resolved_value] == 'default' }
      dark_red = color_exposures.select { |r| r[:resolved_value] == 'dark-red' }
      light_blue = color_exposures.select { |r| r[:resolved_value] == 'light-blue' }

      expect(control.size).to be_within(50).of(200) # 20% of 1000
      expect(dark_red.size).to be_within(75).of(400) # 40% of 1000
      expect(light_blue.size).to be_within(75).of(400) # 40% of 1000
    end

    it 'correctly parses multivariate experiment configuration' do
      exp = config.experiments.first

      expect(exp.audience_variants.size).to eq(3)

      # Control audience
      control_audience, control_variant = exp.audience_variants[0]
      expect(control_audience.range).to eq(1..20)
      expect(control_variant).to be_nil

      # Test darker audience
      darker_audience, darker_variant = exp.audience_variants[1]
      expect(darker_audience.range).to eq(21..60)
      expect(darker_variant.parameter_values['color']).to eq('dark-red')

      # Test lighter audience
      lighter_audience, lighter_variant = exp.audience_variants[2]
      expect(lighter_audience.range).to eq(61..100)
      expect(lighter_variant.parameter_values['color']).to eq('light-blue')
    end
  end

  # Regression test for sc-179: resolver must only match experiments that control the requested parameter
  # Note: This test uses experiments in DIFFERENT spaces, which is realistic when both need 100% allocation
  describe 'with experiments in different spaces controlling different parameters' do
    let(:config_json) do
      {
        spaces: [
          { id: 1, salt: 'color-space-salt' },
          { id: 2, salt: 'cache-space-salt' }
        ],
        parameters: [
          { id: 1, slug: 'color', parameter_type: 'String', default_value: 'default-color', space_id: 1 },
          { id: 2, slug: 'cache_strategy', parameter_type: 'String', default_value: 'default-cache', space_id: 2 }
        ],
        experiments: [
          # Experiment A: uses "color" parameter in space 1 (100% allocation)
          {
            id: 100,
            space_id: 1,
            range: [1, 100],
            audience_variants: [
              {
                audience: { id: 10, type: 'random', salt: 'color-test-salt', range: [1, 100] },
                variant: { id: 1, parameter_values: [{ slug: 'color', value: 'red' }] }
              }
            ]
          },
          # Experiment B: uses "cache_strategy" parameter in space 2 (100% allocation)
          {
            id: 200,
            space_id: 2,
            range: [1, 100],
            audience_variants: [
              {
                audience: { id: 20, type: 'random', salt: 'cache-test-salt', range: [1, 100] },
                variant: { id: 2, parameter_values: [{ slug: 'cache_strategy', value: 'aggressive' }] }
              }
            ]
          }
        ],
        feature_flags: []
      }.to_json
    end

    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }
    let(:resolver) { described_class.new(config: config) }
    let(:user) { ABMeter::Core::User.new(user_id: 'test-user-123', email: 'test@example.com') }

    it 'resolves cache_strategy to Experiment B, not Experiment A' do
      exposure = resolver.exposure_for(user: user, parameter_slug: 'cache_strategy')

      # The exposure should be attributed to Experiment B (id: 200) which uses cache_strategy
      # NOT to Experiment A (id: 100) which only uses the "color" parameter
      expect(exposure[:exposable_type]).to eq('Experiment')
      expect(exposure[:exposable_id]).to eq(200) # Should be Experiment B
      expect(exposure[:resolved_value]).to eq('aggressive')
    end

    it 'resolves color to Experiment A' do
      exposure = resolver.exposure_for(user: user, parameter_slug: 'color')

      # color parameter is controlled by Experiment A
      expect(exposure[:exposable_type]).to eq('Experiment')
      expect(exposure[:exposable_id]).to eq(100)
      expect(exposure[:resolved_value]).to eq('red')
    end
  end

  # Realistic scenario: multiple experiments in the SAME space with proper traffic partitioning
  # This tests that parameter resolution correctly attributes to the right experiment based on
  # user bucket, even when experiments share a space but control different parameters
  describe 'with properly partitioned experiments in same space' do
    let(:config_json) do
      {
        spaces: [{ id: 1, salt: 'main-space-salt' }],
        parameters: [
          { id: 1, slug: 'color', parameter_type: 'String', default_value: 'default-color', space_id: 1 },
          { id: 2, slug: 'cache_strategy', parameter_type: 'String', default_value: 'default-cache', space_id: 1 }
        ],
        experiments: [
          # E1: controls "color" for users in bucket 1-40 (control + test variants)
          {
            id: 100,
            space_id: 1,
            range: [1, 40],
            audience_variants: [
              { audience: { id: 10, type: 'random', salt: 'e1-control-salt', range: [1, 50] }, variant: nil },
              {
                audience: { id: 11, type: 'random', salt: 'e1-test-salt', range: [51, 100] },
                variant: { id: 1, parameter_values: [{ slug: 'color', value: 'red' }] }
              }
            ]
          },
          # E2: controls "color" for users in bucket 41-70 (control + test variants)
          {
            id: 200,
            space_id: 1,
            range: [41, 70],
            audience_variants: [
              { audience: { id: 20, type: 'random', salt: 'e2-control-salt', range: [1, 50] }, variant: nil },
              {
                audience: { id: 21, type: 'random', salt: 'e2-test-salt', range: [51, 100] },
                variant: { id: 2, parameter_values: [{ slug: 'color', value: 'blue' }] }
              }
            ]
          },
          # E3: controls "cache_strategy" for users in bucket 71-100 (control + test variants)
          {
            id: 300,
            space_id: 1,
            range: [71, 100],
            audience_variants: [
              { audience: { id: 30, type: 'random', salt: 'e3-control-salt', range: [1, 50] }, variant: nil },
              {
                audience: { id: 31, type: 'random', salt: 'e3-test-salt', range: [51, 100] },
                variant: { id: 3, parameter_values: [{ slug: 'cache_strategy', value: 'aggressive' }] }
              }
            ]
          }
        ],
        feature_flags: []
      }.to_json
    end

    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }
    let(:resolver) { described_class.new(config: config) }

    it 'never attributes color parameter to E3 (which only controls cache_strategy)' do
      users = 100.times.map { |i| ABMeter::Core::User.new(user_id: SecureRandom.uuid, email: "user#{i}@test.com") }

      aggregate_failures 'color attribution invariants' do
        users.each do |user|
          exposure = resolver.exposure_for(user: user, parameter_slug: 'color')

          # Color should NEVER be attributed to E3 (id: 300) which only controls cache_strategy
          expect(exposure[:exposable_id]).not_to eq(300),
            "User #{user.user_id}: color should not be attributed to E3 (id: 300)"

          # It should be attributed to E1 (100), E2 (200), or nil (user not in any color experiment's range)
          expect([100, 200, nil]).to include(exposure[:exposable_id]),
            "User #{user.user_id}: expected exposable_id in [100, 200, nil], got #{exposure[:exposable_id]}"

          # Resolved value should be from the correct experiment or default
          expect(['default-color', 'red', 'blue']).to include(exposure[:resolved_value]),
            "User #{user.user_id}: unexpected color value #{exposure[:resolved_value]}"
        end
      end
    end

    it 'never attributes cache_strategy parameter to E1 or E2 (which only control color)' do
      users = 100.times.map { |i| ABMeter::Core::User.new(user_id: SecureRandom.uuid, email: "user#{i}@test.com") }

      aggregate_failures 'cache_strategy attribution invariants' do
        users.each do |user|
          exposure = resolver.exposure_for(user: user, parameter_slug: 'cache_strategy')

          # cache_strategy should NEVER be attributed to E1 (100) or E2 (200)
          expect([100, 200]).not_to include(exposure[:exposable_id]),
            "User #{user.user_id}: cache_strategy should not be attributed to E1/E2"

          # It should be attributed to E3 (300) or nil (user not in E3's range)
          expect([300, nil]).to include(exposure[:exposable_id]),
            "User #{user.user_id}: expected exposable_id in [300, nil], got #{exposure[:exposable_id]}"

          # Resolved value should be from E3 or default
          expect(['default-cache', 'aggressive']).to include(exposure[:resolved_value]),
            "User #{user.user_id}: unexpected cache_strategy value #{exposure[:resolved_value]}"
        end
      end
    end

    it 'attributes to correct experiment based on user space bucket' do
      # Test with many users to cover all bucket ranges
      users = 200.times.map { |i| ABMeter::Core::User.new(user_id: SecureRandom.uuid, email: "user#{i}@test.com") }

      e1_users = []
      e2_users = []
      no_experiment_users = []

      users.each do |user|
        exposure = resolver.exposure_for(user: user, parameter_slug: 'color')
        case exposure[:exposable_id]
        when 100 then e1_users << user
        when 200 then e2_users << user
        when nil then no_experiment_users << user
        end
      end

      # With 200 random users and bucket ranges 1-40, 41-70, 71-100,
      # we expect roughly: E1=40%, E2=30%, none=30%
      # Allow generous tolerance for randomness
      expect(e1_users.size).to be_within(40).of(80), "E1 (40%) got #{e1_users.size}/200"
      expect(e2_users.size).to be_within(35).of(60), "E2 (30%) got #{e2_users.size}/200"
      expect(no_experiment_users.size).to be_within(35).of(60), "No experiment (30%) got #{no_experiment_users.size}/200"
    end

    it 'control group users get default value but are still attributed to experiment' do
      # Find a user that lands in E1's control group (bucket 1-40, audience 1-50)
      control_user = nil
      100.times do
        candidate = ABMeter::Core::User.new(user_id: SecureRandom.uuid, email: 'control@test.com')
        exposure = resolver.exposure_for(user: candidate, parameter_slug: 'color')
        if exposure[:exposable_id] == 100 && exposure[:resolved_value] == 'default-color'
          control_user = candidate
          break
        end
      end

      skip 'Could not find control group user in 100 attempts' unless control_user

      exposure = resolver.exposure_for(user: control_user, parameter_slug: 'color')

      # Control group: default value BUT attributed to the experiment
      expect(exposure[:resolved_value]).to eq('default-color')
      expect(exposure[:exposable_type]).to eq('Experiment')
      expect(exposure[:exposable_id]).to eq(100)
      expect(exposure[:audience_id]).to eq(10) # Control audience
    end
  end

  # Regression test for sc-179: resolver must only match feature flags that control the requested parameter
  describe 'with feature flag controlling specific parameters' do
    let(:config_json) do
      {
        spaces: [{ id: 1, salt: 'main-space-salt' }],
        parameters: [
          { id: 1, slug: 'dark_mode_enabled', parameter_type: 'Boolean', default_value: 'false', space_id: 1 },
          { id: 2, slug: 'button_color', parameter_type: 'String', default_value: 'blue', space_id: 1 }
        ],
        experiments: [],
        feature_flags: [
          # Feature Flag: controls only "dark_mode_enabled" parameter for beta users
          {
            id: 100,
            audience: { id: 10, type: 'user_list', user_ids: ['beta-user-1', 'beta-user-2'] },
            variant: { id: 1, parameter_values: [{ slug: 'dark_mode_enabled', value: 'true' }] }
          }
        ]
      }.to_json
    end

    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }
    let(:resolver) { described_class.new(config: config) }
    let(:beta_user) { ABMeter::Core::User.new(user_id: 'beta-user-1', email: 'beta@example.com') }

    it 'resolves button_color to default (no feature flag match)' do
      exposure = resolver.exposure_for(user: beta_user, parameter_slug: 'button_color')

      # The exposure should NOT be attributed to any feature flag because
      # the only feature flag (id: 100) doesn't control "button_color"
      expect(exposure[:exposable_type]).to be_nil
      expect(exposure[:exposable_id]).to be_nil
      expect(exposure[:resolved_value]).to eq('blue') # Default value
    end

    # Verify the feature flag correctly matches when resolving the parameter it actually controls
    it 'correctly resolves dark_mode_enabled to the feature flag' do
      exposure = resolver.exposure_for(user: beta_user, parameter_slug: 'dark_mode_enabled')

      expect(exposure[:exposable_type]).to eq('FeatureFlag')
      expect(exposure[:exposable_id]).to eq(100)
      expect(exposure[:resolved_value]).to eq('true')
    end
  end
end
