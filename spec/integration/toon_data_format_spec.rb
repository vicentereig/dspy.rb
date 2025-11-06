# frozen_string_literal: true

require 'spec_helper'
require 'sorbet/toon'

RSpec.describe 'TOON data format integration', type: :integration do
  before do
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(double('Adapter'))
  end

  let(:signature_class) do
    Class.new(DSPy::Signature) do
      description 'Summarize research with TOON serialization'

      input do
        const :query, String
      end

      output do
        const :summary, String
        const :sources, T::Array[
          Class.new(T::Struct) do
            prop :name, String
            prop :url, String
          end
        ]
      end
    end
  end

  let(:lm) { DSPy::LM.new('test/provider', data_format: :toon) }

  it 'parses TOON output into hash' do
    toon_payload = Sorbet::Toon.encode(
      {
        summary: 'Done',
        sources: [
          { name: 'Anthropic', url: 'https://anthropic.com' },
          { name: 'OpenAI', url: 'https://openai.com' }
        ]
      },
      signature: signature_class,
      role: :output
    )

    usage = DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0)
    response = DSPy::LM::Response.new(content: "```toon\n#{toon_payload}\n```", usage: usage, metadata: {})

    parsed = lm.send(:parse_response, response, {}, signature_class)

    expect(parsed['summary']).to eq('Done')
    expect(parsed['sources'].length).to eq(2)
    expect(parsed['sources'].first['name']).to eq('Anthropic')
  end
end
