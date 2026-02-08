# frozen_string_literal: true

module ABMeter
  module Core
    module AssignmentConfig
      class Space
        attr_reader :id, :salt

        def initialize(id:, salt:)
          @id = id
          @salt = salt
        end

        def self.from_json(json)
          json.map do |space|
            new(
              id: space[:id],
              salt: space[:salt]
            )
          end
        end

        def serialize
          {
            id: id,
            salt: salt
          }
        end
      end
    end
  end
end
