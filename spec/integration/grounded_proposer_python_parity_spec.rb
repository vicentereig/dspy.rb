# frozen_string_literal: true

require 'spec_helper'
require 'dspy/propose/grounded_proposer'

RSpec.describe DSPy::Propose::GroundedProposer, 'Python parity', :vcr do
  let(:lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }

  before do
    DSPy.configure { |config| config.lm = lm }
  end

  let(:signature_class) do
    Class.new(DSPy::Signature) do
      description "Provide detailed, comprehensive answers to complex scientific questions"

      input do
        const :question, String
        const :context, String
      end

      output do
        const :answer, String
        const :reasoning, String
      end
    end
  end

  let(:examples) do
    [
      DSPy::Example.new(
        signature_class: signature_class,
        input: {
          question: "How does photosynthesis work at the molecular level?",
          context: "Photosynthesis is the process by which plants convert light energy into chemical energy."
        },
        expected: {
          answer: "Photosynthesis occurs in chloroplasts through light-dependent and light-independent reactions.",
          reasoning: "The process involves electron transport chains and the Calvin cycle."
        }
      ),
      DSPy::Example.new(
        signature_class: signature_class,
        input: {
          question: "What are the key principles of quantum mechanics?",
          context: "Quantum mechanics is the fundamental theory in physics describing nature at small scales."
        },
        expected: {
          answer: "Key principles include wave-particle duality, uncertainty principle, and superposition.",
          reasoning: "These principles explain behavior of particles at atomic and subatomic scales."
        }
      )
    ]
  end

  describe 'long instruction preservation', vcr: { cassette_name: 'grounded_proposer/long_instructions_preserved' } do
    it 'preserves verbose instructions without truncation' do
      proposer = described_class.new

      # Prompt the LLM to generate verbose, detailed instructions
      # by providing complex examples
      result = proposer.propose_instructions(
        signature_class,
        examples,
        few_shot_examples: []
      )

      # Verify at least one instruction is longer than 200 characters
      long_instructions = result.candidate_instructions.select { |i| i.length > 200 }
      expect(long_instructions).not_to be_empty, "Expected at least one instruction > 200 chars"

      # Verify no instructions end with truncation artifacts
      result.candidate_instructions.each do |instruction|
        # Should not end with ellipsis (clear truncation indicator)
        expect(instruction).not_to end_with('...')
        # Should end with proper sentence punctuation
        expect(instruction).to match(/[.!?]$/)
      end
    end
  end

  describe 'instruction quality over length', vcr: { cassette_name: 'grounded_proposer/quality_over_length' } do
    it 'generates and ranks instructions by quality, not length' do
      config = described_class::Config.new
      config.num_instruction_candidates = 5
      proposer = described_class.new(config: config)

      result = proposer.propose_instructions(
        signature_class,
        examples,
        few_shot_examples: []
      )

      # Should generate multiple instructions
      expect(result.candidate_instructions.size).to be >= 3

      # Instructions should vary in length (not all truncated to same length)
      lengths = result.candidate_instructions.map(&:length)
      expect(lengths.uniq.size).to be > 1, "Expected varying instruction lengths"

      # All instructions should be high quality (contain action words or reasoning indicators)
      action_words = %w[
        analyze classify generate explain solve determine identify describe evaluate
        respond provide research synthesize ensure examine assess consider review
        compare contrast investigate explore develop create formulate
      ]
      result.candidate_instructions.each do |instruction|
        has_quality = action_words.any? { |word| instruction.downcase.include?(word) }
        expect(has_quality).to be(true), "Instruction lacks quality indicators: #{instruction}"
      end
    end
  end

  describe 'config compatibility', vcr: { cassette_name: 'grounded_proposer/config_compatibility' } do
    it 'works without max_instruction_length config' do
      config = described_class::Config.new

      # Should not have max_instruction_length attribute
      expect(config).not_to respond_to(:max_instruction_length)

      proposer = described_class.new(config: config)

      # Should generate instructions successfully
      result = proposer.propose_instructions(
        signature_class,
        examples.take(1),
        few_shot_examples: []
      )

      expect(result.candidate_instructions).not_to be_empty
    end
  end
end
