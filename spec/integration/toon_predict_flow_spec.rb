# frozen_string_literal: true

require 'spec_helper'
require 'sorbet/toon'

class ToonPredictSource < T::Struct
  prop :name, String
  prop :url, String
end

class ToonPredictSignature < DSPy::Signature
  description 'Test signature for TOON predict flow'

  input do
    const :query, String
  end

  output do
    const :summary, String
    const :sources, T::Array[ToonPredictSource]
  end
end

RSpec.describe 'Predict + TOON end-to-end', type: :integration do
  let(:mock_adapter) { instance_double('Adapter') }
  let(:response_usage) { DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0) }
  let(:lm) do
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)
    allow(mock_adapter).to receive(:chat).and_return(
      DSPy::LM::Response.new(content: "```toon\n#{toon_response}\n```", usage: response_usage, metadata: {})
    )
    DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :toon, data_format: :toon)
  end

  let(:toon_response) do
    Sorbet::Toon.encode(
      {
        summary: 'Done',
        sources: [
          { name: 'Anthropic', url: 'https://anthropic.com' }
        ]
      },
      signature: ToonPredictSignature,
      role: :output
    )
  end

  before do
    DSPy.configure { |c| c.lm = lm }
  end

  it 'round-trips predict flow using TOON data format' do
    result = DSPy::Predict.new(ToonPredictSignature).call(query: 'latest ai research')

    expect(result.summary).to eq('Done')
    expect(result.sources.first.name).to eq('Anthropic')
  end
end
