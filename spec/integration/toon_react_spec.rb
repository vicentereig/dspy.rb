# frozen_string_literal: true

require 'spec_helper'
require 'sorbet/toon'

class ToonReActSignature < DSPy::Signature
  description 'ReAct signature for TOON data format'

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

RSpec.describe 'ReAct with TOON data format', type: :integration do

  let(:mock_adapter) { instance_double('Adapter') }
  let(:usage) { DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0) }

  before do
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)

    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :toon, data_format: :toon)
    end
  end

  it 'parses TOON tool calls in ReAct loop' do
    iteration_payload = Sorbet::Toon.encode(
      {
        thought: 'Need to finish',
        action: 'finish',
        action_input: 'answer'
      },
      signature: ToonReActSignature,
      role: :output
    )

    allow(mock_adapter).to receive(:chat).and_return(
      DSPy::LM::Response.new(content: "```toon\n#{iteration_payload}\n```", usage: usage, metadata: {})
    )

    agent = DSPy::ReAct.new(ToonReActSignature, tools: [], max_iterations: 1)
    result = agent.forward(question: 'test')

    expect(result.answer).to eq('answer')
  end
end
