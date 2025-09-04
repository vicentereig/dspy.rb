# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Teleprompt::GEPA Simple Optimization' do
  # Test signature
  class TestOptimSignature < DSPy::Signature
    description "Solve problems clearly and accurately"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:metric) { proc { |example, prediction| example.expected_values[:answer] == prediction.answer ? 1.0 : 0.0 } }
  let(:gepa) { DSPy::Teleprompt::GEPA.new(metric: metric) }

  let(:mock_program) do
    double('program', signature_class: TestOptimSignature).tap do |prog|
      allow(prog).to receive(:call) do |**kwargs|
        # Simple mock implementation - just return the input as answer
        DSPy::Prediction.new(
          signature_class: TestOptimSignature,
          answer: kwargs[:question] == "What is 2+2?" ? "4" : "unknown"
        )
      end
    end
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: TestOptimSignature,
        input: { question: 'What is 2+2?' },
        expected: { answer: '4' }
      )
    ]
  end

  describe '#generate_instruction_variants' do
    it 'generates step-by-step variant' do
      original = "Answer the question"
      variants = gepa.send(:generate_instruction_variants, original)
      
      expect(variants).to include("Answer the question Think step by step.")
    end

    it 'generates detailed variant' do
      original = "Solve this problem"  
      variants = gepa.send(:generate_instruction_variants, original)
      
      expect(variants).to include("Solve this problem Provide detailed reasoning.")
    end

    it 'generates careful variant' do
      original = "Calculate the result"
      variants = gepa.send(:generate_instruction_variants, original)
      
      expect(variants).to include("Be careful and accurate. Calculate the result")
    end

    it 'skips variants that already exist' do
      original = "Answer step by step with detailed reasoning"
      variants = gepa.send(:generate_instruction_variants, original)
      
      # Should skip step-by-step and detailed variants, may include careful variant
      step_variants = variants.select { |v| v.include?("Think step by step") }
      detailed_variants = variants.select { |v| v.include?("Provide detailed reasoning") }
      
      expect(step_variants).to be_empty
      expect(detailed_variants).to be_empty
    end

    it 'limits to 3 variants maximum' do
      original = "Simple instruction"
      variants = gepa.send(:generate_instruction_variants, original)
      
      expect(variants.size).to be <= 3
    end
  end

  describe '#evaluate_program' do
    it 'evaluates program performance using metric' do
      allow(mock_program).to receive(:call).with(question: 'What is 2+2?').and_return(
        double('prediction', answer: '4')
      )
      
      score = gepa.send(:simple_evaluate_program, mock_program, trainset)
      expect(score).to eq(1.0)
    end

    it 'handles program call errors gracefully' do
      allow(mock_program).to receive(:call).and_raise(StandardError, 'Test error')
      
      expect(gepa).to receive(:emit_event).with('evaluation_error', hash_including(error: 'Test error'))
      
      score = gepa.send(:simple_evaluate_program, mock_program, trainset)
      expect(score).to eq(0.0)
    end

    it 'averages scores across multiple examples' do
      trainset = [
        DSPy::Example.new(
          signature_class: TestOptimSignature,
          input: { question: 'Q1' },
          expected: { answer: 'A1' }
        ),
        DSPy::Example.new(
          signature_class: TestOptimSignature,
          input: { question: 'Q2' },
          expected: { answer: 'A2' }
        )
      ]

      allow(mock_program).to receive(:call).with(question: 'Q1').and_return(
        double('prediction', answer: 'A1')  # Correct
      )
      allow(mock_program).to receive(:call).with(question: 'Q2').and_return(
        double('prediction', answer: 'Wrong')  # Incorrect
      )
      
      score = gepa.send(:simple_evaluate_program, mock_program, trainset)
      expect(score).to eq(0.5)  # Average of 1.0 and 0.0
    end
  end

  describe '#basic_result' do
    it 'returns basic optimization result' do
      result = gepa.send(:basic_result, mock_program)
      
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).to eq(mock_program)
      expect(result.best_score_value).to eq(0.0)
      expect(result.metadata[:implementation_status]).to include('Phase 1')
    end
  end

  describe 'simple optimization mode' do
    let(:simple_config) do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.simple_mode = true
      config
    end
    
    let(:simple_gepa) { DSPy::Teleprompt::GEPA.new(metric: metric, config: simple_config) }

    it 'uses simple optimization when simple_mode is enabled' do
      allow(mock_program).to receive(:respond_to?).with(:signature_class).and_return(true)
      allow(mock_program).to receive(:signature_class).and_return(TestOptimSignature)
      allow(mock_program).to receive(:call).and_return(double('prediction', answer: '4'))
      
      expect(simple_gepa).to receive(:perform_simple_optimization).and_call_original
      
      result = simple_gepa.compile(mock_program, trainset: trainset, valset: trainset)
      expect(result.metadata[:mode]).to eq('Simple Optimization')
    end

    it 'falls back to basic result when program lacks signature_class' do
      allow(mock_program).to receive(:respond_to?).with(:signature_class).and_return(false)
      
      result = simple_gepa.compile(mock_program, trainset: trainset, valset: trainset)
      expect(result.metadata[:implementation_status]).to include('Phase 1')
    end
  end

  describe 'integration with existing tests' do
    it 'maintains backward compatibility with Phase 1 tests' do
      # For backward compatibility test, enable simple_mode
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.simple_mode = true
      simple_gepa = DSPy::Teleprompt::GEPA.new(metric: metric, config: config)
      
      result = simple_gepa.compile(mock_program, trainset: trainset, valset: trainset)
      
      # Should return simple optimization result
      expect(result.metadata[:mode]).to eq('Simple Optimization')
      expect(result.metadata[:optimizer]).to eq('GEPA')
      expect(result.history[:variants_tested]).to eq(3)
    end
  end
end