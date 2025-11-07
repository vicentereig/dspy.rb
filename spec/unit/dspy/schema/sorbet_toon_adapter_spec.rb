# frozen_string_literal: true

require 'spec_helper'
require 'sorbet/toon'
require 'dspy/schema/sorbet_toon_adapter'

RSpec.describe DSPy::Schema::SorbetToonAdapter do
  class AdapterTestSignature < DSPy::Signature
    description 'Adapter test signature'

    input do
      const :query, String
    end

    output do
      const :answer, String
    end
  end

  describe '.parse_output' do
    it 'raises AdapterError with helpful message when decode fails' do
      logger = double('Logger', warn: nil)
      allow(DSPy).to receive(:logger).and_return(logger)

      expect(logger).to receive(:warn).with(hash_including(event: 'toon.decode_error'))
      invalid_payload = "foo\n  bar"

      expect do
        described_class.parse_output(AdapterTestSignature, invalid_payload)
      end.to raise_error(DSPy::LM::AdapterError, /Failed to parse TOON/)
    end
  end
end
