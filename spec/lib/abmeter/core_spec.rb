# frozen_string_literal: true

require 'spec_helper'

describe ABMeter::Core do
  describe '.percentages_to_ranges' do
    it 'delegates to Utils::NumUtils.percentages_to_ranges' do
      percentages = [10, 20, 30, 40]
      expected_result = [1..10, 11..30, 31..60, 61..100]

      # Test that it returns the expected result
      result = described_class.percentages_to_ranges(percentages)
      expect(result).to eq(expected_result)

      # Test that it actually delegates to NumUtils
      expect(ABMeter::Core::Utils::NumUtils).to receive(:percentages_to_ranges).with(percentages).and_call_original
      described_class.percentages_to_ranges(percentages)
    end
  end
end
