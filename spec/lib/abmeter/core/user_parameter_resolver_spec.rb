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
            salt: 'exp-400-salt',
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

      RSpec.configuration.reporter.message("Exposure for 1000 users took: #{time.real * 1000}ms")

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
            salt: 'exp-color-salt',
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
            salt: 'exp-cache-salt',
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
            salt: 'exp-e1-salt',
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
            salt: 'exp-e2-salt',
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
            salt: 'exp-e3-salt',
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

  # Per-experiment salt must survive the wire format so audience assignment is
  # independent across experiments. With salt dropped, every experiment hashes the
  # same nil salt and all assignments collapse into one global per-user shuffle
  # (φ = 1.0 between any two 50/50 experiments).
  describe 'cross-experiment assignment independence over the wire' do
    let(:user_count) { 1000 }
    let(:users) do
      user_count.times.map { |i| ABMeter::Core::User.new(user_id: "user-#{i}", email: "user-#{i}@test.com") }
    end

    def independence_config_data(exp1_salt:, exp2_salt:)
      {
        spaces: [
          { id: 1, salt: 'alpha-space-salt' },
          { id: 2, salt: 'beta-space-salt' }
        ],
        parameters: [
          { id: 1, slug: 'alpha', parameter_type: 'String', default_value: 'alpha-default', space_id: 1 },
          { id: 2, slug: 'beta', parameter_type: 'String', default_value: 'beta-default', space_id: 2 }
        ],
        experiments: [
          {
            id: 100, space_id: 1, range: [1, 100], salt: exp1_salt,
            audience_variants: [
              { audience: { id: 10, type: 'random', range: [1, 50] }, variant: nil },
              {
                audience: { id: 11, type: 'random', range: [51, 100] },
                variant: { id: 1, parameter_values: [{ slug: 'alpha', value: 'alpha-test' }] }
              }
            ]
          },
          {
            id: 200, space_id: 2, range: [1, 100], salt: exp2_salt,
            audience_variants: [
              { audience: { id: 20, type: 'random', range: [1, 50] }, variant: nil },
              {
                audience: { id: 21, type: 'random', range: [51, 100] },
                variant: { id: 2, parameter_values: [{ slug: 'beta', value: 'beta-test' }] }
              }
            ]
          }
        ],
        feature_flags: []
      }
    end

    # φ (phi) coefficient: correlation of two binary variables on a 2×2 table —
    # 0 = independent assignment, ±1 = identical. Independent per-experiment salts
    # give φ ≈ 0; a dropped salt makes both experiments hash the same percentile, so
    # the two assignments become identical and φ = 1.
    def phi_coefficient(pairs)
      n11 = pairs.count { |a, b| a && b }
      n10 = pairs.count { |a, b| a && !b }
      n01 = pairs.count { |a, b| !a && b }
      n00 = pairs.count { |a, b| !a && !b }
      denominator = Math.sqrt((n11 + n10) * (n01 + n00) * (n11 + n01) * (n10 + n00))
      return 0.0 if denominator.zero?

      ((n11 * n00) - (n10 * n01)) / denominator
    end

    def assignment_pairs(resolver)
      users.map do |user|
        alpha = resolver.exposure_for(user: user, parameter_slug: 'alpha')
        beta = resolver.exposure_for(user: user, parameter_slug: 'beta')
        [alpha[:audience_id] == 11, beta[:audience_id] == 21]
      end
    end

    it 'assigns audiences independently when the config travels the wire format' do
      config_data = independence_config_data(exp1_salt: 'space-1-exp-salt', exp2_salt: 'space-2-exp-salt')
      config = ABMeter::Core::AssignmentConfig.from_json(config_data.to_json)
      # Re-serialize through Config#serialize (the producer under test) and re-parse:
      wire_config = ABMeter::Core::AssignmentConfig.from_json(config.to_json)
      resolver = described_class.new(config: wire_config)

      expect(phi_coefficient(assignment_pairs(resolver)).abs).to be < 0.1
    end

    # Guards the test itself: with salts absent from the wire payload, assignment
    # degenerates into one global shuffle and the phi coefficient saturates.
    it 'detects the degenerate correlation when salts are missing from the wire payload' do
      config_data = independence_config_data(exp1_salt: nil, exp2_salt: nil)
      resolver = described_class.new(config: ABMeter::Core::AssignmentConfig.from_json(config_data.to_json))

      expect(phi_coefficient(assignment_pairs(resolver))).to be > 0.9
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

  # A variant that explicitly overrides a parameter to a falsy value must win.
  # The platform wire format casts values to their native type (Boolean false,
  # Integer 0, empty String), so `variant_value || default` would wrongly drop a
  # `false` override and fall back to the default.
  describe 'with a variant overriding parameters to falsy values' do
    let(:config_json) do
      {
        spaces: [{ id: 1, salt: 'main-space-salt' }],
        parameters: [
          { id: 1, slug: 'dark_mode', parameter_type: 'Boolean', default_value: 'true', space_id: 1 },
          { id: 2, slug: 'max_retries', parameter_type: 'Integer', default_value: '3', space_id: 1 },
          { id: 3, slug: 'banner_text', parameter_type: 'String', default_value: 'welcome', space_id: 1 }
        ],
        experiments: [],
        feature_flags: [
          {
            id: 100,
            audience: { id: 10, type: 'user_list', user_ids: ['beta-user-1'] },
            variant: {
              id: 1,
              parameter_values: [
                { slug: 'dark_mode', value: false },
                { slug: 'max_retries', value: 0 },
                { slug: 'banner_text', value: '' }
              ]
            }
          }
        ]
      }.to_json
    end

    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }
    let(:resolver) { described_class.new(config: config) }
    let(:beta_user) { ABMeter::Core::User.new(user_id: 'beta-user-1', email: 'beta@example.com') }

    it 'resolves a Boolean false override instead of the default' do
      exposure = resolver.exposure_for(user: beta_user, parameter_slug: 'dark_mode')
      expect(exposure[:exposable_type]).to eq('FeatureFlag')
      expect(exposure[:resolved_value]).to eq(false)
    end

    it 'resolves an Integer 0 override instead of the default' do
      exposure = resolver.exposure_for(user: beta_user, parameter_slug: 'max_retries')
      expect(exposure[:resolved_value]).to eq(0)
    end

    it 'resolves an empty String override instead of the default' do
      exposure = resolver.exposure_for(user: beta_user, parameter_slug: 'banner_text')
      expect(exposure[:resolved_value]).to eq('')
    end
  end

  # Email is an optional targeting field, not part of identity. A user built with
  # only a user_id resolves through user_list and random audiences normally.
  describe 'with a user that has no email' do
    let(:config_json) do
      {
        spaces: [{ id: 1, salt: 'main-space-salt' }],
        parameters: [
          { id: 1, slug: 'color', parameter_type: 'String', default_value: 'default-color', space_id: 1 }
        ],
        experiments: [
          {
            id: 400,
            space_id: 1,
            salt: 'exp-400-salt',
            range: [1, 100],
            audience_variants: [
              {
                audience: { id: 101, type: 'random', salt: 'test-salt', range: [1, 100] },
                variant: { id: 201, parameter_values: [{ slug: 'color', value: 'green' }] }
              }
            ]
          }
        ],
        feature_flags: [
          {
            id: 200,
            audience: { id: 10, type: 'user_list', user_ids: ['internal-user-1'] },
            variant: { id: 100, parameter_values: [{ slug: 'color', value: 'blue' }] }
          }
        ]
      }.to_json
    end

    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }
    let(:resolver) { described_class.new(config: config) }

    it 'resolves a user_list feature flag without raising' do
      listed_user = ABMeter::Core::User.new(user_id: 'internal-user-1')
      exposure = resolver.exposure_for(user: listed_user, parameter_slug: 'color')
      expect(exposure[:exposable_type]).to eq('FeatureFlag')
      expect(exposure[:resolved_value]).to eq('blue')
    end

    it 'resolves a random-audience experiment for an unlisted no-email user' do
      other_user = ABMeter::Core::User.new(user_id: 'someone-else')
      exposure = resolver.exposure_for(user: other_user, parameter_slug: 'color')
      expect(exposure[:exposable_type]).to eq('Experiment')
      expect(exposure[:resolved_value]).to eq('green')
    end
  end
end
