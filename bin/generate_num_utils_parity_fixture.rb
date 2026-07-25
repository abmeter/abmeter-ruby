#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates the cross-language num-utils parity fixture consumed by the
# Python SDK (sdk-python/tests/test_num_utils_parity.py).
#
# Emits 1000 [salt, user_id, expected] triples where `expected` is the integer
# returned by ABMeter::Core::Utils::NumUtils.to_percentage. The Python
# implementation must reproduce every row. Run from the abmeter-sdk directory:
#
#   bundle exec ruby bin/generate_num_utils_parity_fixture.rb
#
# Regenerate only when the assignment algorithm changes (it shouldn't).

require 'json'
require_relative '../lib/abmeter/core/utils/num_utils'

FIXTURE_PATH = File.expand_path(
  '../../sdk-python/tests/fixtures/num_utils_parity.json', __dir__
)
ROW_COUNT = 1000

rows = Array.new(ROW_COUNT) do |i|
  # Deterministic, varied inputs — mixed shapes exercise the hashing across
  # salts and user-id formats without depending on RNG.
  salt = "space-salt-#{i}-#{format('%04d', (i * 7) % 9973)}"
  user_id = "user_#{((i * 31) + 5) % 100_003}"
  [salt, user_id, ABMeter::Core::Utils::NumUtils.to_percentage(salt, user_id)]
end

File.write(FIXTURE_PATH, "#{JSON.pretty_generate(rows)}\n")
puts "Wrote #{rows.size} rows to #{FIXTURE_PATH}"
