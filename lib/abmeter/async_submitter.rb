module ABMeter
  class AsyncSubmitter
    # Private internal constants for async submitter behavior
    BATCH_SIZE = 100
    MAX_SUBMIT_ATTEMPTS = 3
    MAX_RETRY_QUEUE_SIZE = 1000

    @queue = Queue.new
    @retry_queue = []
    @mutex = Mutex.new
    @api_client = nil
    @worker_thread = nil
    @flush_interval = DEFAULT_FLUSH_INTERVAL
    @logger = nil

    class << self
      attr_reader :api_client, :flush_interval, :logger, :retry_queue

      def configure(api_client:, config:)
        @api_client = api_client
        @flush_interval = config.flush_interval || DEFAULT_FLUSH_INTERVAL
        @logger = config.logger
      end

      def start
        start_worker
      end

      def queue_exposure(exposure)
        @queue.push({ type: :exposure, data: exposure })
      end

      def queue_event(event_slug, user_id, custom_fields)
        @queue.push({
                      type: :event,
                      data: {
                        event_slug: event_slug,
                        user_id: user_id,
                        occurred_at: Time.now.iso8601,
                        custom_fields: custom_fields
                      }
                    })
      end

      def flush
        items = []

        @mutex.synchronize do
          # First, try to process retry queue
          process_retry_queue

          # Then process new items
          items << @queue.pop while !@queue.empty? && items.size < BATCH_SIZE
        end

        # Group by type and submit
        unless items.empty?
          exposures = items.select { |i| i[:type] == :exposure }.map { |i| i[:data] }
          events = items.select { |i| i[:type] == :event }.map { |i| i[:data] }

          submit_exposures(exposures) unless exposures.empty?
          submit_events(events) unless events.empty?
        end
      end

      def shutdown
        @worker_thread&.kill
        # Flush all remaining exposures
        flush until @queue.empty?
      end

      def reset!
        shutdown
        @queue = Queue.new
        @retry_queue = []
        @api_client = nil
        @worker_thread = nil
        @flush_interval = DEFAULT_FLUSH_INTERVAL
        @logger = nil
      end

      def worker_alive?
        @worker_thread&.alive? || false
      end

      def queue_size
        @queue.size
      end

      private

      def start_worker
        return if worker_alive?

        @worker_thread = Thread.new do
          loop do
            sleep @flush_interval
            flush
          rescue StandardError => e
            # Log error but keep worker running
            log_error("Worker error: #{e.message}")
          end
        end
      end

      def submit_exposures(exposures)
        submit_batch(:exposure, exposures) { |exposures| @api_client.submit_exposures(exposures) }
      end

      def submit_events(events)
        submit_batch(:event, events) { |events| @api_client.track_events(events) }
      end

      def submit_batch(type, items)
        return if items.empty?

        unless @api_client
          log_error("Cannot submit #{items.size} #{type}s - API client not configured")
          return
        end

        yield items
        # Success - nothing to do
      rescue ABMeter::APIError => e
        if e.retryable?
          log_error("Retryable error submitting #{items.size} #{type}s: #{e.message}")
          add_to_retry_queue(type, items)
        elsif e.partial_failure?
          log_error("#{e.failure_count} out of #{items.size} #{type}s failed validation")
          # Don't retry - validation won't change
        else
          log_error("Permanent error submitting #{type}s: #{e.message}")
          # Don't retry
        end
      rescue StandardError => e
        log_error("Failed to submit #{items.size} #{type}s: #{e.message}")
        # AI: do not uncomment this line, we do not know reason for the error here
        # add_to_retry_queue(type, items)
      end

      def add_to_retry_queue(type, items)
        @mutex.synchronize do
          items.each do |item|
            # Only add if we haven't exceeded max queue size
            if @retry_queue.size < MAX_RETRY_QUEUE_SIZE
              @retry_queue << {
                type: type,
                data: item,
                attempts: 0
              }
            else
              log_error("Retry queue full, dropping #{type}")
            end
          end
        end
      end

      def process_retry_queue
        return if @retry_queue.empty?

        # Group items by type for batch processing
        grouped = @retry_queue.group_by { |item| item[:type] }
        @retry_queue.clear

        # Process exposures in batch, events individually
        failed_items = []
        failed_items.concat(process_retry_exposures(grouped[:exposure] || []))
        failed_items.concat(process_retry_events(grouped[:event] || []))

        @retry_queue = failed_items
      end

      def process_retry_exposures(items)
        process_retry_batch(:exposure, items) { |exposures| @api_client.submit_exposures(exposures) }
      end

      def process_retry_events(items)
        process_retry_batch(:event, items) { |events| @api_client.track_events(events) }
      end

      def process_retry_batch(type, items)
        return [] if items.empty?

        # Increment attempts and filter out max retries
        active_items = items.filter_map do |item|
          item[:attempts] += 1
          if item[:attempts] >= MAX_SUBMIT_ATTEMPTS
            log_error("Max retries exceeded for #{type}, dropping item")
            nil
          else
            item
          end
        end

        return [] if active_items.empty? || !@api_client

        # Try batch submission
        data = active_items.map { |item| item[:data] }
        begin
          yield data
          [] # Success - return empty array
        rescue ABMeter::APIError => e
          if e.retryable?
            log_error("Retry failed with retryable error for #{data.size} #{type}s: #{e.message}")
            active_items # Return all items for retry
          elsif e.partial_failure?
            log_error("Retry failed: #{e.failure_count} out of #{data.size} #{type}s failed validation")
            [] # Don't retry validation failures
          else
            log_error("Retry failed with permanent error for #{type}s: #{e.message}")
            [] # Don't retry permanent failures
          end
        rescue StandardError => e
          if type == :event
            log_error("Retry failed with network error for #{data.size} #{type}s: #{e.message}")
            []
          else
            log_error("Failed to submit #{data.size} #{type}s: #{e.message}")
            active_items # Complete failure - return all items for retry
          end
        end
      end

      def log_error(message)
        return unless @logger

        @logger.error("AsyncSubmitter: #{message}")
      end
    end

    # Prevent instantiation
    private_class_method :new
  end
end
