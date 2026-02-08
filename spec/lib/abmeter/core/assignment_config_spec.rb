# frozen_string_literal: true

require 'spec_helper'

describe ABMeter::Core::AssignmentConfig do
  # Comprehensive config with all features
  let(:comprehensive_config_data) do
    {
      spaces: [
        { id: 1, salt: 'space-1-salt' },
        { id: 2, salt: 'space-2-salt' }
      ],
      parameters: [
        { id: 1, slug: 'button_color', parameter_type: 'String', default_value: 'blue', space_id: 1 },
        { id: 2, slug: 'button_size', parameter_type: 'Integer', default_value: '12', space_id: 1 },
        { id: 3, slug: 'dark_mode', parameter_type: 'Boolean', default_value: 'false', space_id: 2 },
        { id: 4, slug: 'font_size', parameter_type: 'Float', default_value: '14.5', space_id: 2 }
      ],
      experiments: [
        {
          id: 100,
          space_id: 1,
          range: [1, 50],
          audience_variants: [
            {
              audience: { id: 10, type: 'random', salt: 'control-salt', range: [1, 30] },
              variant: nil # Control group
            },
            {
              audience: { id: 11, type: 'random', salt: 'test-salt', range: [31, 70] },
              variant: {
                id: 1,
                parameter_values: [
                  { slug: 'button_color', value: 'green' },
                  { slug: 'button_size', value: '16' }
                ]
              }
            },
            {
              audience: { id: 12, type: 'random', salt: 'test2-salt', range: [71, 100] },
              variant: {
                id: 2,
                parameter_values: [
                  { slug: 'button_color', value: 'red' },
                  { slug: 'button_size', value: '20' }
                ]
              }
            }
          ]
        },
        {
          id: 101,
          space_id: 1,
          range: [51, 100],
          audience_variants: [
            {
              audience: { id: 13, type: 'random', salt: 'exp2-salt', range: [1, 100] },
              variant: {
                id: 3,
                parameter_values: [
                  { slug: 'button_color', value: 'purple' }
                ]
              }
            }
          ]
        }
      ],
      feature_flags: [
        {
          id: 200,
          audience: { id: 20, type: 'predicate', predicate: '@example.com$' },
          variant: {
            id: 4,
            parameter_values: [
              { slug: 'dark_mode', value: 'true' },
              { slug: 'font_size', value: '18.0' }
            ]
          }
        },
        {
          id: 201,
          audience: { id: 21, type: 'user_list', user_ids: ['user1', 'user2', 'user3'] },
          variant: {
            id: 5,
            parameter_values: [
              { slug: 'button_color', value: 'yellow' }
            ]
          }
        }
      ]
    }
  end

  describe 'with valid comprehensive config' do
    let(:config_json) { comprehensive_config_data.to_json }
    let(:config) { ABMeter::Core::AssignmentConfig.from_json(config_json) }

    describe 'basic structure' do
      it 'loads all spaces' do
        expect(config.spaces.size).to eq(2)
        expect(config.spaces.map(&:id)).to eq([1, 2])
        expect(config.spaces.map(&:salt)).to eq(['space-1-salt', 'space-2-salt'])
      end

      it 'loads all parameters with proper type casting' do
        expect(config.parameters.size).to eq(4)

        button_color = config.parameters.find { |p| p.slug == 'button_color' }
        expect(button_color.default_value).to eq('blue')
        expect(button_color.default_value).to be_a(String)

        button_size = config.parameters.find { |p| p.slug == 'button_size' }
        expect(button_size.default_value).to eq(12)
        expect(button_size.default_value).to be_a(Integer)

        dark_mode = config.parameters.find { |p| p.slug == 'dark_mode' }
        expect(dark_mode.default_value).to be(false)
        expect(dark_mode.default_value).to be_a(FalseClass)

        font_size = config.parameters.find { |p| p.slug == 'font_size' }
        expect(font_size.default_value).to eq(14.5)
        expect(font_size.default_value).to be_a(Float)
      end

      it 'loads all experiments' do
        expect(config.experiments.size).to eq(2)
        expect(config.experiments.map(&:id)).to eq([100, 101])
      end

      it 'loads all feature flags' do
        expect(config.feature_flags.size).to eq(2)
        expect(config.feature_flags.map(&:id)).to eq([200, 201])
      end
    end

    describe 'serialization' do
      it 'round-trips through JSON preserving all data' do
        config_from_json = ABMeter::Core::AssignmentConfig.from_json(config.to_json)
        expect(config_from_json.serialize).to eq(config.serialize)
      end

      it 'serializes to expected structure' do
        serialized = config.serialize
        expect(serialized[:spaces].size).to eq(2)
        expect(serialized[:parameters].size).to eq(4)
        expect(serialized[:experiments].size).to eq(2)
        expect(serialized[:feature_flags].size).to eq(2)
      end
    end

    describe 'experiment validations' do
      it 'associates experiments with correct spaces' do
        config.experiments.each do |exp|
          space = config.spaces.find { |s| s.id == exp.space_id }
          expect(space).not_to be_nil
          expect(exp.space_salt).to eq(space.salt)
        end
      end

      it 'has non-overlapping experiment ranges within same space' do
        space1_experiments = config.experiments.select { |e| e.space_id == 1 }
        ranges = space1_experiments.map(&:range)

        ranges.combination(2).each do |r1, r2|
          overlap = r1.to_a & r2.to_a
          expect(overlap).to be_empty
        end
      end

      it 'has complete audience ranges within each experiment' do
        config.experiments.each do |exp|
          audiences = exp.audience_variants.map(&:first)
          ranges = audiences.map(&:range).sort_by(&:begin)

          # First range starts at 1
          expect(ranges.first.begin).to eq(1)

          # No gaps between ranges
          ranges.each_cons(2) do |r1, r2|
            expect(r2.begin).to eq(r1.end + 1)
          end

          # Last range ends at 100
          expect(ranges.last.end).to eq(100)
        end
      end

      it 'validates all variant parameters exist' do
        config.experiments.each do |exp|
          exp.audience_variants.each do |_audience, variant| # rubocop:disable Style/HashEachMethods
            next unless variant

            variant.parameter_values.each_key do |slug|
              param = config.parameters.find { |p| p.slug == slug }
              expect(param).not_to be_nil
            end
          end
        end
      end
    end

    describe 'feature flag validations' do
      it 'has both audience and variant for all flags' do
        config.feature_flags.each do |flag|
          expect(flag.audience).not_to be_nil
          expect(flag.variant).not_to be_nil
        end
      end

      it 'validates predicate audiences have predicates' do
        predicate_flags = config.feature_flags.select { |f| f.audience.type == 'predicate' }
        predicate_flags.each do |flag|
          expect(flag.audience.predicate).not_to be_empty
        end
      end

      it 'validates user_list audiences have user lists' do
        user_list_flags = config.feature_flags.select { |f| f.audience.type == 'user_list' }
        user_list_flags.each do |flag|
          expect(flag.audience.user_ids).not_to be_empty
        end
      end

      it 'validates all variant parameters exist' do
        config.feature_flags.each do |flag|
          flag.variant.parameter_values.each_key do |slug|
            param = config.parameters.find { |p| p.slug == slug }
            expect(param).not_to be_nil
          end
        end
      end
    end

    describe 'cross-entity validations' do
      it 'has unique parameter slugs within each space' do
        config.spaces.each do |space|
          space_params = config.parameters.select { |p| p.space_id == space.id }
          slugs = space_params.map(&:slug)
          expect(slugs).to eq(slugs.uniq)
        end
      end

      it 'references only existing spaces' do
        space_ids = config.spaces.map(&:id)

        config.parameters.each do |param|
          expect(space_ids).to include(param.space_id)
        end

        config.experiments.each do |exp|
          expect(space_ids).to include(exp.space_id)
        end
      end
    end

    describe '#expose_parameter' do
      let(:user) { ABMeter::Core::User.new(user_id: 'user-123', email: 'user-123@test.com') }

      context 'with experiments' do
        it 'exposes parameter with default value for control group' do
          exp = config.experiments.first
          param = config.parameters.find { |p| p.slug == 'button_color' }
          control_audience, control_variant = exp.audience_variants.first

          exposure = exp.expose_parameter(user, param, control_variant, control_audience)

          expect(exposure[:resolved_value]).to eq('blue') # default
          expect(exposure[:exposable_type]).to eq('Experiment')
          expect(exposure[:exposable_id]).to eq(exp.id)
        end

        it 'exposes parameter with variant value for test group' do
          exp = config.experiments.first
          param = config.parameters.find { |p| p.slug == 'button_color' }
          test_audience, test_variant = exp.audience_variants[1]

          exposure = exp.expose_parameter(user, param, test_variant, test_audience)

          expect(exposure[:resolved_value]).to eq('green') # variant value
          expect(exposure[:exposable_type]).to eq('Experiment')
          expect(exposure[:exposable_id]).to eq(exp.id)
        end

        it 'requires audience parameter' do
          exp = config.experiments.first
          param = config.parameters.first

          expect do
            exp.expose_parameter(user, param, nil, nil)
          end.to raise_error(ArgumentError, 'Audience must be provided')
        end
      end

      context 'with feature flags' do
        it 'exposes parameter with variant value' do
          flag = config.feature_flags.last
          param = config.parameters.find { |p| p.slug == 'button_color' }

          exposure = flag.expose_parameter(user, param)

          expect(exposure[:resolved_value]).to eq('yellow') # variant value
          expect(exposure[:exposable_type]).to eq('FeatureFlag')
          expect(exposure[:exposable_id]).to eq(flag.id)
        end

        it 'requires variant for feature flags' do
          flag = config.feature_flags.first
          param = config.parameters.first

          allow(flag).to receive(:variant).and_return(nil)

          expect do
            flag.expose_parameter(user, param)
          end.to raise_error(ArgumentError, 'Variant must be provided for feature flags')
        end
      end
    end
  end
end
