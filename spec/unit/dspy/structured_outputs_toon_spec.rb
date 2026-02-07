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
    fake_adapter_class = Class.new(DSPy::LM::Adapter) do
      def self.name
        'DSPy::OpenAI::LM::Adapters::OpenAIAdapter'
      end

      def initialize
        super(model: 'fake-model', api_key: 'fake-key')
      end
    end

    adapter = fake_adapter_class.new
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(adapter)
    lm = DSPy::LM.new('openai/fake-model', api_key: 'fake-key', data_format: :toon)
    DSPy.configure { |c| c.lm = lm }

    predictor = DSPy::Predict.new(StructuredOutputsToonSignature)

    messages = lm.send(:build_messages, predictor, { question: 'Ping?' })
    system_prompt = messages.first.content

    expect(system_prompt).to include('TOON data format instructions')
    expect(system_prompt).to include('```toon')
  end
end
