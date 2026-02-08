# frozen_string_literal: true

module ABMeter
  module Core
    module AssignmentConfig
      class Variant
        attr_reader :id, :parameter_values

        def initialize(id:, parameter_values:)
          @id = id
          @parameter_values = parameter_values
        end

        def parameter_value(parameter_slug)
          @parameter_values[parameter_slug]
        end

        def self.from_json(variant)
          parameter_values = variant[:parameter_values].map { |pv| [pv[:slug], pv[:value]] }.to_h
          Variant.new(id: variant[:id], parameter_values: parameter_values)
        end

        def serialize
          {
            id: id,
            parameter_values: parameter_values.map do |parameter_slug, value|
              {
                slug: parameter_slug,
                value: value
              }
            end
          }
        end
      end
    end
  end
end
