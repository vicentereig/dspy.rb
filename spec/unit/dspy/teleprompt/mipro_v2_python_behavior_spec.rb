# frozen_string_literal: true

require 'spec_helper'
require 'dspy/teleprompt/mipro_v2'
require 'dspy/few_shot_example'

module MIPROv2MultiPredictorSpec
  class Prompt
    attr_accessor :instruction, :few_shot_examples

    def initialize(instruction)
      @instruction = instruction
      @few_shot_examples = []
    end
  end

  class Predictor
    attr_accessor :prompt, :demos

    def initialize(instruction)
      @prompt = Prompt.new(instruction)
      @demos = []
    end

    def clone
      duplicated = self.class.new(@prompt.instruction.dup)
      duplicated.demos = @demos.map { |demo| demo }
      duplicated.prompt.few_shot_examples = @prompt.few_shot_examples.map { |demo| demo }
      duplicated
    end
  end

  class Program
    attr_reader :predictors, :global_instruction, :global_examples

    def initialize(predictors)
      @predictors = predictors
      @global_instruction = nil
      @global_examples = nil
    end

    def clone
      cloned_predictors = @predictors.map(&:clone)
      self.class.new(cloned_predictors)
    end

    def with_instruction(instruction)
      @global_instruction = instruction
      self
    end

    def with_examples(examples)
      @global_examples = examples
      self
    end
  end
end

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

  describe 'multi-predictor handling' do
    let(:few_shot_a) do
      DSPy::FewShotExample.new(
        input: { question: "One?", context: "Context A" },
        output: { answer: "Answer A" },
        reasoning: "Reasoning A"
      )
    end

    let(:few_shot_b) do
      DSPy::FewShotExample.new(
        input: { question: "Two?", context: "Context B" },
        output: { answer: "Answer B" },
        reasoning: "Reasoning B"
      )
    end

    let(:proposal_result) do
      DSPy::Propose::GroundedProposer::ProposalResult.new(
        candidate_instructions: [
          "Fallback instruction"
        ],
        analysis: {},
        metadata: {},
        predictor_instructions: {
          0 => ["inst-0a", "inst-0b"],
          1 => ["inst-1a"]
        }
      )
    end

    let(:demo_candidates) do
      {
        0 => [[few_shot_a]],
        1 => [[few_shot_b]]
      }
    end

    it 'builds joint instruction and demo combinations per predictor' do
      candidates = optimizer.send(:generate_candidate_configurations, proposal_result, demo_candidates)
      metadata = candidates.map(&:metadata)

      expect(metadata).to include(
        a_hash_including(
          instructions_map: { 0 => "inst-0a", 1 => "inst-1a" },
          demos_map: { 0 => [few_shot_a], 1 => [few_shot_b] }
        )
      )
    end

    it 'records predictor-level selections in trial logs' do
      candidate = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: "inst-0a",
        few_shot_examples: [few_shot_a, few_shot_b],
        type: DSPy::Teleprompt::CandidateType::Combined,
        metadata: {
          instructions_map: { 0 => "inst-0a", 1 => "inst-1a" },
          demos_map: { 0 => [few_shot_a], 1 => [few_shot_b] }
        },
        config_id: "log_test"
      )

      entry = optimizer.send(
        :create_trial_log_entry,
        trial_number: 1,
        candidate: candidate,
        evaluation_type: :full,
        batch_size: 2
      )

      expect(entry[:instructions]).to eq({ 0 => "inst-0a", 1 => "inst-1a" })
      expect(entry[:few_shot_map]).to eq({ 0 => [few_shot_a], 1 => [few_shot_b] })
    end

    it 'applies predictor-specific instructions and few-shot sets' do
      program = MIPROv2MultiPredictorSpec::Program.new([
        MIPROv2MultiPredictorSpec::Predictor.new("orig-0"),
        MIPROv2MultiPredictorSpec::Predictor.new("orig-1")
      ])

      candidate = DSPy::Teleprompt::MIPROv2::EvaluatedCandidate.new(
        instruction: "",
        few_shot_examples: [few_shot_a, few_shot_b],
        type: DSPy::Teleprompt::CandidateType::Combined,
        metadata: {
          instructions_map: { 0 => "inst-0a", 1 => "inst-1a" },
          demos_map: { 0 => [few_shot_a], 1 => [few_shot_b] }
        },
        config_id: "apply_test"
      )

      modified = optimizer.send(:apply_candidate_configuration, program, candidate)

      expect(modified).not_to equal(program)
      expect(modified.predictors[0].prompt.instruction).to eq("inst-0a")
      expect(modified.predictors[1].prompt.instruction).to eq("inst-1a")
      expect(modified.predictors[0].demos).to eq([few_shot_a])
      expect(modified.predictors[1].demos).to eq([few_shot_b])
      expect(modified.predictors[0].prompt.few_shot_examples).to eq([few_shot_a])
      expect(modified.predictors[1].prompt.few_shot_examples).to eq([few_shot_b])
      expect(program.predictors[0].prompt.instruction).to eq("orig-0")
      expect(program.predictors[1].prompt.instruction).to eq("orig-1")
      expect(modified.global_examples).to be_nil
    end
  end
end
