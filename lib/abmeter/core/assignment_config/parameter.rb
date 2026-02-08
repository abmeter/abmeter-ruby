# frozen_string_literal: true

module ABMeter
  module Core
    module AssignmentConfig
      class Parameter
        attr_reader :id, :slug, :parameter_type, :default_value, :space_id

        def initialize(id:, slug:, parameter_type:, default_value:, space_id:)
          @id = id
          @slug = slug
          @parameter_type = parameter_type
          @default_value = default_value
          @space_id = space_id
        end

        def self.from_json(json)
          json.map do |param|
            new(
              id: param[:id],
              slug: param[:slug],
              default_value: ABMeter::Core::Protocol.cast!(param[:default_value], param[:parameter_type]),
              parameter_type: param[:parameter_type],
              space_id: param[:space_id]
            )
          end
        end

        def serialize(*_)
          {
            id: id,
            slug: slug,
            parameter_type: parameter_type,
            default_value: default_value.to_s,
            space_id: space_id
          }
        end
      end
    end
  end
end
