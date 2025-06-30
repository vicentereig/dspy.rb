require 'spec_helper'
require 'ostruct'
require 'dspy/teleprompt/simple_optimizer'
require 'dspy/signature'
require 'dspy/predict'
require 'dspy/example'

# Test signature for optimizer testing
class OptimizerMath < DSPy::Signature
  description "Solve math problems with explanations"

  input do
    const :problem, String, description: "Math problem to solve"
  end

  output do
    const :answer, Integer, description: "Numerical answer"
    const :explanation, String, description: "Step-by-step explanation"
  end
end

# Mock program that can be optimized
class MockOptimizableProgram
  attr_reader :signature_class, :instruction, :few_shot_examples

  def initialize(signature_class, instruction: nil, few_shot_examples: [])
    @signature_class = signature_class
    @instruction = instruction || signature_class.description
    @few_shot_examples = few_shot_examples
  end

  def call(problem:)
    # Simple mock behavior based on current configuration
    base_score = 0.5
    
    # Better performance with good instruction
    if @instruction&.include?("step") || @instruction&.include?("explain")
      base_score += 0.2
    end
    
    # Better performance with few-shot examples
    if @few_shot_examples.any?
      base_score += 0.1 * [@few_shot_examples.size, 3].min
    end
    
    # Simulate some variability
    final_score = [base_score + rand(0.2) - 0.1, 1.0].min
    
    if final_score > 0.7
      answer = case problem
               when /(\d+)\s*\+\s*(\d+)/ then $1.to_i + $2.to_i
               when /(\d+)\s*-\s*(\d+)/ then $1.to_i - $2.to_i
               when /(\d+)\s*\*\s*(\d+)/ then $1.to_i * $2.to_i
               else 42
               end
      OpenStruct.new(
        problem: problem,
        answer: answer,
        explanation: "#{@instruction&.include?('step') ? 'Step by step: ' : ''}Calculated result"
      )
    else
      # Simulate wrong answer for low scores
      OpenStruct.new(
        problem: problem,
        answer: 0,
        explanation: "Unable to solve"
      )
    end
  end

  def with_instruction(new_instruction)
    self.class.new(@signature_class, instruction: new_instruction, few_shot_examples: @few_shot_examples)
  end

  def with_examples(new_examples)
    self.class.new(@signature_class, instruction: @instruction, few_shot_examples: new_examples)
  end

  def prompt
    OpenStruct.new(instruction: @instruction)
  end

  def system_signature
    @instruction
  end

  def to_h
    { answer: @answer, explanation: @explanation }
  end
end

RSpec.describe DSPy::Teleprompt::SimpleOptimizer do
  let(:test_program) { MockOptimizableProgram.new(OptimizerMath) }
  let(:optimizer) { DSPy::Teleprompt::SimpleOptimizer.new }

  let(:training_examples) do
    [
      DSPy::Example.new(
        signature_class: OptimizerMath,
        input: { problem: "5 + 3" },
        expected: { answer: 8, explanation: "Add 5 and 3 to get 8" },
        id: "add_1"
      ),
      DSPy::Example.new(
        signature_class: OptimizerMath,
        input: { problem: "10 - 4" },
        expected: { answer: 6, explanation: "Subtract 4 from 10 to get 6" },
        id: "sub_1"
      ),
      DSPy::Example.new(
        signature_class: OptimizerMath,
        input: { problem: "3 * 7" },
        expected: { answer: 21, explanation: "Multiply 3 by 7 to get 21" },
        id: "mult_1"
      ),
      DSPy::Example.new(
        signature_class: OptimizerMath,
        input: { problem: "2 + 6" },
        expected: { answer: 8, explanation: "Add 2 and 6 to get 8" },
        id: "add_2"
      ),
      DSPy::Example.new(
        signature_class: OptimizerMath,
        input: { problem: "9 - 5" },
        expected: { answer: 4, explanation: "Subtract 5 from 9 to get 4" },
        id: "sub_2"
      )
    ]
  end

  let(:validation_examples) do
    training_examples.take(2) # Use subset for validation
  end

  describe DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig do
    it 'has sensible defaults' do
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new

      expect(config.num_trials).to eq(10)
      expect(config.search_strategy).to eq("random")
      expect(config.use_instruction_optimization).to be(true)
      expect(config.use_few_shot_optimization).to be(true)
      expect(config.proposer_config).to be_a(DSPy::Propose::GroundedProposer::Config)
    end

    it 'allows configuration customization' do
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
      config.num_trials = 5
      config.search_strategy = "grid"
      config.use_instruction_optimization = false

      expect(config.num_trials).to eq(5)
      expect(config.search_strategy).to eq("grid")
      expect(config.use_instruction_optimization).to be(false)
    end
  end

  describe DSPy::Teleprompt::SimpleOptimizer::TrialResult do
    let(:mock_evaluation) do
      DSPy::Evaluate::BatchEvaluationResult.new(
        results: Array.new(10) { 
          DSPy::Evaluate::EvaluationResult.new(
            example: {},
            prediction: {},
            trace: nil,
            metrics: {},
            passed: true
          )
        },
        aggregated_metrics: {}
      )
    end

    let(:trial_result) do
      DSPy::Teleprompt::SimpleOptimizer::TrialResult.new(
        trial_number: 1,
        program: test_program,
        instruction: "Test instruction",
        few_shot_examples: [],
        evaluation_result: mock_evaluation,
        score: 0.8,
        metadata: { duration_ms: 100 }
      )
    end

    it 'stores trial results correctly' do
      expect(trial_result.trial_number).to eq(1)
      expect(trial_result.program).to eq(test_program)
      expect(trial_result.instruction).to eq("Test instruction")
      expect(trial_result.evaluation_result).to eq(mock_evaluation)
      expect(trial_result.score).to eq(0.8)
    end

    it 'determines success correctly' do
      expect(trial_result.successful?).to be(true)
      
      failed_result = DSPy::Teleprompt::SimpleOptimizer::TrialResult.new(
        trial_number: 2,
        program: test_program,
        instruction: "",
        few_shot_examples: [],
        evaluation_result: mock_evaluation,
        score: 0.0,
        metadata: {}
      )
      
      expect(failed_result.successful?).to be(false)
    end

    it 'freezes metadata' do
      expect(trial_result.metadata).to be_frozen
    end
  end

  describe '#initialize' do
    it 'creates optimizer with default configuration' do
      optimizer = DSPy::Teleprompt::SimpleOptimizer.new

      expect(optimizer.optimizer_config).to be_a(DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig)
      expect(optimizer.proposer).to be_a(DSPy::Propose::GroundedProposer)
    end

    it 'creates optimizer with custom configuration' do
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
      config.use_instruction_optimization = false
      
      optimizer = DSPy::Teleprompt::SimpleOptimizer.new(config: config)

      expect(optimizer.optimizer_config).to eq(config)
      expect(optimizer.proposer).to be_nil # No proposer when instruction optimization disabled
    end

    it 'accepts custom metric' do
      custom_metric = proc { |example, prediction| true }
      optimizer = DSPy::Teleprompt::SimpleOptimizer.new(metric: custom_metric)

      expect(optimizer.metric).to eq(custom_metric)
    end
  end

  describe '#compile' do
    before do
      # Mock the grounded proposer to return predictable instructions
      allow_any_instance_of(DSPy::Propose::GroundedProposer).to receive(:propose_instructions).and_return(
        DSPy::Propose::GroundedProposer::ProposalResult.new(
          candidate_instructions: [
            "Solve step by step with clear explanations",
            "Calculate carefully and show your work",
            "Think through the problem methodically"
          ],
          analysis: { complexity: "medium" },
          metadata: { model: "test" }
        )
      )

      # Mock bootstrap to return some examples
      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return(
        DSPy::Teleprompt::Utils::BootstrapResult.new(
          candidate_sets: [
            training_examples.take(2),
            training_examples.drop(1).take(2)
          ],
          successful_examples: training_examples.take(3),
          failed_examples: [],
          statistics: { success_rate: 1.0 }
        )
      )
    end

    it 'performs optimization and returns result' do
      result = optimizer.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).not_to be_nil
      expect(result.scores).to include(:pass_rate)
      expect(result.best_score_value).to be_a(Float)
      expect(result.best_score_value).to be >= 0.0
    end

    it 'validates inputs before optimization' do
      expect {
        optimizer.compile(nil, trainset: training_examples)
      }.to raise_error(ArgumentError, /Program cannot be nil/)

      expect {
        optimizer.compile(test_program, trainset: [])
      }.to raise_error(ArgumentError, /Training set cannot be empty/)
    end

    it 'handles missing validation set' do
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
      config.require_validation_examples = false
      optimizer = DSPy::Teleprompt::SimpleOptimizer.new(config: config)

      result = optimizer.compile(test_program, trainset: training_examples)

      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
    end

    it 'respects trial limit configuration' do
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
      config.num_trials = 3
      optimizer = DSPy::Teleprompt::SimpleOptimizer.new(config: config)

      result = optimizer.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result.history[:total_trials]).to be <= 3
    end

    it 'works with instruction optimization disabled' do
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
      config.use_instruction_optimization = false
      optimizer = DSPy::Teleprompt::SimpleOptimizer.new(config: config)

      result = optimizer.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
    end

    it 'works with few-shot optimization disabled' do
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
      config.use_few_shot_optimization = false
      optimizer = DSPy::Teleprompt::SimpleOptimizer.new(config: config)

      result = optimizer.compile(test_program, trainset: training_examples, valset: validation_examples)

      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
    end
  end

  describe 'trial configuration generation' do
    let(:instruction_candidates) { ["Instruction 1", "Instruction 2"] }
    let(:bootstrap_result) do
      DSPy::Teleprompt::Utils::BootstrapResult.new(
        candidate_sets: [training_examples.take(2), training_examples.drop(1).take(2)],
        successful_examples: training_examples.take(3),
        failed_examples: [],
        statistics: {}
      )
    end

    it 'generates diverse trial configurations' do
      configs = optimizer.send(:generate_trial_configurations, instruction_candidates, bootstrap_result)

      expect(configs.size).to be > 1
      
      # Should include base configuration
      base_config = configs.find { |c| c[:instruction].nil? && c[:few_shot_examples].empty? }
      expect(base_config).not_to be_nil

      # Should include instruction-only configurations
      instruction_configs = configs.select { |c| c[:instruction] && c[:few_shot_examples].empty? }
      expect(instruction_configs.size).to be > 0

      # Should include few-shot only configurations
      few_shot_configs = configs.select { |c| c[:instruction].nil? && c[:few_shot_examples].any? }
      expect(few_shot_configs.size).to be > 0

      # Should include combined configurations
      combined_configs = configs.select { |c| c[:instruction] && c[:few_shot_examples].any? }
      expect(combined_configs.size).to be > 0
    end

    it 'respects search strategy' do
      # Test random strategy
      config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
      config.search_strategy = "random"
      random_optimizer = DSPy::Teleprompt::SimpleOptimizer.new(config: config)

      configs1 = random_optimizer.send(:generate_trial_configurations, instruction_candidates, bootstrap_result)
      configs2 = random_optimizer.send(:generate_trial_configurations, instruction_candidates, bootstrap_result)

      # Random strategy should potentially produce different orders
      # (This is probabilistic, but with enough configs it should be different)
      expect(configs1).to be_an(Array)
      expect(configs2).to be_an(Array)
    end
  end

  describe 'program modification' do
    it 'applies instruction modifications' do
      modified = optimizer.send(:apply_instruction_modification, test_program, "New instruction")

      expect(modified.instruction).to eq("New instruction")
      expect(modified).not_to eq(test_program) # Should be new instance
    end

    it 'applies few-shot modifications' do
      examples = training_examples.take(2)
      modified = optimizer.send(:apply_few_shot_modification, test_program, examples)

      expect(modified.few_shot_examples.size).to eq(2)
      expect(modified).not_to eq(test_program) # Should be new instance
    end

    it 'applies combined modifications' do
      config = { instruction: "New instruction", few_shot_examples: training_examples.take(1) }
      modified = optimizer.send(:apply_trial_configuration, test_program, config)

      expect(modified.instruction).to eq("New instruction")
      expect(modified.few_shot_examples.size).to eq(1)
    end

    it 'handles programs that don\'t support modifications' do
      simple_program = Object.new
      config = { instruction: "Test", few_shot_examples: [] }
      
      modified = optimizer.send(:apply_trial_configuration, simple_program, config)
      
      expect(modified).to eq(simple_program) # Should return unchanged
    end
  end

  describe 'helper methods' do
    it 'extracts current instruction from program' do
      instruction = optimizer.send(:extract_current_instruction, test_program)
      expect(instruction).to eq(test_program.instruction)
    end

    it 'extracts signature class from program' do
      signature_class = optimizer.send(:extract_signature_class, test_program)
      expect(signature_class).to eq(OptimizerMath)
    end

    it 'checks program capabilities' do
      expect(optimizer.send(:respond_to_instruction_modification?, test_program)).to be(true)
      expect(optimizer.send(:respond_to_few_shot_modification?, test_program)).to be(true)

      simple_program = Object.new
      expect(optimizer.send(:respond_to_instruction_modification?, simple_program)).to be(false)
      expect(optimizer.send(:respond_to_few_shot_modification?, simple_program)).to be(false)
    end

    it 'extracts reasoning from examples' do
      # Create a signature that includes reasoning field for this test
      reasoning_signature = Class.new(DSPy::Signature) do
        description "Test with reasoning"
        
        input do
          const :problem, String
        end
        
        output do
          const :answer, Integer
          const :explanation, String
          const :reasoning, String
        end
      end
      
      reasoning_example = DSPy::Example.new(
        signature_class: reasoning_signature,
        input: { problem: "test" },
        expected: { answer: 1, explanation: "test", reasoning: "step by step" }
      )

      reasoning = optimizer.send(:extract_reasoning_from_example, reasoning_example)
      expect(reasoning).to eq("step by step")

      # OptimizerMath has 'explanation' field, which is used as fallback for reasoning
      explanation_example = training_examples.first
      reasoning = optimizer.send(:extract_reasoning_from_example, explanation_example)
      expect(reasoning).to eq("Add 5 and 3 to get 8") # Uses explanation as reasoning fallback
    end
  end

  describe 'optimization result building' do
    let(:mock_evaluation_1) do
      DSPy::Evaluate::BatchEvaluationResult.new(
        results: Array.new(10) { |i|
          DSPy::Evaluate::EvaluationResult.new(
            example: {},
            prediction: {},
            trace: nil,
            metrics: {},
            passed: i < 6  # 6 out of 10 pass = 0.6
          )
        },
        aggregated_metrics: {}
      )
    end

    let(:mock_evaluation_2) do
      DSPy::Evaluate::BatchEvaluationResult.new(
        results: Array.new(10) { |i|
          DSPy::Evaluate::EvaluationResult.new(
            example: {},
            prediction: {},
            trace: nil,
            metrics: {},
            passed: i < 8  # 8 out of 10 pass = 0.8
          )
        },
        aggregated_metrics: {}
      )
    end

    let(:mock_trials) do
      [
        DSPy::Teleprompt::SimpleOptimizer::TrialResult.new(
          trial_number: 1,
          program: test_program,
          instruction: "Instruction 1",
          few_shot_examples: [],
          evaluation_result: mock_evaluation_1,
          score: 0.6,
          metadata: {}
        ),
        DSPy::Teleprompt::SimpleOptimizer::TrialResult.new(
          trial_number: 2,
          program: test_program,
          instruction: "Instruction 2",
          few_shot_examples: training_examples.take(1),
          evaluation_result: mock_evaluation_2,
          score: 0.8,
          metadata: {}
        )
      ]
    end

    it 'finds best trial correctly' do
      best = optimizer.send(:find_best_trial, mock_trials)

      expect(best.trial_number).to eq(2)
      expect(best.score).to eq(0.8)
    end

    it 'builds optimization result from best trial' do
      best = optimizer.send(:find_best_trial, mock_trials)
      result = optimizer.send(:build_optimization_result, best, mock_trials)

      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.best_score_value).to eq(0.8)
      expect(result.history[:total_trials]).to eq(2)
      expect(result.history[:best_trial_number]).to eq(2)
      expect(result.metadata[:optimizer]).to eq("SimpleOptimizer")
      expect(result.metadata[:best_instruction]).to eq("Instruction 2")
    end

    it 'handles case with no successful trials' do
      result = optimizer.send(:build_optimization_result, nil, [])

      expect(result.optimized_program).to be_nil
      expect(result.best_score_value).to eq(0.0)
      expect(result.metadata[:error]).to eq("No successful trials")
    end
  end

  describe 'instrumentation integration' do
    before do
      allow_any_instance_of(DSPy::Propose::GroundedProposer).to receive(:propose_instructions).and_return(
        DSPy::Propose::GroundedProposer::ProposalResult.new(
          candidate_instructions: ["Test instruction"],
          analysis: {},
          metadata: {}
        )
      )
      allow(DSPy::Teleprompt::Utils).to receive(:create_n_fewshot_demo_sets).and_return(
        DSPy::Teleprompt::Utils::BootstrapResult.new(
          candidate_sets: [],
          successful_examples: [],
          failed_examples: [],
          statistics: {}
        )
      )
    end

    it 'instruments optimization process' do
      expect(DSPy::Instrumentation).to receive(:instrument).with(
        'dspy.optimization.compile',
        hash_including(trainset_size: 5, num_trials: 10)
      ).and_call_original

      # Allow other instrumentation calls from evaluation
      allow(DSPy::Instrumentation).to receive(:instrument).and_call_original

      optimizer.compile(test_program, trainset: training_examples, valset: validation_examples)
    end

    it 'emits trial events' do
      expect(optimizer).to receive(:emit_event).with('trial_start', anything).at_least(:once)
      expect(optimizer).to receive(:emit_event).with('trial_complete', anything).at_least(:once)

      optimizer.compile(test_program, trainset: training_examples, valset: validation_examples)
    end
  end
end