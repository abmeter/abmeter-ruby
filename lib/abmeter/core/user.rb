# frozen_string_literal: true

module ABMeter
  module Core
    class User
      attr_reader :user_id, :email

      def initialize(user_id:, email:)
        @user_id = user_id
        @email = email
      end
    end
  end
end
