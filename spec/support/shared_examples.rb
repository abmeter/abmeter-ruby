shared_examples 'raises APIError when unauthorized' do
  include_context 'with unauthorized config'

  it 'raises an APIError' do
    expect { subject }.to raise_error(ABMeter::APIError)
  end
end

shared_examples 'successful API call' do
  it 'completes without errors' do
    expect { subject }.not_to raise_error
  end
end

shared_examples 'logs warnings when unauthorized' do |expected_warning_count|
  include_context 'with unauthorized config'

  it 'logs warnings but does not raise' do
    allow(client).to receive(:warn)
    expect { subject }.not_to raise_error
    if expected_warning_count
      expect(client).to have_received(:warn).exactly(expected_warning_count).times
    else
      expect(client).to have_received(:warn).at_least(:once)
    end
  end
end

shared_examples 'handles empty input gracefully' do
  it 'handles empty input without errors' do
    expect { subject }.not_to raise_error
  end
end
