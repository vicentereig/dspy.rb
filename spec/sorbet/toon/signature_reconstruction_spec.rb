# frozen_string_literal: true

require 'sorbet-runtime'
require 'dspy/signature'
require 'sorbet/toon'

RSpec.describe 'Sorbet::Toon.decode with signatures' do
  module SorbetToonSignatureSpec
    class Source < T::Struct
      prop :name, String
      prop :url, String
      prop :notes, T.nilable(String)
    end

    class ReportSignature < DSPy::Signature
      input do
        const :query, String
        const :limit, Integer, default: 3
      end

      output do
        const :summary, String
        const :sources, T::Array[Source]
      end
    end
  end

  let(:signature) { SorbetToonSignatureSpec::ReportSignature }
  let(:struct_class) { signature.output_struct_class }

  let(:payload) do
    <<~TOON
      summary: Recent AI papers
      sources[2]{name,url,notes}:
        Anthropic,https://www.anthropic.com,
        OpenAI,https://openai.com,"top pick"
    TOON
  end

  after do
    Sorbet::Toon.reset_config!
  end

  it 'rehydrates Sorbet structs when a signature is provided' do
    result = Sorbet::Toon.decode(payload, signature: signature, role: :output)

    expect(result).to be_a(struct_class)
    expect(result.summary).to eq('Recent AI papers')
    expect(result.sources.length).to eq(2)
    expect(result.sources.first).to be_a(SorbetToonSignatureSpec::Source)
    expect(result.sources.last.notes).to eq('top pick')
  end

  it 'rehydrates using explicit struct_class without signature' do
    result = Sorbet::Toon.decode(payload, struct_class: struct_class)

    expect(result).to be_a(struct_class)
    expect(result.sources.first.name).to eq('Anthropic')
  end
end
