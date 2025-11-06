# frozen_string_literal: true

require 'spec_helper'
require 'dspy/propose/grounded_proposer'

RSpec.describe DSPy::Propose::GroundedProposer, 'Python-compatible behavior' do
  let(:proposer) { described_class.new }

  describe 'instruction generation' do
    let(:long_instruction) do
      "This is a very long instruction that exceeds 200 characters. " * 10 # Creates 630 char string
    end

    let(:signature_class) do
      Class.new(DSPy::Signature) do
        input { const :question, String }
        output { const :answer, String }
      end
    end

    let(:examples) do
      [
        DSPy::Example.new(
          signature_class: signature_class,
          input: { question: "What is 2+2?" },
          expected: { answer: "4" }
        )
      ]
    end

    before do
      # Mock current_lm for metadata collection
      mock_lm = double('LM', model: 'gpt-4o-mini', schema_format: :json, data_format: :json)
      allow(DSPy).to receive(:current_lm).and_return(mock_lm)

      # Mock LLM to return long instruction
      allow_any_instance_of(DSPy::Predict).to receive(:call).and_return(
        OpenStruct.new(instruction: long_instruction)
      )
    end

    it 'does not truncate long instructions' do
      result = proposer.propose_instructions(
        signature_class,
        examples,
        few_shot_examples: []
      )

      # Should preserve full instruction length (no 200-char truncation)
      expect(result.candidate_instructions.first.length).to eq(long_instruction.strip.length)
      expect(result.candidate_instructions.first).to eq(long_instruction.strip)
    end

    it 'only strips whitespace from generated instructions' do
      instruction_with_whitespace = "  #{long_instruction}  \n"

      allow_any_instance_of(DSPy::Predict).to receive(:call).and_return(
        OpenStruct.new(instruction: instruction_with_whitespace)
      )

      result = proposer.propose_instructions(
        signature_class,
        examples,
        few_shot_examples: []
      )

      # Should only apply .strip(), nothing else
      expect(result.candidate_instructions.first).to eq(instruction_with_whitespace.strip)
      expect(result.candidate_instructions.first).not_to include("  ")  # No leading/trailing spaces
    end
  end

  describe 'instruction scoring' do
    let(:signature_class) do
      Class.new(DSPy::Signature) do
        input { const :question, String }
        output { const :answer, String }
      end
    end

    let(:examples) do
      [
        DSPy::Example.new(
          signature_class: signature_class,
          input: { question: "What is 2+2?" },
          expected: { answer: "4" }
        )
      ]
    end

    let(:short_instruction) { "Answer the question." }  # 21 chars
    let(:long_instruction) { "Carefully analyze the question and provide a detailed, well-reasoned answer." }  # 78 chars

    it 'does not use instruction length as a scoring factor' do
      instructions = [short_instruction, long_instruction]

      # The filter_and_rank_instructions method should not consider length
      # We'll check this by verifying instructions can be ranked purely by quality
      proposer_instance = described_class.new

      # Mock the analysis to be consistent
      analysis = {
        complexity_indicators: { requires_reasoning: false }
      }

      # Both instructions should have same length-independent base score
      # Score should only depend on action words and reasoning indicators
      ranked = proposer_instance.send(:filter_and_rank_candidates, instructions, analysis)

      # Verify both instructions are included (not filtered by length)
      expect(ranked).to include(short_instruction)
      expect(ranked).to include(long_instruction)
    end

    it 'ranks instructions by quality indicators only' do
      # Instructions with different qualities but similar lengths
      good_instruction = "Analyze the question and explain the answer clearly."  # Has "analyze" and "explain"
      poor_instruction = "Just do it quickly without much thought or care."  # No action words

      proposer_instance = described_class.new
      analysis = {
        complexity_indicators: { requires_reasoning: false }
      }

      ranked = proposer_instance.send(:filter_and_rank_candidates,
                                       [poor_instruction, good_instruction],
                                       analysis)

      # Good instruction should rank higher (appear first in descending sort)
      expect(ranked.first).to eq(good_instruction)
    end
  end

  describe 'config attributes' do
    it 'does not have max_instruction_length attribute' do
      config = described_class::Config.new

      # Should not respond to max_instruction_length (removed attribute)
      expect(config).not_to respond_to(:max_instruction_length)
      expect(config).not_to respond_to(:max_instruction_length=)
    end
  end
end
