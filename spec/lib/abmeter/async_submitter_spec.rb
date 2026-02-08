require 'spec_helper'
require 'active_support/testing/time_helpers'
require 'active_support/core_ext/numeric/time'

describe ABMeter::AsyncSubmitter do
  include ActiveSupport::Testing::TimeHelpers

  let(:api_client) { instance_double(ABMeter::Client) }
  let(:frozen_time) { Time.parse('2026-06-28 12:00:00 +0000') }
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }
  let(:config) do
    instance_double(ABMeter::Config,
                    logger: logger,
                    flush_interval: 60)
  end

  around do |example|
    travel_to(frozen_time) do
      described_class.reset!
      example.run
    end
  end

  describe '.configure' do
    it 'sets up the reporter with provided settings' do
      described_class.configure(api_client: api_client, config: config)

      expect(described_class.api_client).to eq(api_client)
      expect(described_class.flush_interval).to eq(60)
      expect(described_class.logger).to eq(logger)
    end

    it 'does not automatically start the worker thread' do
      described_class.configure(api_client: api_client, config: config)

      expect(described_class.worker_alive?).to be false
    end
  end

  describe '.start' do
    before do
      described_class.configure(api_client: api_client, config: config)
    end

    it 'starts the worker thread' do
      expect(described_class.worker_alive?).to be false

      described_class.start

      expect(described_class.worker_alive?).to be true
    end

    it 'does not start multiple worker threads' do
      expect(Thread).to receive(:new).once.and_call_original

      described_class.start
      described_class.start

      expect(described_class.worker_alive?).to be true
    end
  end

  describe '.queue_exposure' do
    it 'adds exposures to the queue' do
      expect(described_class.queue_size).to eq(0)

      described_class.queue_exposure({ user_id: 1, parameter_id: 'param1' })
      described_class.queue_exposure({ user_id: 2, parameter_id: 'param2' })

      expect(described_class.queue_size).to eq(2)
    end
  end

  describe '.flush' do
    before do
      described_class.configure(api_client: api_client, config: config)
    end

    let(:exposures) do
      [
        { user_id: 1, parameter_id: 'param1', resolved_value: 'A', resolved_at: frozen_time },
        { user_id: 1, parameter_id: 'param2', resolved_value: 'B', resolved_at: frozen_time },
        { user_id: 2, parameter_id: 'param1', resolved_value: 'A', resolved_at: frozen_time }
      ]
    end

    it 'submits all exposures in a single call' do
      exposures.each { |e| described_class.queue_exposure(e) }

      expect(api_client).to receive(:submit_exposures).once.with(
        array_including(
          hash_including(parameter_id: 'param1', user_id: 1),
          hash_including(parameter_id: 'param2', user_id: 1),
          hash_including(parameter_id: 'param1', user_id: 2)
        )
      )

      described_class.flush
    end

    it 'respects batch size limit' do
      allow(api_client).to receive(:submit_exposures)

      (ABMeter::AsyncSubmitter::BATCH_SIZE + 1).times do |i|
        described_class.queue_exposure({ user_id: i, parameter_id: "param#{i}", resolved_at: frozen_time })
      end

      expect(api_client).to receive(:submit_exposures).once do |args|
        expect(args[:exposures].size).to eq(100)
      end

      described_class.flush

      expect(described_class.queue_size).to eq(1)
    end

    it 'handles API errors gracefully' do
      allow(api_client).to receive(:submit_exposures).and_raise(StandardError, 'API Error')
      expect(config.logger).to receive(:error).with(/Failed to submit .* exposures/).at_least(:once)

      exposures.each { |e| described_class.queue_exposure(e) }
      expect { described_class.flush }.not_to raise_error
    end

    context 'with empty queue' do
      it 'does not call api_client' do
        expect(api_client).not_to receive(:submit_exposures)
        described_class.flush
      end
    end
  end

  describe '.shutdown' do
    before do
      described_class.configure(api_client: api_client, config: config)
      described_class.start
    end

    it 'stops the worker thread' do
      expect(described_class.worker_alive?).to be true

      described_class.shutdown
      sleep 0.1 # Give thread time to stop

      expect(described_class.worker_alive?).to be false
    end

    it 'flushes remaining exposures' do
      described_class.queue_exposure({ user_id: 1, parameter_id: 'param1', resolved_at: frozen_time })

      expect(api_client).to receive(:submit_exposures)

      described_class.shutdown
    end

    it 'flushes all exposures on shutdown' do
      described_class.configure(api_client: api_client, config: config)

      expect(5).to be < ABMeter::AsyncSubmitter::BATCH_SIZE
      expect(described_class.queue_size).to eq(0)

      5.times do |i|
        described_class.queue_exposure({ user_id: i + 1, parameter_id: "param#{i}", resolved_at: frozen_time })
      end

      expect(api_client).to receive(:submit_exposures).once

      described_class.shutdown

      expect(described_class.queue_size).to eq(0)
    end
  end

  describe '.reset!' do
    before do
      allow(api_client).to receive(:submit_exposures)
      described_class.configure(api_client: api_client, config: config)
      described_class.start
      described_class.queue_exposure({ user_id: 1, parameter_id: 'param1' })
    end

    it 'stops worker thread and clears all state' do
      expect(described_class.worker_alive?).to be true
      expect(described_class.queue_size).to eq(1)

      described_class.reset!

      expect(described_class.worker_alive?).to be false
      expect(described_class.queue_size).to eq(0)
      expect(described_class.api_client).to be_nil
      expect(described_class.logger).to be_nil
    end
  end

  describe 'worker thread behavior' do
    let(:config_with_short_interval) do
      instance_double(ABMeter::Config,
                      logger: logger,
                      log_level: :warn,
                      flush_interval: 0.1)
    end

    before do
      described_class.configure(api_client: api_client, config: config_with_short_interval)
      described_class.start
    end

    it 'periodically flushes exposures' do
      expect(api_client).to receive(:submit_exposures).at_least(:once)

      described_class.queue_exposure({ user_id: 1, parameter_id: 'param1', resolved_at: frozen_time })

      # Wait for actual time to pass (not using time travel since it doesn't affect sleep in threads)
      sleep 0.3
    end

    it 'continues running after errors' do
      # Mock the flush method to raise an error
      call_count = 0
      allow(described_class).to receive(:flush) do
        call_count += 1
        raise StandardError, 'Flush error' if call_count == 1
      end

      expect(config.logger).to receive(:error).with(/Worker error/).at_least(:once)

      # Wait for worker to attempt flush
      sleep 0.3

      expect(described_class.worker_alive?).to be true
    end
  end

  describe 'exposure data formatting' do
    before do
      described_class.configure(api_client: api_client, config: config)
    end

    it 'formats exposure data correctly for API' do
      exposure = {
        user_id: 1,
        parameter_id: 'test_param',
        resolved_value: 'variant_a',
        exposable_type: 'Feature',
        exposable_id: '123',
        audience_id: 'aud_456',
        resolved_at: frozen_time
      }

      described_class.queue_exposure(exposure)

      expect(api_client).to receive(:submit_exposures).with([exposure])

      described_class.flush
    end
  end

  describe 'retry mechanism' do
    before do
      described_class.configure(api_client: api_client, config: config)
    end

    let(:retryable_error) { ABMeter::APIError.new(instance_double(Faraday::Response, body: 'Server Error', status: 500)) }

    context 'when API submission fails' do
      let(:exposure) { { user_id: 1, parameter_id: 'param1', resolved_at: frozen_time } }

      before do
        described_class.queue_exposure(exposure)
      end

      it 'adds failed items to retry queue for retryable errors' do
        allow(api_client).to receive(:submit_exposures).and_raise(retryable_error)
        expect(config.logger).to receive(:error).with(/Retryable error submitting/).at_least(:once)

        described_class.flush

        retry_queue = described_class.retry_queue
        expect(retry_queue.size).to eq(1)
        expect(retry_queue.first[:type]).to eq(:exposure)
        expect(retry_queue.first[:attempts]).to eq(0)
      end

      it 'retries failed items on subsequent flushes' do
        expect(api_client).to receive(:submit_exposures).once.and_raise(retryable_error)
        described_class.flush

        retry_queue = described_class.retry_queue
        expect(retry_queue.size).to eq(1)

        expect(api_client).to receive(:submit_exposures).once
          .with([exposure])

        described_class.flush

        retry_queue = described_class.retry_queue
        expect(retry_queue).to be_empty
      end

      it 'increments attempt count on each retry' do
        allow(api_client).to receive(:submit_exposures).and_raise(retryable_error)

        described_class.flush

        expect(described_class.retry_queue.first[:attempts]).to eq(0)

        described_class.flush
        expect(described_class.retry_queue.first[:attempts]).to eq(1)

        described_class.flush
        expect(described_class.retry_queue.first[:attempts]).to eq(2)
      end

      it 'does not retry StandardError exceptions' do
        allow(api_client).to receive(:submit_exposures).and_raise(StandardError, 'Boom!')
        expect(config.logger).to receive(:error).with(/Failed to submit/).once

        described_class.flush

        expect(described_class.retry_queue).to be_empty
      end

      it 'drops items after max_submit_attempts' do
        max_submit_attempts = ABMeter::AsyncSubmitter::MAX_SUBMIT_ATTEMPTS
        allow(api_client).to receive(:submit_exposures).and_raise(retryable_error)
        allow(logger).to receive(:error).with(/Retryable error submitting/).at_least(:once)
        allow(logger).to receive(:error).with(/Retry failed/).at_least(:once)
        expect(logger).to receive(:error).with(/Max retries exceeded/).once

        (max_submit_attempts + 1).times { described_class.flush }

        expect(described_class.retry_queue).to be_empty
      end
    end

    context 'with mixed exposures and events' do
      it 'handles both types in retry queue' do
        described_class.configure(api_client: api_client, config: config)

        # Queue both exposures and events
        described_class.queue_exposure({ user_id: 1, parameter_id: 'param1' })
        described_class.queue_event('test_event', 'user123', { value: 42 })

        # Both fail on first attempt with retryable errors
        retryable_error = ABMeter::APIError.new(instance_double(Faraday::Response, body: 'Server Error', status: 503))
        allow(api_client).to receive(:submit_exposures).and_raise(retryable_error)
        allow(api_client).to receive(:track_events).and_raise(retryable_error)

        described_class.flush

        expect(described_class.retry_queue.size).to eq(2)
        expect(described_class.retry_queue.map { |item| item[:type] }).to contain_exactly(:exposure, :event)

        allow(api_client).to receive(:submit_exposures)
        allow(api_client).to receive(:track_events)

        described_class.flush

        expect(described_class.retry_queue).to be_empty
      end
    end
  end
end
