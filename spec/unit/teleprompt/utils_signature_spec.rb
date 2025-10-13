# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Teleprompt::Utils signature functions' do
  # Create a simple test signature
  class TestSignature < DSPy::Signature
    description "Answer questions"

    input do
      const :question, String, description: "A question to answer"
    end

    output do
      const :answer, String, description: "The answer"
    end
  end

  describe '.get_signature and .set_signature' do
    let(:predictor) { DSPy::Predict.new(TestSignature) }

    it 'get_signature returns signature info from predictor' do
      sig = DSPy::Teleprompt::Utils.get_signature(predictor)

      expect(sig).not_to be_nil
      # Should have instructions (from the signature or prompt)
      expect(sig).to respond_to(:instructions)
    end

    it 'allows updating instruction via signature modification' do
      # Get current signature
      sig = DSPy::Teleprompt::Utils.get_signature(predictor)
      original_instruction = sig.instructions

      # Create updated signature with new instruction
      new_instruction = "You are a helpful assistant. Answer concisely."
      updated_sig = sig.with_instructions(new_instruction)

      # Set it back
      DSPy::Teleprompt::Utils.set_signature(predictor, updated_sig)

      # Verify it changed
      current_sig = DSPy::Teleprompt::Utils.get_signature(predictor)
      expect(current_sig.instructions).to eq(new_instruction)
      expect(current_sig.instructions).not_to eq(original_instruction)
    end

    it 'preserves signature class fields when updating instructions' do
      sig = DSPy::Teleprompt::Utils.get_signature(predictor)

      updated_sig = sig.with_instructions("New instruction")
      DSPy::Teleprompt::Utils.set_signature(predictor, updated_sig)

      # Signature class should remain the same
      expect(predictor.signature_class).to eq(TestSignature)
    end

    it 'allows setting demos on predictor' do
      # In Python: predictor.demos = [...]
      # We need similar capability
      demos = [
        DSPy::FewShotExample.new(
          input: { question: "What is 2+2?" },
          output: { answer: "4" }
        )
      ]

      # Should be able to set demos
      expect { predictor.demos = demos }.not_to raise_error
      expect(predictor.demos).to eq(demos)
    end
  end

  describe '.get_signature with custom signature classes' do
    class CustomSignature < DSPy::Signature
      description "Custom base instructions"

      input do
        const :query, String, description: "User query"
      end

      output do
        const :response, String, description: "System response"
      end
    end

    it 'returns signature with custom instructions' do
      predictor = DSPy::Predict.new(CustomSignature)
      sig = DSPy::Teleprompt::Utils.get_signature(predictor)

      expect(sig.instructions).to include("Custom base instructions")
    end
  end
end
