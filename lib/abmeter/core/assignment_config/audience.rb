# frozen_string_literal: true

module ABMeter
  module Core
    module AssignmentConfig
      class Audience
        attr_reader :id, :type

        def initialize(id:, type:)
          @id = id
          @type = type
        end

        def matches?(user)
          raise NotImplementedError, 'Subclass must implement this method'
        end

        def serialize
          {
            id: id,
            type: type
          }
        end

        def self.from_json(audience)
          case audience[:type]
          when 'user_list'
            UserListAudience.new(id: audience[:id], user_ids: audience[:user_ids])
          when 'predicate'
            PredicateAudience.new(id: audience[:id], predicate: audience[:predicate])
          when 'random'
            RandomAudience.new(id: audience[:id], range: Range.new(*audience[:range]))
          else
            raise "Unknown audience type: #{audience[:type]}"
          end
        end
      end

      class UserListAudience < Audience
        attr_reader :user_ids

        def initialize(id:, user_ids:)
          super(id: id, type: 'user_list')
          @user_ids = user_ids
        end

        def matches?(user)
          @user_ids.include?(user.user_id)
        end

        def serialize
          super.merge(
            user_ids: user_ids
          )
        end
      end

      class PredicateAudience < Audience
        attr_reader :predicate

        def initialize(id:, predicate:)
          super(id: id, type: 'predicate')
          @predicate = predicate
        end

        def matches?(user)
          user.email.match?(predicate)
        end

        def serialize
          super.merge(
            predicate: predicate
          )
        end
      end

      class RandomAudience < Audience
        attr_reader :range

        def initialize(id:, range:)
          super(id: id, type: 'random')
          @range = range
        end

        def serialize
          super.merge(
            range: [range.begin, range.end]
          )
        end
      end
    end
  end
end
