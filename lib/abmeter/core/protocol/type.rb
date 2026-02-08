# frozen_string_literal: true

module ABMeter
  module Core
    module Protocol
      # Type name constants
      STRING = 'String'
      INTEGER = 'Integer'
      FLOAT = 'Float'
      BOOLEAN = 'Boolean'

      class Type
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def numerical?
          false
        end

        def cast!(value)
          value
        end

        def to_s
          name
        end
      end

      class StringType < Type
        def initialize
          super(STRING)
        end

        def cast!(value)
          value.to_s
        end
      end

      class IntegerType < Type
        def initialize
          super(INTEGER)
        end

        def numerical?
          true
        end

        def cast!(value)
          Integer(value)
        end
      end

      class FloatType < Type
        def initialize
          super(FLOAT)
        end

        def numerical?
          true
        end

        def cast!(value)
          Float(value)
        end
      end

      class BooleanType < Type
        def initialize
          super(BOOLEAN)
        end

        def cast!(value)
          case value
          when true, 'true', 'TRUE', 't', 'T', '1', 1
            true
          when false, 'false', 'FALSE', 'f', 'F', '0', 0, nil, ''
            false
          else
            raise ArgumentError, "Cannot cast #{value.inspect} to Boolean"
          end
        end
      end

      class TypeRegistry
        def initialize
          @types = {}
          register_default_types
        end

        def register(type)
          @types[type.name] = type
        end

        def get(type_name)
          @types[type_name] || raise("Unknown type: #{type_name}")
        end

        def all
          @types.values
        end

        def numerical_types
          @_numerical_types ||= all.select(&:numerical?)
        end

        private

        def register_default_types
          register(StringType.new)
          register(IntegerType.new)
          register(FloatType.new)
          register(BooleanType.new)
        end
      end

      # Protocol class methods
      class << self
        def string
          type(STRING)
        end

        def integer
          type(INTEGER)
        end

        def float
          type(FLOAT)
        end

        def boolean
          type(BOOLEAN)
        end

        def type(name)
          registry.get(name)
        end

        def all_types
          registry.all.map(&:name)
        end

        def numerical?(type_name)
          type(type_name).numerical?
        rescue StandardError
          false
        end

        def cast!(value, type_name)
          type(type_name).cast!(value)
        end

        def valid_for_type?(value, type_name)
          cast!(value, type_name)
          true
        rescue ArgumentError
          false
        end

        private

        def registry
          @registry ||= TypeRegistry.new
        end
      end
    end
  end
end
