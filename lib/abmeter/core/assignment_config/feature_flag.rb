# frozen_string_literal: true

module ABMeter
  module Core
    module AssignmentConfig
      class FeatureFlag
        include Exposable

        attr_reader :id, :variant, :audience

        def initialize(id:, variant:, audience:)
          @id = id
          @variant = variant
          @audience = audience
        end

        def self.from_json(json)
          json.map do |flag|
            new(
              id: flag[:id],
              audience: Audience.from_json(flag[:audience]),
              variant: Variant.from_json(flag[:variant])
            )
          end
        end

        def serialize(*_)
          {
            id: id,
            audience: audience.serialize,
            variant: variant.serialize
          }
        end

        # Expose parameter for feature flags
        def expose_parameter(user, parameter)
          validate_expose_parameter_args!(user.user_id, parameter, audience)
          raise ArgumentError, 'Variant must be provided for feature flags' unless variant

          make_exposure(user, parameter, 'FeatureFlag', id, audience, variant)
        end
      end
    end
  end
end
