# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA do
  # Simple signature for testing
  class TestQuestionAnswering < DSPy::Signature
    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:metric) { proc { |example, prediction| example.expected_values[:answer] == prediction.answer } }
  
  describe 'inheritance' do
    it 'inherits from Teleprompter' do
      expect(described_class).to be < DSPy::Teleprompt::Teleprompter
    end
  end
  
  describe 'initialization' do
    context 'with default config' do
      it 'creates a new instance' do
        config = DSPy::Teleprompt::GEPA::GEPAConfig.new
        # Use a real LM object instead of a mock to satisfy Sorbet type checking
        config.reflection_lm = DSPy::LM.new('openai/gpt-4o', api_key: 'test-key-for-spec-only')
        gepa = described_class.new(metric: metric, config: config)
        expect(gepa).to be_a(described_class)
        expect(gepa.metric).to eq(metric)
      end
    end
    
    context 'with custom config' do
      let(:config) { DSPy::Teleprompt::GEPA::GEPAConfig.new }
      
      it 'accepts custom configuration' do
        config.reflection_lm = DSPy::LM.new('openai/gpt-4o', api_key: 'test-key-for-spec-only')
        config.num_generations = 5
        
        gepa = described_class.new(metric: metric, config: config)
        expect(gepa.config).to eq(config)
        expect(gepa.config.reflection_lm.model).to eq('gpt-4o')
        expect(gepa.config.num_generations).to eq(5)
      end
    end
  end
  
  describe 'configuration' do
    describe 'GEPAConfig' do
      let(:config) { DSPy::Teleprompt::GEPA::GEPAConfig.new }
      
      it 'has default values' do
        # reflection_lm must be set by user - no default
        expect(config.num_generations).to eq(10)
        expect(config.population_size).to eq(8)
        expect(config.mutation_rate).to eq(0.7)
        expect(config.use_pareto_selection).to be(true)
      end
      
      it 'allows configuration updates' do
        config.reflection_lm = DSPy::LM.new('anthropic/claude-3-5-sonnet-20241022', api_key: 'test-key')
        config.num_generations = 15
        config.population_size = 12
        config.mutation_rate = 0.8
        config.use_pareto_selection = false
        
        expect(config.reflection_lm.model).to eq('claude-3-5-sonnet-20241022')
        expect(config.num_generations).to eq(15)
        expect(config.population_size).to eq(12)
        expect(config.mutation_rate).to eq(0.8)
        expect(config.use_pareto_selection).to be(false)
      end
    end
  end
  
  describe '#compile' do
    let(:program) do
      double('program', signature_class: TestQuestionAnswering).tap do |prog|
        allow(prog).to receive(:call) do |**kwargs|
          # Mock implementation for testing
          answer = case kwargs[:question]
          when 'What is 2+2?' then '4'
          when 'What is the capital of France?' then 'Paris'
          when 'What is 3+3?' then '6'
          else 'I don\'t know'
          end
          
          DSPy::Prediction.new(
            signature_class: TestQuestionAnswering,
            answer: answer
          )
        end
      end
    end
    let(:trainset) do
      [
        DSPy::Example.new(
          signature_class: TestQuestionAnswering,
          input: { question: 'What is 2+2?' },
          expected: { answer: '4' }
        ),
        DSPy::Example.new(
          signature_class: TestQuestionAnswering,
          input: { question: 'What is the capital of France?' },
          expected: { answer: 'Paris' }
        )
      ]
    end
    let(:valset) do
      [
        DSPy::Example.new(
          signature_class: TestQuestionAnswering,
          input: { question: 'What is 3+3?' },
          expected: { answer: '6' }
        )
      ]
    end
    
    it 'implements the required compile interface' do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new('openai/gpt-4o', api_key: 'test-key')
      gepa = described_class.new(metric: metric, config: config)
      
      # Should not raise error when called with required parameters
      expect { gepa.compile(program, trainset: trainset, valset: valset) }.not_to raise_error
    end
    
    it 'returns an OptimizationResult' do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      config.reflection_lm = DSPy::LM.new('openai/gpt-4o', api_key: 'test-key')
      gepa = described_class.new(metric: metric, config: config)
      result = gepa.compile(program, trainset: trainset, valset: valset)
      
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
    end
  end
end