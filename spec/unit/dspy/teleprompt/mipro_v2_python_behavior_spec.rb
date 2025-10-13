# frozen_string_literal: true

require 'spec_helper'
require 'dspy/teleprompt/mipro_v2'

RSpec.describe DSPy::Teleprompt::MIPROv2, 'Python-compatible behavior' do
  let(:optimizer) { described_class.new }

  describe 'diversity calculation' do
    it 'calculates diversity without instruction length' do
      # Create candidates with different instruction lengths
      short_candidate = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: "Short instruction.",  # 18 chars
        few_shot_examples: [double('example')] * 5,  # 5 examples
        type: DSPy::Teleprompt::CandidateType::Combined,
        metadata: {},
        config_id: "test1"
      )

      long_candidate = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: "This is a much longer instruction that contains more detail." * 5,  # 300+ chars
        few_shot_examples: [double('example')] * 5,  # 5 examples (same count)
        type: DSPy::Teleprompt::CandidateType::Combined,
        metadata: {},
        config_id: "test2"
      )

      # Diversity should be same since few-shot count is identical
      # Instruction length should NOT affect diversity
      short_diversity = optimizer.send(:calculate_diversity_score, short_candidate)
      long_diversity = optimizer.send(:calculate_diversity_score, long_candidate)

      expect(short_diversity).to eq(long_diversity)
      expect(short_diversity).to eq(0.5)  # 5 / 10.0, capped at 1.0
    end

    it 'bases diversity only on few-shot example count' do
      no_examples = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: "Any instruction here",
        few_shot_examples: [],
        type: DSPy::Teleprompt::CandidateType::InstructionOnly,
        metadata: {},
        config_id: "test3"
      )

      many_examples = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: "Any instruction here",
        few_shot_examples: [double('example')] * 10,
        type: DSPy::Teleprompt::CandidateType::Combined,
        metadata: {},
        config_id: "test4"
      )

      no_examples_diversity = optimizer.send(:calculate_diversity_score, no_examples)
      many_examples_diversity = optimizer.send(:calculate_diversity_score, many_examples)

      expect(no_examples_diversity).to eq(0.0)  # 0 / 10.0
      expect(many_examples_diversity).to eq(1.0)  # 10 / 10.0, capped
    end
  end

  describe 'feature extraction' do
    it 'does not cap instruction length features' do
      short_instruction = "Short."  # 6 chars
      long_instruction = "X" * 500  # 500 chars

      short_candidate = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: short_instruction,
        few_shot_examples: [],
        type: DSPy::Teleprompt::CandidateType::InstructionOnly,
        metadata: {},
        config_id: "test5"
      )

      long_candidate = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: long_instruction,
        few_shot_examples: [],
        type: DSPy::Teleprompt::CandidateType::InstructionOnly,
        metadata: {},
        config_id: "test6"
      )

      short_features = optimizer.send(:encode_candidates_for_gp, [short_candidate]).first
      long_features = optimizer.send(:encode_candidates_for_gp, [long_candidate]).first

      # Feature 4 (index 3) is instruction length (if present)
      # Should be length/100.0 with NO cap at 2.0
      expect(short_features[3]).to eq(6.0 / 100.0)  # 0.06
      expect(long_features[3]).to eq(500.0 / 100.0)  # 5.0 (not capped at 2.0)
    end
  end
end
