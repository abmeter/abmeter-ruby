# frozen_string_literal: true

require 'ostruct'
require_relative 'version'

# Utils
require_relative 'core/utils/num_utils'

# Protocol types
require_relative 'core/protocol/type'

# Assignment Config - order matters
require_relative 'core/assignment_config/exposable'
require_relative 'core/assignment_config/space'
require_relative 'core/assignment_config/parameter'
require_relative 'core/assignment_config/variant'
require_relative 'core/assignment_config/audience'
require_relative 'core/assignment_config/experiment'
require_relative 'core/assignment_config/feature_flag'
require_relative 'core/assignment_config'

# Parameter resolution
require_relative 'core/user_parameter_resolver'

# Domain objects
require_relative 'core/user'

module ABMeter
  module Core
    class Error < StandardError; end

    class << self
      # Get type object by name
      def type(type_name)
        Protocol.type(type_name)
      end

      # Get all available types
      def all_types
        Protocol.all_types
      end

      # Check if type is numerical
      def numerical?(type_name)
        Protocol.numerical?(type_name)
      end

      # Cast value to given type (strict - raises ArgumentError on invalid)
      def cast!(value, type_name)
        Protocol.cast!(value, type_name)
      end

      # Check if value is valid for type
      def valid_for_type?(value, type_name)
        Protocol.valid_for_type?(value, type_name)
      end

      # Build a resolver from JSON configuration
      def build_resolver_from_json(json)
        config = AssignmentConfig.from_json(json)
        UserParameterResolver.new(config: config)
      end

      # Provide convenience access to utilities
      def num_utils
        Utils::NumUtils
      end

      # Convert percentages to ranges for experiment allocation
      def percentages_to_ranges(percentages)
        Utils::NumUtils.percentages_to_ranges(percentages)
      end
    end
  end
end
