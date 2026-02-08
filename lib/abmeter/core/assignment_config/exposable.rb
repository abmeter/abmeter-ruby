# frozen_string_literal: true

module ABMeter
  module Core
    module AssignmentConfig
      module Exposable
        protected

        def resolve_parameter_value(parameter, variant)
          variant&.parameter_value(parameter.slug) || parameter.default_value
        end

        def validate_expose_parameter_args!(user_id, parameter, audience)
          raise ArgumentError, 'User must be provided' unless user_id
          raise ArgumentError, 'Parameter must be provided' unless parameter
          raise ArgumentError, 'Audience must be provided' unless audience
        end

        def make_exposure(user, parameter, exposable_type, exposable_id, audience, variant) # rubocop:disable Metrics/ParameterLists
          value = resolve_parameter_value(parameter, variant)

          {
            parameter_id: parameter.id,
            space_id: parameter.space_id,
            resolved_value: value,
            user_id: user.user_id,
            exposable_type: exposable_type,
            exposable_id: exposable_id,
            audience_id: audience.id,
            resolved_at: Time.now
          }
        end
      end
    end
  end
end
