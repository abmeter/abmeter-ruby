module CustomerHelper
  def test_customer
    # This customer is pre-created in the API project in development
    {
      name: 'Test Customer',
      email: 'test@example.com',
      api_key: 'test-api-key'
    }
  end
end

RSpec.configure do |config|
  config.include CustomerHelper
end
