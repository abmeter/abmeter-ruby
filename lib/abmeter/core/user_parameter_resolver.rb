# frozen_string_literal: true

module ABMeter
  module Core
    class UserParameterResolver
      attr_reader :config

      def initialize(config:)
        @config = config
      end

      def exposure_for(user:, parameter_slug:)
        validate_user!(user)

        # Find parameter once, upfront
        parameter = @config.parameters.find { |p| p.slug == parameter_slug }
        raise "Parameter '#{parameter_slug}' not found" unless parameter

        # First check feature flags that control this parameter
        feature_flag = find_matching_feature_flag(user, parameter_slug)
        return feature_flag.expose_parameter(user, parameter) if feature_flag

        # Then check experiments that control this parameter
        experiment_result = find_matching_experiment_variant(user, parameter_slug)
        if experiment_result
          variant, experiment, audience = experiment_result
          return experiment.expose_parameter(user, parameter, variant, audience)
        end

        {
          parameter_id: parameter.id,
          space_id: parameter.space_id,
          resolved_value: parameter.default_value,
          user_id: nil,
          exposable_type: nil,
          exposable_id: nil,
          audience_id: nil,
          resolved_at: Time.now
        }
      end

      private

      def validate_user!(user)
        raise ArgumentError, 'User must have user_id' unless user.respond_to?(:user_id)
        raise ArgumentError, 'User must have email' unless user.respond_to?(:email)
      end

      def find_matching_feature_flag(user, parameter_slug)
        @config.feature_flags.find do |feature_flag|
          # Only match if user is in audience AND the flag's variant controls this parameter
          feature_flag.audience.matches?(user) &&
            feature_flag_controls_parameter?(feature_flag, parameter_slug)
        end
      end

      def feature_flag_controls_parameter?(feature_flag, parameter_slug)
        feature_flag.variant&.parameter_values&.key?(parameter_slug)
      end

      def find_matching_experiment_variant(user, parameter_slug)
        @config.experiments.each do |experiment|
          # Skip experiments that don't control this parameter
          next unless experiment_controls_parameter?(experiment, parameter_slug)

          # Check if user is allocated to this experiment using space salt
          experiment_percentage = ABMeter::Core::Utils::NumUtils.to_percentage(experiment.space_salt, user.user_id)
          next unless experiment.range.include?(experiment_percentage)

          # Then check which audience the user belongs to using experiment salt
          user_percentage = ABMeter::Core::Utils::NumUtils.to_percentage(experiment.salt, user.user_id)

          assigned_av = experiment.audience_variants.find do |av|
            av.first.range.include?(user_percentage)
          end

          return [assigned_av.last, experiment, assigned_av.first] if assigned_av
        end
        nil
      end

      def experiment_controls_parameter?(experiment, parameter_slug)
        experiment.audience_variants.any? do |av|
          variant = av.last
          variant&.parameter_values&.key?(parameter_slug)
        end
      end
    end
  end
end
