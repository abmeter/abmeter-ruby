require 'spec_helper'

describe ABMeter::ErrorSafety do
  around do |example|
    ABMeter.reset!
    example.run
  end

  describe 'error handling' do
    let(:logger) { instance_double(Logger) }
    let(:error_callback) { instance_double(Proc) }
    let(:test_error) { StandardError.new('Test error') }

    before do
      ABMeter.configure do |config|
        config.api_key = 'test_key'
        config.logger = logger
        config.error_callback = error_callback
      end
    end

    describe '#track_event' do
      it 'returns nil when an error occurs' do
        expect(ABMeter::AsyncSubmitter).to receive(:queue_event).and_raise(test_error)
        expect(logger).to receive(:error).with(/Failed to execute track_event: StandardError - Test error/)
        expect(error_callback).to receive(:call).with(test_error)
        result = ABMeter.track_event('test_event', 'user123', { value: 100 })
        expect(result).to be_nil
      end
    end

    describe '#resolve_parameter' do
      let(:resolver_provider) { instance_double(ABMeter::ResolverProvider) }

      it 'returns nil when an error occurs' do
        expect(ABMeter).to receive(:resolver_provider).and_return(resolver_provider)
        expect(resolver_provider).to receive(:resolve_parameter).and_raise(test_error)
        expect(logger).to receive(:error).with(/Failed to execute resolve_parameter: StandardError - Test error/)
        expect(error_callback).to receive(:call).with(test_error)
        result = ABMeter.resolve_parameter(user: { id: 'user123' }, parameter_slug: 'test_param')
        expect(result).to be_nil
      end
    end

    describe '#get_exposure' do
      let(:resolver_provider) { instance_double(ABMeter::ResolverProvider) }

      it 'returns nil when an error occurs' do
        expect(ABMeter).to receive(:resolver_provider).and_return(resolver_provider)
        expect(resolver_provider).to receive(:get_exposure).and_raise(test_error)
        expect(logger).to receive(:error).with(/Failed to execute get_exposure: StandardError - Test error/)
        expect(error_callback).to receive(:call).with(test_error)
        result = ABMeter.get_exposure(user: { id: 'user123' }, parameter_slug: 'test_param')
        expect(result).to be_nil
      end
    end

    describe 'error callback error handling' do
      let(:callback_error) { StandardError.new('Callback error') }

      it 'handles errors in the error callback' do
        expect(error_callback).to receive(:call).and_raise(callback_error)
        expect(ABMeter::AsyncSubmitter).to receive(:queue_event).and_raise(test_error)
        expect(logger).to receive(:error).with(/Failed to execute track_event: StandardError - Test error/)
        expect(logger).to receive(:error).with(/Error in error callback: StandardError - Callback error/)

        result = ABMeter.track_event('test_event', 'user123', { value: 100 })
        expect(result).to be_nil
      end
    end

    describe 'without logger' do
      before do
        ABMeter.configure do |config|
          config.api_key = 'test_key'
          config.logger = nil
        end
      end

      it 'does not raise error when logger is nil' do
        expect(ABMeter::AsyncSubmitter).to receive(:queue_event).and_raise(test_error)
        expect { ABMeter.track_event('test_event', 'user123', { value: 100 }) }.not_to raise_error
      end
    end

    describe 'without error callback' do
      before do
        ABMeter.configure do |config|
          config.api_key = 'test_key'
          config.logger = logger
          config.error_callback = nil
        end
      end

      it 'does not raise error when error_callback is nil' do
        expect(ABMeter::AsyncSubmitter).to receive(:queue_event).and_raise(test_error)
        expect(logger).to receive(:error).with(/Failed to execute track_event: StandardError - Test error/)
        expect { ABMeter.track_event('test_event', 'user123', { value: 100 }) }.not_to raise_error
      end
    end
  end

  describe 'DSL functionality' do
    it 'successfully applies error_safe to methods' do
      # This test verifies that the DSL correctly wraps the methods
      expect(ABMeter.singleton_class.instance_methods).to include(:track_event)
      expect(ABMeter.singleton_class.instance_methods).to include(:resolve_parameter)
      expect(ABMeter.singleton_class.instance_methods).to include(:get_exposure)
    end
  end
end
