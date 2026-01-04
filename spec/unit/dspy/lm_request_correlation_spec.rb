# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'LM request correlation' do
  class FakeAdapter < DSPy::LM::Adapter
    def initialize
      super(model: 'fake-model', api_key: 'fake-key')
    end

    def chat(messages:, signature: nil, &block)
      usage = DSPy::LM::Usage.new(input_tokens: 1, output_tokens: 1, total_tokens: 2)
      DSPy::LM::Response.new(
        content: '{"ok":true}',
        usage: usage,
        metadata: { provider: 'fake', model: model }
      )
    end
  end

  before do
    DSPy.events.clear_listeners
  end

  after do
    DSPy.events.clear_listeners
  end

  it 'emits distinct request_id values for concurrent fibers' do
    adapter = FakeAdapter.new
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(adapter)

    lm = DSPy::LM.new('openai/fake-model', api_key: 'fake-key')

    token_events = []
    subscription = DSPy.events.subscribe('lm.tokens') do |_event_name, attrs|
      token_events << attrs
    end

    Async do |task|
      task.async { lm.raw_chat([{ role: 'user', content: 'alpha' }]) }
      task.async { lm.raw_chat([{ role: 'user', content: 'beta' }]) }
    end

    DSPy.events.unsubscribe(subscription)

    request_ids = token_events.map { |attrs| attrs['request_id'] || attrs[:request_id] }.compact
    expect(request_ids.uniq.length).to eq(2)
  end
end
