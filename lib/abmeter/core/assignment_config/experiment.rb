# frozen_string_literal: true

module ABMeter
  module Core
    module AssignmentConfig
      class Experiment
        include Exposable

        attr_reader :id, :range, :audience_variants, :space_id, :salt, :space_salt

        def initialize(id:, range:, audience_variants:, space_id:, salt:, space_salt:)
          @id = id
          @range = range
          @audience_variants = audience_variants
          @space_id = space_id
          @salt = salt
          @space_salt = space_salt
        end

        def self.from_json(json, space_salts)
          json.map do |exp|
            space_salt = space_salts[exp[:space_id]]
            raise "Space with id #{exp[:space_id]} not found" unless space_salt

            audience_variants = exp[:audience_variants].map do |av|
              [Audience.from_json(av[:audience]), av[:variant] ? Variant.from_json(av[:variant]) : nil]
            end

            new(
              id: exp[:id],
              range: Range.new(exp[:range][0], exp[:range][1]),
              audience_variants: audience_variants,
              space_id: exp[:space_id],
              salt: exp[:salt],
              space_salt: space_salt
            )
          end
        end

        def serialize
          {
            id: id,
            space_id: space_id,
            range: [range.begin, range.end],
            audience_variants: audience_variants.map do |audience_variant|
              {
                audience: audience_variant.first.serialize,
                variant: audience_variant.last&.serialize
              }
            end
          }
        end

        # Expose parameter for experiments
        # For experiments: audience is required, variant is optional (nil for control)
        def expose_parameter(user, parameter, variant, audience)
          validate_expose_parameter_args!(user.user_id, parameter, audience)

          make_exposure(user, parameter, 'Experiment', id, audience, variant)
        end
      end
    end
  end
end
