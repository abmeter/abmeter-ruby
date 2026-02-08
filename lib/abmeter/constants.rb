# frozen_string_literal: true

module ABMeter
  DEFAULT_BATCH_SIZE = 100
  DEFAULT_FLUSH_INTERVAL = 60 # seconds
  DEFAULT_FETCH_INTERVAL = 60 # seconds
  DEFAULT_BASE_URL = 'https://api.abmeter.ai'
  DEFAULT_MAX_SUBMIT_ATTEMPTS = 3
  DEFAULT_MAX_RETRY_QUEUE_SIZE = 1000
  DEFAULT_LOG_LEVEL = :error
end
