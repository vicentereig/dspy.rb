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

# Test enums for enum extraction testing
module TestEnums
  class EmailCategory < T::Enum
    enums do
      Technical = new("technical")
      Billing = new("billing")
      General = new("general")
    end
  end

  class Priority < T::Enum
    enums do
      Low = new("low")
      Medium = new("medium")
      High = new("high")
      Critical = new("critical")
    end
  end
end

# Signature with enum fields for testing enum extraction
class EmailClassification < DSPy::Signature
  description "Classify email support tickets by category and priority"

  input do
    const :email_content, String, description: "The email content to classify"
    const :subject, String, description: "The email subject line"
  end

  output do
    const :category, TestEnums::EmailCategory, description: "The email category"
    const :priority, TestEnums::Priority, description: "The priority level"
    const :summary, String, description: "Brief summary of the email"
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

  let(:email_examples) do
    [
      DSPy::Example.new(
        signature_class: EmailClassification,
        input: { 
          email_content: "Hi, I'm having trouble logging into my account and can't access my billing information.",
          subject: "Login issues - can't see billing"
        },
        expected: { 
          category: TestEnums::EmailCategory::Billing,
          priority: TestEnums::Priority::High,
          summary: "User cannot access account to view billing information"
        }
      ),
      DSPy::Example.new(
        signature_class: EmailClassification,
        input: { 
          email_content: "The new API endpoint is returning 500 errors when I send POST requests with large payloads.",
          subject: "API 500 errors with large requests"
        },
        expected: { 
          category: TestEnums::EmailCategory::Technical,
          priority: TestEnums::Priority::Critical,
          summary: "API endpoint failing with 500 errors for large POST requests"
        }
      ),
      DSPy::Example.new(
        signature_class: EmailClassification,
        input: { 
          email_content: "I just wanted to say thanks for the great service. Keep up the good work!",
          subject: "Thank you!"
        },
        expected: { 
          category: TestEnums::EmailCategory::General,
          priority: TestEnums::Priority::Low,
          summary: "Customer appreciation message"
        }
      )
    ]
  end

  describe DSPy::Propose::GroundedProposer::Config do
    it 'has sensible defaults' do
      config = DSPy::Propose::GroundedProposer::Config.new

      expect(config.num_instruction_candidates).to eq(5)
      expect(config.view_data_batch_size).to eq(10)
      # Python-compatible awareness flags
      expect(config.program_aware).to be(true)
      expect(config.use_dataset_summary).to be(true)
      expect(config.use_task_demos).to be(true)
      expect(config.use_tip).to be(true)
      expect(config.use_instruct_history).to be(true)
    end

    it 'allows configuration customization' do
      config = DSPy::Propose::GroundedProposer::Config.new
      config.num_instruction_candidates = 3
      config.view_data_batch_size = 5
      config.program_aware = false

      expect(config.num_instruction_candidates).to eq(3)
      expect(config.view_data_batch_size).to eq(5)
      expect(config.program_aware).to be(false)
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
      # Mock current_lm for metadata collection
      mock_lm = double('LM', model: 'gpt-4o-mini')
      allow(DSPy).to receive(:current_lm).and_return(mock_lm)

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

      custom_proposer = DSPy::Propose::GroundedProposer.new(config: config)
      result = custom_proposer.propose_instructions(GroundedClassify, simple_examples)

      expect(result.num_candidates).to be <= 2
      # max_instruction_length removed for Python compatibility - instructions not truncated
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

    it 'generates instructions with enum-specific context for enum-based signatures' do
      result = proposer.propose_instructions(EmailClassification, email_examples)

      expect(result).to be_a(DSPy::Propose::GroundedProposer::ProposalResult)
      expect(result.num_candidates).to be > 0
      
      # Analysis should contain enum field information
      expect(result.analysis).to include(:input_fields, :output_fields)
      
      category_field = result.analysis[:output_fields].find { |f| f[:name] == :category }
      priority_field = result.analysis[:output_fields].find { |f| f[:name] == :priority }
      
      expect(category_field).to be_truthy
      expect(category_field[:is_enum]).to be(true)
      expect(category_field[:enum_values]).to eq(["technical", "billing", "general"])
      
      expect(priority_field).to be_truthy
      expect(priority_field[:is_enum]).to be(true)
      expect(priority_field[:enum_values]).to eq(["low", "medium", "high", "critical"])
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

  describe '#propose_instructions_for_program' do
    before do
      allow(DSPy).to receive(:current_lm).and_return(double('LM', model: 'gpt-4o-mini'))
      allow_any_instance_of(DSPy::Predict).to receive(:call).and_return(
        OpenStruct.new(instruction: "Analyze the data carefully before responding.")
      )
    end

    it 'returns predictor-specific instruction mapping' do
      predictor = double('Predictor', prompt: OpenStruct.new(instruction: "Answer clearly"))
      program = double('Program', signature_class: ProposerQA, prompt: OpenStruct.new(instruction: "Answer clearly"), predictors: [predictor])
      demo_sets = { 0 => [[DSPy::FewShotExample.new(input: {}, output: {})]] }
      result = proposer.propose_instructions_for_program(
        trainset: training_examples,
        program: program,
        demo_candidates: demo_sets,
        trial_logs: nil,
        num_instruction_candidates: 2
      )

      expect(result).to be_a(DSPy::Propose::GroundedProposer::ProposalResult)
      expect(result.predictor_instructions).to include(0)
      expect(result.predictor_instructions[0].length).to be >= 1
    end
  end

  describe 'instruction history integration' do
    let(:trial_logs) do
      {
        1 => { instructions: { 0 => 'Use detailed reasoning' }, score: 0.72 },
        2 => { instructions: { 0 => 'Summarize context before answering' }, score: 0.81 },
        3 => { instructions: { 0 => 'Use detailed reasoning' }, score: 0.88 }
      }
    end

    it 'aggregates prior instruction scores into a history string' do
      proposer.instance_variable_set(:@program, nil)
      history_string = proposer.send(:build_instruction_history_summary, trial_logs, predictor_index: 0, top_n: 5)

      expect(history_string).to include('Use detailed reasoning')
      expect(history_string).to include('Summarize context before answering')
      expect(history_string).to include('Score: 0.8000')
    end

    it 'includes instruction history in generation context when enabled' do
      proposer.instance_variable_set(:@program, nil)
      proposer.config.use_instruct_history = true

      analysis = proposer.send(:analyze_task, ProposerQA, training_examples, nil)
      context = proposer.send(
        :build_generation_context,
        ProposerQA,
        analysis,
        nil,
        few_shot_examples: nil,
        trial_logs: trial_logs
      )

      expect(context).to include('Previous instructions')
      expect(context).to include('Use detailed reasoning')
    end

    it 'omits instruction history when disabled' do
      proposer.config.use_instruct_history = false

      analysis = proposer.send(:analyze_task, ProposerQA, training_examples, nil)
      context = proposer.send(
        :build_generation_context,
        ProposerQA,
        analysis,
        nil,
        few_shot_examples: nil,
        trial_logs: trial_logs
      )

      expect(context).not_to include('Previous instructions')
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

      it 'extracts enum field information with enum values' do
        fields = proposer.send(:extract_field_info, EmailClassification.output_struct_class)
        
        category_field = fields.find { |f| f[:name] == :category }
        priority_field = fields.find { |f| f[:name] == :priority }
        summary_field = fields.find { |f| f[:name] == :summary }

        expect(category_field).to be_truthy
        expect(category_field[:is_enum]).to be(true)
        expect(category_field[:enum_values]).to eq(["technical", "billing", "general"])

        expect(priority_field).to be_truthy
        expect(priority_field[:is_enum]).to be(true)
        expect(priority_field[:enum_values]).to eq(["low", "medium", "high", "critical"])

        expect(summary_field).to be_truthy
        expect(summary_field[:is_enum]).to be_nil
        expect(summary_field[:enum_values]).to be_nil
      end

      it 'preserves non-enum field information' do
        fields = proposer.send(:extract_field_info, EmailClassification.input_struct_class)
        
        fields.each do |field|
          expect(field).to include(:name, :type, :description, :required)
          expect(field[:is_enum]).to be_nil
          expect(field[:enum_values]).to be_nil
        end
      end
    end

    describe 'enum value extraction' do
      it 'extracts enum values from T::Enum types' do
        email_category_values = proposer.send(:extract_enum_values, TestEnums::EmailCategory)
        priority_values = proposer.send(:extract_enum_values, TestEnums::Priority)

        expect(email_category_values).to eq(["technical", "billing", "general"])
        expect(priority_values).to eq(["low", "medium", "high", "critical"])
      end

      it 'returns nil for non-enum types' do
        string_values = proposer.send(:extract_enum_values, String)
        integer_values = proposer.send(:extract_enum_values, Integer)

        expect(string_values).to be_nil
        expect(integer_values).to be_nil
      end

      it 'returns nil for nil input' do
        expect(proposer.send(:extract_enum_values, nil)).to be_nil
      end
    end

    describe 'field description formatting' do
      it 'formats enum fields with enum values' do
        enum_field = {
          name: :category,
          type: "TestEnums::EmailCategory",
          is_enum: true,
          enum_values: ["technical", "billing", "general"]
        }

        formatted = proposer.send(:format_field_description, enum_field)
        expect(formatted).to eq("category (TestEnums::EmailCategory) [values: technical, billing, general]")
      end

      it 'formats non-enum fields without enum values' do
        regular_field = {
          name: :summary,
          type: "String"
        }

        formatted = proposer.send(:format_field_description, regular_field)
        expect(formatted).to eq("summary (String)")
      end

      it 'handles enum fields without enum_values gracefully' do
        enum_field_no_values = {
          name: :status,
          type: "StatusEnum",
          is_enum: true,
          enum_values: nil
        }

        formatted = proposer.send(:format_field_description, enum_field_no_values)
        expect(formatted).to eq("status (StatusEnum)")
      end

      it 'handles enum fields with empty enum_values' do
        enum_field_empty = {
          name: :status,
          type: "StatusEnum",
          is_enum: true,
          enum_values: []
        }

        formatted = proposer.send(:format_field_description, enum_field_empty)
        expect(formatted).to eq("status (StatusEnum)")
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

    it 'builds context with enum field descriptions including enum values' do
      analysis = proposer.send(:analyze_task, EmailClassification, email_examples, nil)
      context = proposer.send(:build_generation_context, EmailClassification, analysis, nil)

      expect(context).to include("Task:")
      expect(context).to include("Input fields:")
      expect(context).to include("Output fields:")
      expect(context).to include(EmailClassification.description)
      
      # Verify enum fields include their values in the context
      expect(context).to include("category (TestEnums::EmailCategory) [values: technical, billing, general]")
      expect(context).to include("priority (TestEnums::Priority) [values: low, medium, high, critical]")
      
      # Verify non-enum fields don't have enum values
      expect(context).to include("email_content (String)")
      expect(context).to include("subject (String)")
      expect(context).to include("summary (String)")
      
      # Make sure the old placeholder format is not present
      expect(context).not_to include("[List possible TestEnums::EmailCategory options here]")
      expect(context).not_to include("[List possible TestEnums::Priority options here]")
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
