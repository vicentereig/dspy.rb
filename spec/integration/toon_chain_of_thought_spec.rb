# frozen_string_literal: true

require 'spec_helper'
require 'sorbet/toon'

class ToonCoTSignature < DSPy::Signature
  description 'Chain of Thought signature for TOON tests'

  input do
    const :question, String
  end

  output do
    const :answer, String
    const :reasoning, String
  end
end

RSpec.describe 'ChainOfThought + TOON integration', type: :integration do

  let(:mock_adapter) { instance_double('Adapter') }
  let(:usage) { DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0) }
  let(:toon_payload) do
    Sorbet::Toon.encode({ answer: '42', reasoning: 'Because math.' }, signature: ToonCoTSignature, role: :output)
  end

  before do
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)
    allow(mock_adapter).to receive(:chat).and_return(
      DSPy::LM::Response.new(content: "```toon\n#{toon_payload}\n```", usage: usage, metadata: {})
    )

    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :toon, data_format: :toon)
    end
  end

  it 'returns ChainOfThought result with TOON parsing' do
    cot = DSPy::ChainOfThought.new(ToonCoTSignature)
    result = cot.call(question: 'life universe everything?')

    expect(result.answer).to eq('42')
    expect(result.reasoning).to include('math')
  end
end
