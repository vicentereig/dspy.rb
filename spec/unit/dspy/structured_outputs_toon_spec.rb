# frozen_string_literal: true

require 'spec_helper'

class StructuredOutputsToonSignature < DSPy::Signature
  description 'Structured outputs TOON routing'

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

RSpec.describe 'Structured outputs routing with TOON data format' do
  before do
    DSPy.events.clear_listeners
  end

  after do
    DSPy.events.clear_listeners
  end

  it 'avoids JSON-only structured prompts when data_format is :toon' do
    skip 'Phase 3B: data_format routing for structured outputs not implemented yet'

    adapter = DSPy::OpenAI::LM::Adapters::OpenAIAdapter.new(
      model: 'gpt-4o-mini',
      api_key: 'test-key',
      structured_outputs: true
    )
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(adapter)
    allow(DSPy::OpenAI::LM::SchemaConverter)
      .to receive(:supports_structured_outputs?)
      .and_return(true)

    lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test-key', data_format: :toon)
    DSPy.configure { |c| c.lm = lm }

    predictor = DSPy::Predict.new(StructuredOutputsToonSignature)

    messages = lm.send(:build_messages, predictor, { question: 'Ping?' })
    system_prompt = messages.first.content

    expect(system_prompt).to include('TOON data format instructions')
    expect(system_prompt).to include('```toon')
  end
end
