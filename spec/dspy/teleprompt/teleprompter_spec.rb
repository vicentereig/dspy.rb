require 'spec_helper'
require 'ostruct'
require 'dspy/teleprompt/teleprompter'
require 'dspy/signature'
require 'dspy/predict'

# Test signature for teleprompter testing
class TeleprompterMath < DSPy::Signature
  description "Solve math problems with explanations."

  input do
    const :problem, String, description: "A math problem to solve"
  end

  output do
    const :answer, String, description: "The numerical answer"
    const :explanation, String, description: "How the problem was solved"
  end
end

# Mock teleprompter for testing the base class
class MockTeleprompter < DSPy::Teleprompt::Teleprompter
  attr_accessor :compile_called_with

  def compile(program, trainset:, valset: nil)
    @compile_called_with = { program: program, trainset: trainset, valset: valset }
    
    # Return a mock optimization result
    OptimizationResult.new(
      optimized_program: program, # Return the same program for testing
      scores: { accuracy: 0.85, pass_rate: 0.8 },
      history: { trials: 5, best_trial: 3 },
      best_score_name: "accuracy",
      best_score_value: 0.85,
      metadata: { optimizer: "MockTeleprompter", test: true }
    )
  end
end

# Mock program for testing
class MockMathProgram
  def call(problem:)
    # Simple mock responses
    case problem
    when "2 + 2"
      OpenStruct.new(problem: problem, answer: "4", explanation: "Add 2 and 2")
    when "3 × 4"
      OpenStruct.new(problem: problem, answer: "12", explanation: "Multiply 3 by 4")
    else
      OpenStruct.new(problem: problem, answer: "unknown", explanation: "Cannot solve")
    end
  end
end

RSpec.describe DSPy::Teleprompt::Teleprompter do
  let(:mock_program) { MockMathProgram.new }
  let(:teleprompter) { MockTeleprompter.new }

  describe DSPy::Teleprompt::Teleprompter::Config do
    it 'has sensible defaults' do
      config = DSPy::Teleprompt::Teleprompter::Config.new
      
      expect(config.max_bootstrapped_examples).to eq(4)
      expect(config.max_labeled_examples).to eq(16)
      expect(config.num_candidate_examples).to eq(50)
      expect(config.num_threads).to eq(1)
      expect(config.max_errors).to eq(5)
      expect(config.require_validation_examples).to be(true)
      expect(config.save_intermediate_results).to be(false)
      expect(config.save_path).to be_nil
    end

    it 'serializes to hash' do
      config = DSPy::Teleprompt::Teleprompter::Config.new
      config.max_bootstrapped_examples = 8
      config.save_path = "/tmp/test"
      
      hash = config.to_h
      
      expect(hash[:max_bootstrapped_examples]).to eq(8)
      expect(hash[:save_path]).to eq("/tmp/test")
      expect(hash[:require_validation_examples]).to be(true)
    end
  end

  describe DSPy::Teleprompt::Teleprompter::OptimizationResult do
    let(:result) do
      DSPy::Teleprompt::Teleprompter::OptimizationResult.new(
        optimized_program: mock_program,
        scores: { accuracy: 0.9, f1: 0.85 },
        history: { iterations: 10, convergence: true },
        best_score_name: "accuracy",
        best_score_value: 0.9,
        metadata: { optimizer: "test", duration: 120 }
      )
    end

    it 'stores optimization results' do
      expect(result.optimized_program).to eq(mock_program)
      expect(result.scores[:accuracy]).to eq(0.9)
      expect(result.best_score_name).to eq("accuracy")
      expect(result.best_score_value).to eq(0.9)
    end

    it 'serializes to hash' do
      hash = result.to_h
      
      expect(hash[:scores]).to eq({ accuracy: 0.9, f1: 0.85 })
      expect(hash[:best_score_name]).to eq("accuracy")
      expect(hash[:metadata][:optimizer]).to eq("test")
    end

    it 'freezes internal data structures' do
      expect(result.scores).to be_frozen
      expect(result.history).to be_frozen
      expect(result.metadata).to be_frozen
    end
  end

  describe 'initialization' do
    it 'creates teleprompter with default config' do
      tp = DSPy::Teleprompt::Teleprompter.new
      
      expect(tp.config).to be_a(DSPy::Teleprompt::Teleprompter::Config)
      expect(tp.metric).to be_nil
      expect(tp.evaluator).to be_nil
    end

    it 'accepts custom metric and config' do
      metric = proc { |example, prediction| true }
      config = DSPy::Teleprompt::Teleprompter::Config.new
      config.max_errors = 10
      
      tp = DSPy::Teleprompt::Teleprompter.new(metric: metric, config: config)
      
      expect(tp.metric).to eq(metric)
      expect(tp.config.max_errors).to eq(10)
    end
  end

  describe '#compile' do
    it 'raises NotImplementedError for base class' do
      base_tp = DSPy::Teleprompt::Teleprompter.new
      
      expect {
        base_tp.compile(mock_program, trainset: [])
      }.to raise_error(NotImplementedError, /implement the compile method/)
    end

    it 'works for subclasses' do
      trainset = [
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "2 + 2" },
          expected: { answer: "4", explanation: "Add 2 and 2" }
        )
      ]
      
      result = teleprompter.compile(mock_program, trainset: trainset)
      
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).to eq(mock_program)
      expect(teleprompter.compile_called_with[:trainset]).to eq(trainset)
    end
  end

  describe '#validate_inputs' do
    let(:trainset) do
      [
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "1 + 1" },
          expected: { answer: "2", explanation: "Add 1 and 1" }
        )
      ]
    end

    let(:valset) do
      [
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "3 + 3" },
          expected: { answer: "6", explanation: "Add 3 and 3" }
        )
      ]
    end

    it 'validates successfully with proper inputs' do
      expect {
        teleprompter.validate_inputs(mock_program, trainset, valset)
      }.not_to raise_error
    end

    it 'raises error for nil program' do
      expect {
        teleprompter.validate_inputs(nil, trainset, valset)
      }.to raise_error(ArgumentError, /Program cannot be nil/)
    end

    it 'raises error for empty training set' do
      expect {
        teleprompter.validate_inputs(mock_program, [], valset)
      }.to raise_error(ArgumentError, /Training set cannot be empty/)
    end

    it 'raises error when validation set required but not provided' do
      teleprompter.config.require_validation_examples = true
      
      expect {
        teleprompter.validate_inputs(mock_program, trainset, nil)
      }.to raise_error(ArgumentError, /Validation set is required/)
    end

    it 'allows missing validation set when not required' do
      teleprompter.config.require_validation_examples = false
      
      expect {
        teleprompter.validate_inputs(mock_program, trainset, nil)
      }.not_to raise_error
    end
  end

  describe '#ensure_typed_examples' do
    it 'returns DSPy::Example objects unchanged' do
      examples = [
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "5 + 5" },
          expected: { answer: "10", explanation: "Add 5 and 5" }
        )
      ]
      
      result = teleprompter.ensure_typed_examples(examples)
      
      expect(result).to eq(examples)
      expect(result.first).to be_a(DSPy::Example)
    end

    it 'converts legacy format to DSPy::Example objects' do
      legacy_examples = [
        {
          input: { problem: "6 × 2" },
          expected: { answer: "12", explanation: "Multiply 6 by 2" }
        }
      ]
      
      result = teleprompter.ensure_typed_examples(legacy_examples, TeleprompterMath)
      
      expect(result.first).to be_a(DSPy::Example)
      expect(result.first.signature_class).to eq(TeleprompterMath)
      expect(result.first.input_values[:problem]).to eq("6 × 2")
    end

    it 'raises error when signature class cannot be determined' do
      legacy_examples = [{ problem: "test", answer: "result" }]
      
      expect {
        teleprompter.ensure_typed_examples(legacy_examples)
      }.to raise_error(ArgumentError, /Cannot determine signature class/)
    end
  end

  describe '#create_evaluator' do
    it 'creates evaluator with provided metric' do
      custom_metric = proc { |example, prediction| true }
      teleprompter = MockTeleprompter.new(metric: custom_metric)
      
      examples = [
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "test" },
          expected: { answer: "test", explanation: "test" }
        )
      ]
      
      evaluator = teleprompter.create_evaluator(examples)
      
      expect(evaluator).to be_a(DSPy::Evaluate)
      expect(teleprompter.evaluator).to eq(evaluator)
    end

    it 'creates default metric for DSPy::Example objects' do
      examples = [
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "default" },
          expected: { answer: "default", explanation: "default" }
        )
      ]
      
      evaluator = teleprompter.create_evaluator(examples)
      
      expect(evaluator).to be_a(DSPy::Evaluate)
      expect(evaluator.metric).not_to be_nil
    end
  end

  describe '#evaluate_program' do
    let(:examples) do
      [
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "2 + 2" },
          expected: { answer: "4", explanation: "Add 2 and 2" }
        ),
        DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "3 × 4" },
          expected: { answer: "12", explanation: "Multiply 3 by 4" }
        )
      ]
    end

    it 'evaluates program on examples' do
      result = teleprompter.evaluate_program(mock_program, examples)
      
      expect(result).to be_a(DSPy::Evaluate::BatchEvaluationResult)
      expect(result.total_examples).to eq(2)
    end

    it 'uses custom metric when provided' do
      custom_metric = proc { |example, prediction| 
        # Always return true for testing
        true
      }
      
      result = teleprompter.evaluate_program(mock_program, examples, metric: custom_metric)
      
      expect(result.passed_examples).to eq(2) # Should pass due to custom metric
    end
  end

  describe '#save_results' do
    let(:result) do
      DSPy::Teleprompt::Teleprompter::OptimizationResult.new(
        optimized_program: mock_program,
        scores: { test: 0.5 },
        history: { saved: true },
        metadata: { test: "save" }
      )
    end

    it 'does not save when not configured' do
      teleprompter.config.save_intermediate_results = false
      
      expect(File).not_to receive(:open)
      teleprompter.save_results(result)
    end

    it 'saves results when configured' do
      teleprompter.config.save_intermediate_results = true
      teleprompter.config.save_path = "/tmp/test_results.json"
      
      expect(File).to receive(:open).with("/tmp/test_results.json", 'w')
      teleprompter.save_results(result)
    end
  end

  describe 'protected methods' do
    describe '#validate_single_example' do
      it 'accepts DSPy::Example objects' do
        example = DSPy::Example.new(
          signature_class: TeleprompterMath,
          input: { problem: "valid" },
          expected: { answer: "valid", explanation: "valid" }
        )
        
        expect {
          teleprompter.send(:validate_single_example, example, "test")
        }.not_to raise_error
      end

      it 'accepts structured hash format' do
        example = {
          input: { problem: "test" },
          expected: { answer: "test", explanation: "test" }
        }
        
        expect {
          teleprompter.send(:validate_single_example, example, "test")
        }.not_to raise_error
      end

      it 'accepts structured hash with string keys' do
        example = {
          'input' => { 'problem' => "test" },
          'expected' => { 'answer' => "test", 'explanation' => "test" }
        }
        
        expect {
          teleprompter.send(:validate_single_example, example, "test")
        }.not_to raise_error
      end

      it 'accepts objects with input and expected methods' do
        example = OpenStruct.new(
          input: { problem: "test" },
          expected: { answer: "test", explanation: "test" }
        )
        
        expect {
          teleprompter.send(:validate_single_example, example, "test")
        }.not_to raise_error
      end

      it 'rejects invalid formats' do
        invalid_example = { just: "data" }
        
        expect {
          teleprompter.send(:validate_single_example, invalid_example, "test")
        }.to raise_error(ArgumentError, /Invalid test/)
      end
    end

    describe '#infer_signature_class' do
      it 'infers from DSPy::Example objects' do
        examples = [
          DSPy::Example.new(
            signature_class: TeleprompterMath,
            input: { problem: "test" },
            expected: { answer: "test", explanation: "test" }
          )
        ]
        
        result = teleprompter.send(:infer_signature_class, examples)
        expect(result).to eq(TeleprompterMath)
      end

      it 'infers from hash with signature_class key' do
        examples = [
          { signature_class: TeleprompterMath, problem: "test", answer: "test" }
        ]
        
        result = teleprompter.send(:infer_signature_class, examples)
        expect(result).to eq(TeleprompterMath)
      end

      it 'returns nil when cannot infer' do
        examples = [{ problem: "test", answer: "test" }]
        
        result = teleprompter.send(:infer_signature_class, examples)
        expect(result).to be_nil
      end
    end

    describe '#default_metric_for_examples' do
      it 'creates matching metric for DSPy::Example objects' do
        examples = [
          DSPy::Example.new(
            signature_class: TeleprompterMath,
            input: { problem: "test" },
            expected: { answer: "test", explanation: "test" }
          )
        ]
        
        metric = teleprompter.send(:default_metric_for_examples, examples)
        
        expect(metric).to be_a(Proc)
        # Test that it uses example matching
        expect(metric.call(examples.first, { answer: "test", explanation: "test" })).to be(true)
      end

      it 'returns nil for non-Example objects' do
        examples = [{ problem: "test", answer: "test" }]
        
        metric = teleprompter.send(:default_metric_for_examples, examples)
        expect(metric).to be_nil
      end
    end
  end

  describe 'instrumentation' do
    it 'instruments optimization steps' do
      # Mock the instrumentation
      expect(DSPy::Instrumentation).to receive(:instrument).with(
        "dspy.optimization.test_step",
        hash_including(teleprompter_class: "MockTeleprompter")
      ).and_yield

      result = teleprompter.send(:instrument_step, "test_step") do
        "test_result"
      end
      
      expect(result).to eq("test_result")
    end

    it 'emits optimization events' do
      expect(DSPy::Instrumentation).to receive(:emit).with(
        "dspy.optimization.test_event",
        hash_including(
          teleprompter_class: "MockTeleprompter",
          timestamp: kind_of(String)
        )
      )
      
      teleprompter.send(:emit_event, "test_event", { custom: "data" })
    end
  end
end