# frozen_string_literal: true

require 'spec_helper'

describe 'Assignment Algorithm Fairness' do
  describe 'NumUtils.to_percentage' do
    it 'produces uniform distribution across large sample' do
      salt = 'test-salt'
      sample_size = 100_000
      buckets = Hash.new(0)
      
      sample_size.times do |i|
        percentage = ABMeter::Core::Utils::NumUtils.to_percentage(salt, "user-#{i}")
        bucket = (percentage - 1) / 10 # 0-9 for percentages 1-100
        buckets[bucket] += 1
      end
      
      # Each bucket should have ~10% of users (10,000 each)
      expected_per_bucket = sample_size / 10
      tolerance = expected_per_bucket * 0.03 # 3% tolerance for randomness
      
      10.times do |bucket|
        actual = buckets[bucket]
        expect(actual).to be_within(tolerance).of(expected_per_bucket)
      end
      
      # chi-square statistic: χ² = Σ((observed - expected)² / expected)
      chi_square = buckets.values.sum do |observed|
        expected = expected_per_bucket.to_f
        ((observed - expected) ** 2) / expected
      end
      
      # Chi-square critical value for 9 degrees of freedom at 0.05 significance
      # https://en.wikipedia.org/wiki/Chi-squared_distribution#Table_of_critical_values
      critical_value = 16.919
      expect(chi_square).to be < critical_value
    end
    
    it 'produces consistent results for same salt and user' do
      salt = 'test-salt'
      user_id = 'user-123'
      
      results = 10.times.map do
        ABMeter::Core::Utils::NumUtils.to_percentage(salt, user_id)
      end
      
      expect(results.uniq.size).to eq(1)
    end
    
    it 'produces different results for different salts' do
      user_id = 'user-123'
      
      result1 = ABMeter::Core::Utils::NumUtils.to_percentage('salt1', user_id)
      result2 = ABMeter::Core::Utils::NumUtils.to_percentage('salt2', user_id)
      
      expect(result1).not_to eq(result2)
    end
    
    it 'has minimal mathematical bias in percentage distribution' do
      salt = 'test-salt'
      sample_size = 1_000_000
      
      # Count how many times each percentage value appears
      # We expect each percentage (1-100) to appear ~10,000 times in a sample of 1M
      percentage_counts = Hash.new(0)
      
      sample_size.times do |i|
        percentage = ABMeter::Core::Utils::NumUtils.to_percentage(salt, "user-#{i}")
        percentage_counts[percentage] += 1
      end
      
      # Calculate expected count per percentage
      # With 1M samples and 100 possible percentages, each should get ~10,000
      expected_per_percentage = sample_size / 100.0
      
      # Calculate average deviation from expected uniform distribution
      # Mean Absolute Deviation is more intuitive than max deviation:
      # - Shows typical deviation rather than worst case
      # - Not influenced by single outliers
      # Formula: average of all |observed - expected| / expected * 100
      deviations = percentage_counts.values.map do |count|
        ((count - expected_per_percentage).abs / expected_per_percentage) * 100
      end
      mean_absolute_deviation = deviations.sum / deviations.size
      
      # SHA256 + multiply-and-shift method provides good uniformity:
      # - SHA256 is cryptographically uniform, using 64 bits (first 16 hex chars)
      # - Multiply-and-shift ((num * 100) >> 64) avoids modulo bias
      # - This is an industry-standard approach used by major A/B testing platforms
      # 
      # An average deviation of < 1% indicates excellent uniformity.
      # This means that on average, each percentage bucket is within 1% of
      # its expected value, ensuring fair assignment for A/B test results
      # and reliable statistical significance calculations.
      expect(mean_absolute_deviation).to be < 1.0
    end
  end
  
  describe 'Space allocation fairness' do
    let(:config) do
      ABMeter::Core::AssignmentConfig.from_json({
        spaces: [{ id: 1, salt: 'space-salt' }],
        parameters: [
          { id: 1, slug: 'button_color', parameter_type: 'String', default_value: 'blue', space_id: 1 },
          { id: 2, slug: 'price_increase', parameter_type: 'Float', default_value: '0', space_id: 1 }
        ],
        experiments: [
          {
            id: 1,
            space_id: 1,
            range: [1, 50], # 50% allocation
            audience_variants: [
              { audience: { id: 1, type: 'random', range: [1, 100] }, 
                variant: { id: 1, parameter_values: [{ slug: 'button_color', value: 'green' }] } }
            ]
          },
          {
            id: 2,
            space_id: 1,
            range: [51, 100], # 50% allocation
            audience_variants: [
              { audience: { id: 2, type: 'random', range: [1, 100] }, 
                variant: { id: 2, parameter_values: [{ slug: 'price_increase', value: '0.2' }] } }
            ]
          }
        ],
        feature_flags: []
      }.to_json)
    end
    
    let(:resolver) { ABMeter::Core::UserParameterResolver.new(config: config) }
    
    it 'allocates users evenly between experiments' do
      sample_size = 10_000
      experiment_counts = Hash.new(0)
      
      sample_size.times do |i|
        user = ABMeter::Core::User.new(user_id: "user-#{i}", email: "user-#{i}@test.com")
        
        # Check which experiment user is in by looking at exposable_id
        color_exposure = resolver.exposure_for(user: user, parameter_slug: 'button_color')
        price_exposure = resolver.exposure_for(user: user, parameter_slug: 'price_increase')
        
        if color_exposure[:exposable_id] == 1
          experiment_counts[1] += 1
        elsif price_exposure[:exposable_id] == 2
          experiment_counts[2] += 1
        end
      end
      
      # Each experiment should get ~50% of users
      expected_per_experiment = sample_size / 2
      tolerance = expected_per_experiment * 0.03 # 3% tolerance
      
      expect(experiment_counts[1]).to be_within(tolerance).of(expected_per_experiment)
      expect(experiment_counts[2]).to be_within(tolerance).of(expected_per_experiment)
      
      # Verify mutual exclusion - total should equal sample size
      total_in_experiments = experiment_counts[1] + experiment_counts[2]
      expect(total_in_experiments).to eq(sample_size)
    end
    
    it 'ensures mutual exclusion within a space' do
      sample_size = 1_000
      
      sample_size.times do |i|
        user = ABMeter::Core::User.new(user_id: "user-#{i}", email: "user-#{i}@test.com")
        
        color_exposure = resolver.exposure_for(user: user, parameter_slug: 'button_color')
        price_exposure = resolver.exposure_for(user: user, parameter_slug: 'price_increase')
        
        in_color_experiment = color_exposure[:resolved_value] == 'green'
        in_price_experiment = price_exposure[:resolved_value] == 0.2
        
        # User should be in exactly one experiment (XOR)
        # Both false is OK (user not in any experiment), but both true is not
        expect(in_color_experiment && in_price_experiment).to be false
      end
    end
  end
  
  describe 'Control group independence' do
    let(:config) do
      ABMeter::Core::AssignmentConfig.from_json({
        spaces: [{ id: 1, salt: 'space-salt' }],
        parameters: [
          { id: 1, slug: 'button_color', parameter_type: 'String', default_value: 'blue', space_id: 1 },
          { id: 2, slug: 'price_increase', parameter_type: 'Float', default_value: '0', space_id: 1 }
        ],
        experiments: [
          {
            id: 1,
            space_id: 1,
            range: [1, 50],
            audience_variants: [
              { audience: { id: 1, type: 'random', range: [1, 50] }, variant: nil },
              { audience: { id: 2, type: 'random', range: [51, 100] }, 
                variant: { id: 1, parameter_values: [{ slug: 'button_color', value: 'green' }] } }
            ]
          },
          {
            id: 2,
            space_id: 1,
            range: [51, 100],
            audience_variants: [
              { audience: { id: 3, type: 'random', range: [1, 50] }, variant: nil },
              { audience: { id: 4, type: 'random', range: [51, 100] }, 
                variant: { id: 2, parameter_values: [{ slug: 'price_increase', value: '0.2' }] } }
            ]
          }
        ],
        feature_flags: []
      }.to_json)
    end
    
    let(:resolver) { ABMeter::Core::UserParameterResolver.new(config: config) }
    
    it 'ensures control groups have similar user quality across experiments' do
      # Generate users with predetermined purchase behavior
      users = 10_000.times.map do |i|
        user = ABMeter::Core::User.new(user_id: "user-#{i}", email: "user-#{i}@test.com")
        
        # Simulate that each user has an inherent purchase probability
        # This is independent of experiment assignment
        inherent_purchase_probability = (i % 100) / 100.0
        
        { user: user, purchase_probability: inherent_purchase_probability }
      end
      
      # Separate users by experiment and control/test
      color_control = []
      color_test = []
      price_control = []
      price_test = []
      
      users.each do |user_data|
        user = user_data[:user]
        
        color_exposure = resolver.exposure_for(user: user, parameter_slug: 'button_color')
        price_exposure = resolver.exposure_for(user: user, parameter_slug: 'price_increase')
        
        if color_exposure[:exposable_id] == 1
          if color_exposure[:resolved_value] == 'blue'
            color_control << user_data[:purchase_probability]
          else
            color_test << user_data[:purchase_probability]
          end
        elsif price_exposure[:exposable_id] == 2
          if price_exposure[:resolved_value] == 0
            price_control << user_data[:purchase_probability]
          else
            price_test << user_data[:purchase_probability]
          end
        end
      end
      
      # Calculate average purchase probability for each group
      color_control_avg = color_control.sum / color_control.size.to_f
      price_control_avg = price_control.sum / price_control.size.to_f
      
      puts "Color experiment control avg: #{color_control_avg}"
      puts "Price experiment control avg: #{price_control_avg}"
      puts "Difference: #{(color_control_avg - price_control_avg).abs}"
      
      # The averages should be very close (within 2%)
      expect(color_control_avg).to be_within(0.02).of(price_control_avg)
      
      # Also verify test groups
      color_test_avg = color_test.sum / color_test.size.to_f
      price_test_avg = price_test.sum / price_test.size.to_f
      
      expect(color_test_avg).to be_within(0.02).of(price_test_avg)
    end
    
    it 'demonstrates that control group differences decrease with larger sample sizes' do
      # This test verifies a fundamental statistical principle: as sample size increases,
      # the difference between control groups should decrease due to the law of large numbers.
      # We use deterministic purchase behavior to isolate the effect of sample size.
      sample_sizes = [100, 500, 1000, 5000, 10000]
      differences = []
      
      sample_sizes.each do |sample_size|
        users = sample_size.times.map do |i|
          user = ABMeter::Core::User.new(user_id: "user-#{i}", email: "user-#{i}@test.com")
          
          # Deterministic purchase probability based on user index
          # This creates a consistent 60% conversion rate
          { user: user, will_purchase: (i % 10) < 6 }
        end
        
        color_control_purchases = 0
        price_control_purchases = 0
        color_control_count = 0
        price_control_count = 0
        
        users.each do |user_data|
          user = user_data[:user]
          
          color_exposure = resolver.exposure_for(user: user, parameter_slug: 'button_color')
          price_exposure = resolver.exposure_for(user: user, parameter_slug: 'price_increase')
          
          if color_exposure[:exposable_id] == 1 && color_exposure[:resolved_value] == 'blue'
            color_control_count += 1
            color_control_purchases += 1 if user_data[:will_purchase]
          elsif price_exposure[:exposable_id] == 2 && price_exposure[:resolved_value] == 0
            price_control_count += 1
            price_control_purchases += 1 if user_data[:will_purchase]
          end
        end
        
        if color_control_count > 0 && price_control_count > 0
          color_rate = color_control_purchases.to_f / color_control_count
          price_rate = price_control_purchases.to_f / price_control_count
          difference = (color_rate - price_rate).abs
          
          differences << difference
          
          puts "Sample size #{sample_size}: Color control #{(color_rate * 100).round(1)}%, " \
               "Price control #{(price_rate * 100).round(1)}%, Difference: #{(difference * 100).round(1)}%"
        end
      end
      
      # Assert that differences generally decrease with sample size
      # We check that the average difference for larger samples is less than for smaller samples
      small_sample_avg = differences[0..1].sum / 2.0  # Average of 100 and 500 samples
      large_sample_avg = differences[3..4].sum / 2.0  # Average of 5000 and 10000 samples
      
      expect(large_sample_avg).to be < small_sample_avg
      
      # Also verify that the largest sample has a reasonably small difference
      expect(differences.last).to be < 0.05  # Less than 5% difference for 10K samples
    end
  end
  
end