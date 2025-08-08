require 'spec_helper'
require 'ostruct'
require 'dspy/propose/grounded_proposer'
require 'dspy/signature'
require 'dspy/example'

# Test signature for grounded proposer testing
class ProposerQA < DSPy::Signature
  description "Answer questions with detailed explanations and reasoning."

  input do
    const :question, String, description: "The question to answer"
    const :context, String, description: "Relevant context information"
  end

  output do
    const :answer, String, description: "The answer to the question"
    const :reasoning, String, description: "Step-by-step reasoning process"
    const :confidence, Float, description: "Confidence in the answer (0.0 to 1.0)"
  end
end

# Simpler signature for testing
class GroundedClassify < DSPy::Signature
  description "Classify the sentiment of text"

  input do
    const :text, String
  end

  output do
    const :sentiment, String
  end
end

# Mock predictor that simulates instruction generation
class MockInstructionGenerator
  def call(task_context:, requirements:, candidate_number:)
    instructions = [
      "Analyze the given information carefully and provide a comprehensive answer with clear reasoning.",
      "Break down the problem step by step, considering all relevant context before concluding.",
      "Examine the question thoroughly, use the provided context, and explain your reasoning process.",
      "Think through this systematically, weighing evidence from the context to support your answer.",
      "Process the information methodically, connecting context clues to formulate a well-reasoned response."
    ]
    
    instruction = instructions[(candidate_number - 1) % instructions.size]
    OpenStruct.new(instruction: instruction)
  end
end

RSpec.describe DSPy::Propose::GroundedProposer do
  let(:proposer) { DSPy::Propose::GroundedProposer.new }
  
  let(:training_examples) do
    [
      DSPy::Example.new(
        signature_class: ProposerQA,
        input: { 
          question: "What is photosynthesis?",
          context: "Plants convert sunlight into energy through a biological process."
        },
        expected: { 
          answer: "Photosynthesis is the process by which plants convert sunlight into chemical energy.",
          reasoning: "The context mentions plants converting sunlight into energy, which describes photosynthesis.",
          confidence: 0.9
        }
      ),
      DSPy::Example.new(
        signature_class: ProposerQA,
        input: { 
          question: "How do birds fly?",
          context: "Birds have hollow bones and specialized wing structures that generate lift."
        },
        expected: { 
          answer: "Birds fly by using their wings to generate lift and thrust.",
          reasoning: "The hollow bones reduce weight while wing structures create the aerodynamics needed for flight.",
          confidence: 0.85
        }
      ),
      DSPy::Example.new(
        signature_class: ProposerQA,
        input: { 
          question: "Why is the sky blue?",
          context: "Light scattering in the atmosphere affects which wavelengths reach our eyes."
        },
        expected: { 
          answer: "The sky appears blue due to light scattering in Earth's atmosphere.",
          reasoning: "Shorter blue wavelengths scatter more than other colors when sunlight hits air molecules.",
          confidence: 0.92
        }
      )
    ]
  end

  let(:simple_examples) do
    [
      DSPy::Example.new(
        signature_class: GroundedClassify,
        input: { text: "I love this movie!" },
        expected: { sentiment: "positive" }
      ),
      DSPy::Example.new(
        signature_class: GroundedClassify,
        input: { text: "This is terrible." },
        expected: { sentiment: "negative" }
      )
    ]
  end

  describe DSPy::Propose::GroundedProposer::Config do
    it 'has sensible defaults' do
      config = DSPy::Propose::GroundedProposer::Config.new

      expect(config.num_instruction_candidates).to eq(5)
      expect(config.max_examples_for_analysis).to eq(10)
      expect(config.max_instruction_length).to eq(200)
      expect(config.use_task_description).to be(true)
      expect(config.use_input_output_analysis).to be(true)
      expect(config.use_few_shot_examples).to be(true)
      expect(config.proposal_model).to eq("gpt-4o-mini")
    end

    it 'allows configuration customization' do
      config = DSPy::Propose::GroundedProposer::Config.new
      config.num_instruction_candidates = 3
      config.max_instruction_length = 100
      config.use_task_description = false

      expect(config.num_instruction_candidates).to eq(3)
      expect(config.max_instruction_length).to eq(100)
      expect(config.use_task_description).to be(false)
    end
  end

  describe DSPy::Propose::GroundedProposer::ProposalResult do
    let(:candidates) { ["Instruction 1", "Instruction 2", "Instruction 3"] }
    let(:analysis) { { complexity: "high", themes: ["reasoning"] } }
    let(:metadata) { { model: "gpt-4", timestamp: "2024-01-01" } }

    let(:result) do
      DSPy::Propose::GroundedProposer::ProposalResult.new(
        candidate_instructions: candidates,
        analysis: analysis,
        metadata: metadata
      )
    end

    it 'stores proposal results correctly' do
      expect(result.candidate_instructions).to eq(candidates)
      expect(result.analysis).to eq(analysis)
      expect(result.metadata).to eq(metadata)
    end

    it 'provides best instruction' do
      expect(result.best_instruction).to eq("Instruction 1")
    end

    it 'counts candidates' do
      expect(result.num_candidates).to eq(3)
    end

    it 'handles empty candidates' do
      empty_result = DSPy::Propose::GroundedProposer::ProposalResult.new(
        candidate_instructions: [],
        analysis: {},
        metadata: {}
      )

      expect(empty_result.best_instruction).to eq("")
      expect(empty_result.num_candidates).to eq(0)
    end

    it 'freezes data structures' do
      expect(result.candidate_instructions).to be_frozen
      expect(result.analysis).to be_frozen
      expect(result.metadata).to be_frozen
    end
  end

  describe '#propose_instructions' do
    before do
      # Mock the LLM calls for instruction generation
      allow_any_instance_of(DSPy::Predict).to receive(:call).and_return(
        OpenStruct.new(instruction: "Analyze the information carefully and provide a detailed response.")
      )
    end

    it 'generates instruction proposals for complex signatures' do
      result = proposer.propose_instructions(ProposerQA, training_examples)

      expect(result).to be_a(DSPy::Propose::GroundedProposer::ProposalResult)
      expect(result.candidate_instructions.size).to be > 0
      expect(result.candidate_instructions.all? { |inst| inst.is_a?(String) && !inst.empty? }).to be(true)
    end

    it 'generates proposals for simple signatures' do
      result = proposer.propose_instructions(GroundedClassify, simple_examples)

      expect(result).to be_a(DSPy::Propose::GroundedProposer::ProposalResult)
      expect(result.num_candidates).to be > 0
    end

    it 'includes analysis information' do
      result = proposer.propose_instructions(ProposerQA, training_examples)

      expect(result.analysis).to include(:task_description, :input_fields, :output_fields)
      expect(result.analysis[:task_description]).to eq(ProposerQA.description)
      expect(result.analysis[:input_fields]).to be_an(Array)
      expect(result.analysis[:output_fields]).to be_an(Array)
    end

    it 'respects configuration limits' do
      config = DSPy::Propose::GroundedProposer::Config.new
      config.num_instruction_candidates = 2
      config.max_instruction_length = 50
      
      custom_proposer = DSPy::Propose::GroundedProposer.new(config: config)
      result = custom_proposer.propose_instructions(GroundedClassify, simple_examples)

      expect(result.num_candidates).to be <= 2
      result.candidate_instructions.each do |instruction|
        expect(instruction.length).to be <= 50
      end
    end

    it 'handles few-shot examples when provided' do
      few_shot = training_examples.take(2)
      result = proposer.propose_instructions(ProposerQA, training_examples, few_shot_examples: few_shot)

      expect(result.analysis).to include(:few_shot_patterns)
      expect(result.analysis[:few_shot_patterns]).to include(:num_examples, :demonstrates_reasoning)
    end

    it 'considers current instruction when provided' do
      current = "Answer questions clearly and concisely."
      result = proposer.propose_instructions(ProposerQA, training_examples, current_instruction: current)

      expect(result.metadata[:original_instruction]).to eq(current)
    end

    it 'handles LLM generation failures gracefully' do
      # Mock LLM to raise an error
      allow_any_instance_of(DSPy::Predict).to receive(:call).and_raise("API Error")

      result = proposer.propose_instructions(GroundedClassify, simple_examples)

      # Should still return at least a fallback instruction
      expect(result.num_candidates).to be >= 1
      expect(result.best_instruction).not_to be_empty
    end
  end

  describe 'analysis methods' do
    describe 'task complexity assessment' do
      it 'correctly identifies complex signatures' do
        analysis = proposer.send(:analyze_task, ProposerQA, training_examples, nil)
        complexity = analysis[:complexity_indicators]

        expect(complexity[:num_input_fields]).to eq(2)
        expect(complexity[:num_output_fields]).to eq(3)
        expect(complexity[:requires_reasoning]).to be(true)
      end

      it 'correctly identifies simple signatures' do
        analysis = proposer.send(:analyze_task, GroundedClassify, simple_examples, nil)
        complexity = analysis[:complexity_indicators]

        expect(complexity[:num_input_fields]).to eq(1)
        expect(complexity[:num_output_fields]).to eq(1)
        expect(complexity[:requires_reasoning]).to be(false)
      end
    end

    describe 'pattern analysis' do
      it 'analyzes input patterns correctly' do
        patterns = proposer.send(:analyze_example_patterns, training_examples)
        input_patterns = patterns[:input_patterns]

        expect(input_patterns).to include(:avg_input_length, :common_input_types, :frequent_keywords)
        expect(input_patterns[:avg_input_length]).to be > 0
        expect(input_patterns[:common_input_types]).to include("String")
      end

      it 'extracts common themes' do
        patterns = proposer.send(:analyze_example_patterns, training_examples)

        expect(patterns[:common_themes]).to include("question_answering")
      end

      it 'identifies mathematical reasoning' do
        math_examples = [
          DSPy::Example.new(
            signature_class: GroundedClassify,
            input: { text: "What is 2 + 2 × 3?" },
            expected: { sentiment: "neutral" }
          )
        ]

        patterns = proposer.send(:analyze_example_patterns, math_examples)
        expect(patterns[:common_themes]).to include("mathematical_reasoning")
      end
    end

    describe 'field extraction' do
      it 'extracts input field information' do
        fields = proposer.send(:extract_field_info, ProposerQA.input_struct_class)

        expect(fields.size).to eq(2)
        expect(fields.map { |f| f[:name] }).to include(:question, :context)
        expect(fields.all? { |f| f[:required] }).to be(true)
      end

      it 'extracts output field information' do
        fields = proposer.send(:extract_field_info, ProposerQA.output_struct_class)

        expect(fields.size).to eq(3)
        expect(fields.map { |f| f[:name] }).to include(:answer, :reasoning, :confidence)
      end
    end
  end

  describe 'instruction generation' do
    it 'builds appropriate context for generation' do
      analysis = proposer.send(:analyze_task, ProposerQA, training_examples, nil)
      context = proposer.send(:build_generation_context, ProposerQA, analysis, nil)

      expect(context).to include("Task:")
      expect(context).to include("Input fields:")
      expect(context).to include("Output fields:")
      expect(context).to include(ProposerQA.description)
    end

    it 'builds requirements based on task complexity' do
      analysis = proposer.send(:analyze_task, ProposerQA, training_examples, nil)
      requirements = proposer.send(:build_requirements_text, analysis)

      expect(requirements).to include("step-by-step") # Due to reasoning requirement
      expect(requirements).to include("specific")
      expect(requirements).to include("actionable")
    end

    it 'generates fallback instructions' do
      analysis = { complexity_indicators: { requires_reasoning: true } }
      fallback = proposer.send(:generate_fallback_instruction, ProposerQA, analysis)

      expect(fallback).to include(ProposerQA.description)
      expect(fallback.downcase).to include("step")
    end
  end

  describe 'filtering and ranking' do
    let(:test_candidates) do
      [
        "Simple answer",
        "Analyze the information carefully and provide a detailed, step-by-step explanation of your reasoning process.",
        "Classify sentiment",
        "Think through this problem systematically, considering all relevant factors before reaching a conclusion.",
        ""
      ]
    end

    it 'filters and ranks candidates appropriately' do
      analysis = { complexity_indicators: { requires_reasoning: true } }
      filtered = proposer.send(:filter_and_rank_candidates, test_candidates, analysis)

      expect(filtered).not_to include("") # Removes empty
      expect(filtered.size).to be < test_candidates.size # Removes empty candidate
      expect(filtered.first).to include("step") # Prefers reasoning-related instructions
    end

    it 'handles duplicate candidates' do
      duplicates = ["Same instruction", "Same instruction", "Different instruction"]
      analysis = { complexity_indicators: { requires_reasoning: false } }
      
      filtered = proposer.send(:filter_and_rank_candidates, duplicates, analysis)
      
      expect(filtered.size).to eq(2) # Removes duplicate
      expect(filtered.uniq.size).to eq(filtered.size) # No duplicates in result
    end
  end

  describe 'helper methods' do
    it 'extracts input values from different example formats' do
      dspy_example = training_examples.first
      hash_example = { input: { test: "value" }, expected: { result: "output" } }
      object_example = OpenStruct.new(input: { data: "test" })

      expect(proposer.send(:extract_input_values, dspy_example)).to include(:question, :context)
      expect(proposer.send(:extract_input_values, hash_example)).to eq({ test: "value" })
      expect(proposer.send(:extract_input_values, object_example)).to eq({ data: "test" })
    end

    it 'extracts expected values from different example formats' do
      dspy_example = training_examples.first
      hash_example = { input: { test: "value" }, expected: { result: "output" } }

      expect(proposer.send(:extract_expected_values, dspy_example)).to include(:answer, :reasoning, :confidence)
      expect(proposer.send(:extract_expected_values, hash_example)).to eq({ result: "output" })
    end

    it 'detects reasoning fields' do
      reasoning_example = training_examples.first # Has reasoning field
      simple_example = simple_examples.first # No reasoning field

      expect(proposer.send(:has_reasoning_field?, reasoning_example)).to be(true)
      expect(proposer.send(:has_reasoning_field?, simple_example)).to be(false)
    end

    it 'assesses example variety' do
      high_variety = training_examples # Different questions
      low_variety = [simple_examples.first] # Only one example

      expect(proposer.send(:assess_example_variety, high_variety)).to eq("high")
      expect(proposer.send(:assess_example_variety, low_variety)).to eq("low")
    end
  end

end