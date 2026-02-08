shared_context 'with unauthorized config' do
  let(:config) do
    config = ABMeter::Config.new
    config.api_key = 'invalid-key'
    config.base_url = ENV.fetch('ABMETER_TEST_BASE_URL', 'http://api:3001')
    config
  end
end

shared_context 'with valid config' do
  let(:config) do
    config = ABMeter::Config.new
    config.api_key = test_customer[:api_key]
    config.base_url = ENV.fetch('ABMETER_TEST_BASE_URL', 'http://api:3001')
    config
  end
end
