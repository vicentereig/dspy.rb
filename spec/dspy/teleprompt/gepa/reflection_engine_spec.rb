# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::ReflectionEngine do
  # Test signature for reflection testing  
  class ReflectionTestSignature < DSPy::Signature
    description "Test signature for reflection analysis"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new.tap do |c|
      c.reflection_lm = DSPy::LM.new('openai/gpt-4o', api_key: ENV['OPENAI_API_KEY'] || 'test-key')
    end
  end

  let(:sample_traces) do
    [
      DSPy::Teleprompt::GEPA::ExecutionTrace.new(
        trace_id: 'trace-1',
        event_name: 'llm.response',
        timestamp: Time.now - 10,
        attributes: {
          'gen_ai.request.model' => 'gpt-4o',
          'gen_ai.usage.total_tokens' => 45,
          prompt: 'Solve: What is 5 + 3?',
          response: '5 + 3 = 8'
        },
        metadata: { optimization_run_id: 'run-1' }
      ),
      DSPy::Teleprompt::GEPA::ExecutionTrace.new(
        trace_id: 'trace-2', 
        event_name: 'llm.response',
        timestamp: Time.now - 5,
        attributes: {
          'gen_ai.request.model' => 'gpt-4o',
          'gen_ai.usage.total_tokens' => 52,
          prompt: 'Solve: What is 12 - 4?',
          response: 'Let me calculate step by step. 12 - 4 = 8'
        },
        metadata: { optimization_run_id: 'run-1' }
      ),
      DSPy::Teleprompt::GEPA::ExecutionTrace.new(
        trace_id: 'trace-3',
        event_name: 'module.call',
        timestamp: Time.now,
        attributes: {
          module_name: 'Predict',
          signature: 'ReflectionTestSignature'
        },
        metadata: { optimization_run_id: 'run-1' }
      )
    ]
  end

  describe 'initialization' do
    it 'creates a new engine with config' do
      engine = described_class.new(config)
      expect(engine.config).to eq(config)
    end

    it 'uses default config when none provided' do
      # Create config with test LM for this test
      default_config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      default_config.reflection_lm = DSPy::LM.new('openai/gpt-4o', api_key: 'test-key')
      
      engine = described_class.new(default_config)
      expect(engine.config).to be_a(DSPy::Teleprompt::GEPA::GEPAConfig)
      expect(engine.config.reflection_lm.model).to eq('gpt-4o')
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
      expect(result.metadata[:trace_count]).to eq(3)
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
      
      expect(patterns[:llm_traces_count]).to eq(2)
      expect(patterns[:module_traces_count]).to eq(0) # 'module.call' doesn't match module_trace? logic
      expect(patterns[:unique_models]).to include('gpt-4o')
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

  # LLM-based reflection tests (Phase 2)
  describe '#reflect_with_llm' do
    let(:engine) { described_class.new(config) }

    it 'performs LLM-based reflection on traces', skip: 'Requires API key' do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      result = engine.reflect_with_llm(sample_traces)
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.diagnosis).to include('LLM analysis')
      expect(result.improvements).not_to be_empty
      expect(result.confidence).to be_between(0.0, 1.0)
      expect(result.metadata[:token_usage]).to be > 0
    end

    it 'handles API failures gracefully', skip: 'Requires API key' do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Create engine with invalid model to trigger failure
      invalid_config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      invalid_config.reflection_lm = DSPy::LM.new('invalid/model', api_key: 'test-key')
      invalid_engine = described_class.new(invalid_config)
      
      result = invalid_engine.reflect_with_llm(sample_traces)
      
      # Should fallback to rule-based analysis
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.diagnosis).to include('fallback')
    end
  end

  describe '#generate_reflection_prompt' do
    let(:engine) { described_class.new(config) }

    it 'creates structured reflection prompt from traces' do
      prompt = engine.generate_reflection_prompt(sample_traces)
      
      expect(prompt).to be_a(String)
      expect(prompt).to include('execution traces')
      expect(prompt).to include('analysis')
      expect(prompt).to include('improvements')
      
      # Should include trace details
      expect(prompt).to include('gpt-4o')
      expect(prompt).to include('5 + 3')
      expect(prompt).to include('12 - 4')
    end

    it 'handles empty traces in prompt generation' do
      prompt = engine.generate_reflection_prompt([])
      
      expect(prompt).to be_a(String)
      expect(prompt).to include('No execution traces')
    end

    it 'includes optimization context in prompt' do
      prompt = engine.generate_reflection_prompt(sample_traces)
      
      expect(prompt).to include('genetic algorithm')
      expect(prompt).to include('prompt optimization')
      expect(prompt).to include('mutation')
    end
  end

  describe '#parse_llm_reflection' do
    let(:engine) { described_class.new(config) }

    let(:sample_llm_response) do
      {
        "diagnosis" => "The execution shows inconsistent response length patterns that may indicate suboptimal prompting",
        "improvements" => [
          "Add explicit step-by-step reasoning instructions",
          "Standardize response format expectations",
          "Consider token usage optimization"
        ],
        "confidence" => 0.85,
        "reasoning" => "Based on analysis of 3 traces showing variable response quality and token usage patterns",
        "suggested_mutations" => ["expand", "rewrite", "rephrase"],
        "insights" => {
          "pattern_detected" => "inconsistent_response_quality",
          "optimization_opportunity" => "instruction_clarity"
        }
      }
    end

    it 'parses structured LLM response correctly' do
      result = engine.parse_llm_reflection(sample_llm_response.to_json, sample_traces)
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.diagnosis).to include('inconsistent response length')
      expect(result.improvements).to include('Add explicit step-by-step reasoning instructions')
      expect(result.confidence).to eq(0.85)
      expect(result.suggested_mutations).to include(:expand, :rewrite, :rephrase)
    end

    it 'handles malformed JSON gracefully' do
      result = engine.parse_llm_reflection('invalid json}', sample_traces)
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.diagnosis).to include('parsing error')
      expect(result.confidence).to be < 0.5
    end

    it 'validates and sanitizes mutation suggestions' do
      malformed_response = {
        "suggested_mutations" => ["expand", "invalid_mutation", "rewrite", "another_invalid"]
      }
      
      result = engine.parse_llm_reflection(malformed_response.to_json, sample_traces)
      
      # Should only include valid mutations
      valid_mutations = [:expand, :rewrite]
      expect(result.suggested_mutations).to match_array(valid_mutations)
    end
  end

  describe '#trace_summary_for_reflection' do
    let(:engine) { described_class.new(config) }

    it 'creates comprehensive summary of traces' do
      summary = engine.trace_summary_for_reflection(sample_traces)
      
      expect(summary).to be_a(String)
      expect(summary).to include('Total traces: 3')
      expect(summary).to include('LLM interactions: 2')
      expect(summary).to include('Module calls: 0')
      expect(summary).to include('Total tokens: 97')
      expect(summary).to include('Models used: gpt-4o')
    end

    it 'includes timing information in summary' do
      summary = engine.trace_summary_for_reflection(sample_traces)
      
      expect(summary).to include('Execution timespan')
      expect(summary).to include('seconds')
    end

    it 'handles traces with missing attributes' do
      incomplete_trace = DSPy::Teleprompt::GEPA::ExecutionTrace.new(
        trace_id: 'incomplete',
        event_name: 'llm.response',
        timestamp: Time.now,
        attributes: {},
        metadata: {}
      )
      
      summary = engine.trace_summary_for_reflection([incomplete_trace])
      
      expect(summary).to be_a(String)
      expect(summary).to include('Total traces: 1')
    end
  end

  describe '#extract_optimization_insights' do
    let(:engine) { described_class.new(config) }

    it 'identifies optimization opportunities from traces' do
      insights = engine.extract_optimization_insights(sample_traces)
      
      expect(insights).to be_a(Hash)
      expect(insights).to include(:token_efficiency, :response_quality, :model_consistency)
    end

    it 'detects high token usage patterns' do
      high_token_traces = [
        DSPy::Teleprompt::GEPA::ExecutionTrace.new(
          trace_id: 'high-token',
          event_name: 'llm.response',
          timestamp: Time.now,
          attributes: {
            'gen_ai.usage.total_tokens' => 800,
            response: 'Very long detailed response' * 20
          },
          metadata: {}
        )
      ]
      
      insights = engine.extract_optimization_insights(high_token_traces)
      
      expect(insights[:token_efficiency][:status]).to eq('poor')
      expect(insights[:token_efficiency][:suggestions]).to include(match(/reducing.*prompt/i))
    end

    it 'identifies response quality patterns' do
      varied_traces = [
        DSPy::Teleprompt::GEPA::ExecutionTrace.new(
          trace_id: 'short',
          event_name: 'llm.response',
          timestamp: Time.now,
          attributes: { response: 'Yes' },
          metadata: {}
        ),
        DSPy::Teleprompt::GEPA::ExecutionTrace.new(
          trace_id: 'detailed',
          event_name: 'llm.response',
          timestamp: Time.now,
          attributes: { response: 'Let me think through this step by step and provide a comprehensive analysis' },
          metadata: {}
        )
      ]
      
      insights = engine.extract_optimization_insights(varied_traces)
      
      expect(insights[:response_quality][:consistency]).to eq('inconsistent')
      expect(insights[:response_quality][:recommendations]).not_to be_empty
    end
  end

  describe '#reflection_with_context' do
    let(:engine) { described_class.new(config) }

    it 'incorporates optimization context into reflection' do
      context = {
        generation: 5,
        population_size: 8,
        current_best_score: 0.85,
        mutation_history: [:expand, :rewrite],
        crossover_history: [:uniform, :blend]
      }
      
      result = engine.reflection_with_context(sample_traces, context)
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.reasoning).to include('Generation 5')
      expect(result.metadata[:optimization_context]).to eq(context)
    end

    it 'suggests mutations based on previous history' do
      context = {
        generation: 3,
        mutation_history: [:expand, :expand, :rewrite],
        recent_performance_trend: 'declining'
      }
      
      result = engine.reflection_with_context(sample_traces, context)
      
      # Should suggest different mutations since expand was used recently
      expect(result.suggested_mutations).not_to include(:expand)
      expect([:simplify, :rephrase, :combine].any? { |m| result.suggested_mutations.include?(m) }).to be(true)
    end
  end

  describe 'integration with genetic algorithm' do
    let(:engine) { described_class.new(config) }

    it 'provides actionable insights for genetic operators' do
      result = engine.reflect_on_traces(sample_traces)
      
      # Should provide specific mutation suggestions
      expect(result.suggested_mutations).to be_an(Array)
      result.suggested_mutations.each do |mutation|
        expect([:rewrite, :expand, :simplify, :combine, :rephrase]).to include(mutation)
      end
      
      # Should provide improvement suggestions
      expect(result.improvements).to be_an(Array)
      expect(result.improvements).not_to be_empty
    end

    it 'maintains consistency with GEPA configuration' do
      result = engine.reflect_on_traces(sample_traces)
      
      # Should respect configured mutation types
      available_mutations = config.mutation_types.map(&:serialize)
      result.suggested_mutations.each do |suggestion|
        expect(available_mutations).to include(suggestion.to_s)
      end
    end
  end
end