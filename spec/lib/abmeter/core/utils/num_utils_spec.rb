# frozen_string_literal: true

require 'spec_helper'

describe ABMeter::Core::Utils::NumUtils do
  describe '.to_percentage' do
    it 'returns a number between 1 and 100' do
      result = described_class.to_percentage('test_salt', 'test_id')
      expect(result).to be_between(1, 100)
    end

    it 'returns the same result for the same salt and id' do
      salt = 'consistent_salt'
      id = 'consistent_id'
      result1 = described_class.to_percentage(salt, id)
      result2 = described_class.to_percentage(salt, id)
      expect(result1).to eq(result2)
    end

    it 'returns different results for different salts' do
      id = 'same_id'
      result1 = described_class.to_percentage('salt1', id)
      result2 = described_class.to_percentage('salt2', id)
      expect(result1).not_to eq(result2)
    end

    it 'returns different results for different ids' do
      salt = 'same_salt'
      result1 = described_class.to_percentage(salt, 'id1')
      result2 = described_class.to_percentage(salt, 'id2')
      expect(result1).not_to eq(result2)
    end

    it 'handles integer ids' do
      result = described_class.to_percentage('salt', 123)
      expect(result).to be_between(1, 100)
    end

    it 'handles nil values gracefully' do
      result1 = described_class.to_percentage('salt', nil)
      result2 = described_class.to_percentage(nil, 'id')
      expect(result1).to be_between(1, 100)
      expect(result2).to be_between(1, 100)
    end

    it 'produces a uniform-ish distribution over many calls' do
      results = 1000.times.map { |i| described_class.to_percentage('salt', i) }

      # Check that we get values across the full range
      expect(results.min).to be >= 1
      expect(results.max).to be <= 100

      # Check that distribution isn't too skewed (rough test)
      low_count = results.count { |r| r <= 25 }
      mid_low_count = results.count { |r| r > 25 && r <= 50 }
      mid_high_count = results.count { |r| r > 50 && r <= 75 }
      high_count = results.count { |r| r > 75 }

      # Each quarter should have roughly 200-300 values (25% ± 5%)
      [low_count, mid_low_count, mid_high_count, high_count].each do |count| # rubocop:disable RSpec/IteratedExpectation
        expect(count).to be_between(150, 350)
      end
    end
  end

  describe '.percentages_to_ranges' do
    it 'handles empty array' do
      result = described_class.percentages_to_ranges([])
      expect(result).to eq([])
    end

    it 'converts single percentage to range' do
      result = described_class.percentages_to_ranges([10])
      expect(result).to eq([1..10])
    end

    it 'converts multiple percentages to consecutive ranges' do
      result = described_class.percentages_to_ranges([10, 20, 30, 40])
      expected = [1..10, 11..30, 31..60, 61..100]
      expect(result).to eq(expected)
    end

    it 'handles percentages that sum to less than 100' do
      result = described_class.percentages_to_ranges([25, 25])
      expected = [1..25, 26..50]
      expect(result).to eq(expected)
    end

    it 'handles percentages that sum to more than 100' do
      result = described_class.percentages_to_ranges([50, 60])
      expected = [1..50, 51..110]
      expect(result).to eq(expected)
    end

    it 'preserves order of input percentages' do
      result = described_class.percentages_to_ranges([5, 15, 10, 20])
      expected = [1..5, 6..20, 21..30, 31..50]
      expect(result).to eq(expected)
    end

    it 'handles large percentages' do
      result = described_class.percentages_to_ranges([1000])
      expect(result).to eq([1..1000])
    end

    it 'handles zero percentages' do
      result = described_class.percentages_to_ranges([0, 10, 0, 5])
      expected = [1..0, 1..10, 11..10, 11..15]
      expect(result).to eq(expected)
    end

    it 'handles negative percentages' do
      result = described_class.percentages_to_ranges([-5, 10])
      expected = [1..-5, -4..5]
      expect(result).to eq(expected)
    end

    it 'handles single element with 100%' do
      result = described_class.percentages_to_ranges([100])
      expect(result).to eq([1..100])
    end

    it 'handles decimal percentages' do
      result = described_class.percentages_to_ranges([10.5, 20.5])
      expected = [1..10.5, 11.5..31]
      expect(result).to eq(expected)
    end
  end
end
