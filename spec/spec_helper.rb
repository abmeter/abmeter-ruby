require 'active_support/core_ext/hash/indifferent_access'
require 'pry-byebug'
require 'vcr'
require 'abmeter'

# Configure VCR
VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :faraday
  config.configure_rspec_metadata!
  config.filter_sensitive_data('<API_KEY>') { ENV.fetch('ABMETER_API_KEY', nil) }
  config.filter_sensitive_data('<BASE_URL>') { ENV.fetch('ABMETER_TEST_BASE_URL', nil) }
end

RSpec.configure do |config|
  config.before do
    ENV['ABMETER_TEST_BASE_URL'] = 'http://api:3001'
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = nil
  config.warnings = true

  config.default_formatter = 'doc'

  config.order = :random
  Kernel.srand config.seed

  # Load support files
  Dir[File.join(File.dirname(__FILE__), 'support/**/*.rb')].each { |f| require f }
end
