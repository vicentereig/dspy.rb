# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::ReflectionEngine do
  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new.tap do |c|
      c.reflection_lm = 'gpt-4o'
    end
  end

  let(:sample_traces) do
    [
      DSPy::Teleprompt::GEPA::ExecutionTrace.new(
        trace_id: 'trace-1',
        event_name: 'llm.response',
        timestamp: Time.now,
        attributes: {
          'gen_ai.request.model' => 'gpt-4',
          prompt: 'What is 2+2?',
          response: 'The answer is four.'
        },
        metadata: { optimization_run_id: 'run-001' }
      ),
      DSPy::Teleprompt::GEPA::ExecutionTrace.new(
        trace_id: 'trace-2', 
        event_name: 'chain_of_thought.reasoning_complete',
        timestamp: Time.now,
        attributes: {
          'dspy.signature' => 'QuestionAnswering',
          reasoning: 'I need to solve 2+2. This is a simple addition problem.'
        },
        metadata: { optimization_run_id: 'run-001' }
      )
    ]
  end

  describe 'initialization' do
    it 'creates a new engine with config' do
      engine = described_class.new(config)
      expect(engine.config).to eq(config)
    end

    it 'uses default config when none provided' do
      engine = described_class.new
      expect(engine.config).to be_a(DSPy::Teleprompt::GEPA::GEPAConfig)
      expect(engine.config.reflection_lm).to eq('gpt-4o')
    end
  end

  describe '#reflect_on_traces' do
    let(:engine) { described_class.new(config) }

    it 'returns a ReflectionResult for given traces' do
      result = engine.reflect_on_traces(sample_traces)
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.trace_id).to match(/^reflection-\h{8}$/)
      expect(result.confidence).to be_between(0.0, 1.0)
    end

    it 'handles empty trace array' do
      result = engine.reflect_on_traces([])
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.diagnosis).to include('No traces')
      expect(result.confidence).to eq(0.0)
      expect(result.improvements).to be_empty
    end

    it 'includes trace analysis in diagnosis' do
      result = engine.reflect_on_traces(sample_traces)
      
      expect(result.diagnosis).not_to be_empty
      expect(result.reasoning).not_to be_empty
    end

    it 'suggests actionable improvements' do
      result = engine.reflect_on_traces(sample_traces)
      
      expect(result.improvements).to be_an(Array)
      expect(result.suggested_mutations).to be_an(Array)
    end

    it 'includes metadata about the reflection process' do
      result = engine.reflect_on_traces(sample_traces)
      
      expect(result.metadata).to include(
        :reflection_model,
        :analysis_timestamp,
        :trace_count
      )
      expect(result.metadata[:reflection_model]).to eq('gpt-4o')
      expect(result.metadata[:trace_count]).to eq(2)
    end
  end

  describe '#analyze_execution_patterns' do
    let(:engine) { described_class.new(config) }

    it 'extracts patterns from execution traces' do
      patterns = engine.analyze_execution_patterns(sample_traces)
      
      expect(patterns).to be_a(Hash)
      expect(patterns).to include(
        :llm_traces_count,
        :module_traces_count,
        :total_tokens,
        :unique_models
      )
    end

    it 'counts trace types correctly' do
      patterns = engine.analyze_execution_patterns(sample_traces)
      
      expect(patterns[:llm_traces_count]).to eq(1)
      expect(patterns[:module_traces_count]).to eq(1)
      expect(patterns[:unique_models]).to include('gpt-4')
    end

    it 'handles empty traces' do
      patterns = engine.analyze_execution_patterns([])
      
      expect(patterns[:llm_traces_count]).to eq(0)
      expect(patterns[:module_traces_count]).to eq(0)
      expect(patterns[:total_tokens]).to eq(0)
    end
  end

  describe '#generate_improvement_suggestions' do
    let(:engine) { described_class.new(config) }
    let(:patterns) do
      {
        llm_traces_count: 1,
        module_traces_count: 1,
        total_tokens: 150,
        unique_models: ['gpt-4'],
        avg_response_length: 20
      }
    end

    it 'returns array of improvement suggestions' do
      suggestions = engine.generate_improvement_suggestions(patterns)
      
      expect(suggestions).to be_an(Array)
      expect(suggestions).not_to be_empty
      expect(suggestions.first).to be_a(String)
    end

    it 'suggests different improvements based on patterns' do
      high_token_patterns = patterns.merge(total_tokens: 1000)
      low_token_patterns = patterns.merge(total_tokens: 50)
      
      high_suggestions = engine.generate_improvement_suggestions(high_token_patterns)
      low_suggestions = engine.generate_improvement_suggestions(low_token_patterns)
      
      expect(high_suggestions).not_to eq(low_suggestions)
    end
  end

  describe '#suggest_mutations' do
    let(:engine) { described_class.new(config) }
    let(:patterns) do
      {
        llm_traces_count: 2,
        module_traces_count: 1,
        avg_response_length: 15
      }
    end

    it 'returns array of mutation symbols' do
      mutations = engine.suggest_mutations(patterns)
      
      expect(mutations).to be_an(Array)
      expect(mutations).not_to be_empty
      mutations.each { |m| expect(m).to be_a(Symbol) }
    end

    it 'suggests appropriate mutations based on patterns' do
      mutations = engine.suggest_mutations(patterns)
      
      valid_mutations = [:rewrite, :expand, :combine, :simplify, :rephrase]
      mutations.each { |m| expect(valid_mutations).to include(m) }
    end
  end
end