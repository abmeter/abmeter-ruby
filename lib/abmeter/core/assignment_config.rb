# frozen_string_literal: true

require 'json'

module ABMeter
  module Core
    module AssignmentConfig
      class Config
        attr_reader :feature_flags, :experiments, :parameters, :spaces

        def initialize(feature_flags:, experiments:, parameters:, spaces:)
          @feature_flags = feature_flags
          @experiments = experiments
          @parameters = parameters
          @spaces = spaces
        end

        def to_json(*_)
          serialize.to_json
        end

        def serialize
          {
            spaces: spaces.sort_by(&:id).map(&:serialize),
            parameters: parameters.sort_by(&:id).map(&:serialize),
            feature_flags: feature_flags.sort_by(&:id).map(&:serialize),
            experiments: experiments.sort_by(&:id).map(&:serialize)
          }
        end
      end

      def self.from_json(json)
        parsed_json = JSON.parse(json, symbolize_names: true)

        spaces = Space.from_json(parsed_json[:spaces])
        space_salts = spaces.to_h { |space| [space.id, space.salt] }
        parameters = Parameter.from_json(parsed_json[:parameters])
        feature_flags = FeatureFlag.from_json(parsed_json[:feature_flags])
        experiments = parsed_json[:experiments] ? Experiment.from_json(parsed_json[:experiments], space_salts) : []

        Config.new(
          spaces: spaces,
          feature_flags: feature_flags,
          experiments: experiments,
          parameters: parameters
        )
      end
    end
  end
end
