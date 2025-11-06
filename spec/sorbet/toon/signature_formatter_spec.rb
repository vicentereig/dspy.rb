# frozen_string_literal: true

require 'sorbet-runtime'
require 'dspy/signature'
require 'sorbet/toon/signature_formatter'

RSpec.describe Sorbet::Toon::SignatureFormatter do
  let(:signature_class) do
    Class.new(DSPy::Signature) do
      input do
        const :query, String, description: 'Search query'
        const :filters, T::Array[String], description: 'Optional filters', default: []
      end

      output do
        const :summary, String, description: 'Key findings'
        const :sources, T::Array[
          Class.new(T::Struct) do
            prop :name, String
            prop :url, String
            prop :notes, T.nilable(String)
          end
        ], description: 'Ordered list of sources'
      end
    end
  end

  describe '.describe_signature' do
    it 'lists input fields with optional markers' do
      description = described_class.describe_signature(signature_class, :input)

      expect(description).to include('- query (String')
      expect(description).to include('- filters (Array<String>, optional')
      expect(description).to include('Search query')
    end

    it 'includes tabular guidance for array-of-struct outputs' do
      description = described_class.describe_signature(signature_class, :output)

      expect(description).to include('- sources (Array<')
      expect(description).to include('Tabular columns: name, url, notes')
    end
  end
end
