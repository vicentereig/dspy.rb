# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GEPA Phase 1 Integration' do
  # Simple signature for integration testing
  class IntegrationTestSignature < DSPy::Signature
    description "Answer questions accurately and concisely"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
    end
  end

  let(:metric) { proc { |example, prediction| example.expected_values[:answer] == prediction.answer } }
  let(:gepa_config) do
    config = DSPy::Teleprompt::GEPA::GEPAConfig.new
    # Use a real LM instance for testing
    reflection_lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    config.reflection_lm = reflection_lm
    # Reduce size for faster testing
    config.num_generations = 2
    config.population_size = 2
    config
  end
  let(:gepa) { DSPy::Teleprompt::GEPA.new(metric: metric, config: gepa_config) }

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: IntegrationTestSignature,
        input: { question: 'What is 2+2?' },
        expected: { answer: '4' }
      ),
      DSPy::Example.new(
        signature_class: IntegrationTestSignature,
        input: { question: 'What is the capital of France?' },
        expected: { answer: 'Paris' }
      )
    ]
  end

  let(:valset) do
    [
      DSPy::Example.new(
        signature_class: IntegrationTestSignature,
        input: { question: 'What is 3+3?' },
        expected: { answer: '6' }
      )
    ]
  end

  describe 'Full GEPA workflow integration' do
    let(:program) do
      double('program', signature_class: IntegrationTestSignature).tap do |prog|
        allow(prog).to receive(:call) do |**kwargs|
          # Mock implementation for testing
          answer = case kwargs[:question]
          when 'What is 2+2?' then '4'
          when 'What is the capital of France?' then 'Paris'
          when 'What is 3+3?' then '6'
          else 'I don\'t know'
          end
          
          DSPy::Prediction.new(
            signature_class: IntegrationTestSignature,
            answer: answer
          )
        end
      end
    end

    it 'executes complete Phase 1 workflow without errors', vcr: { cassette_name: "gepa_phase1_workflow_execution" } do
      expect { gepa.compile(program, trainset: trainset, valset: valset) }.not_to raise_error
    end

    it 'returns proper OptimizationResult structure', vcr: { cassette_name: "gepa_phase1_optimization_result" } do
      skip 'Skip until GEPA retry logic is optimized'
      result = gepa.compile(program, trainset: trainset, valset: valset)
      
      expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
      expect(result.optimized_program).to eq(program)
      expect(result.scores).to include(:fitness_score, :primary_score, :token_efficiency)
      expect(result.metadata).to include(
        :optimizer,
        :reflection_lm,
        :implementation_status
      )
      expect(result.metadata[:optimizer]).to eq('GEPA')
    end
  end

  describe 'TraceCollector integration' do
    let(:collector) { DSPy::Teleprompt::GEPA::TraceCollector.new }

    it 'creates collector and collects traces from events' do
      expect(collector.collected_count).to eq(0)
      
      # Simulate collecting traces
      collector.collect_trace('llm.response', {
        'trace_id' => 'integration-trace-1',
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'attributes' => {
          'gen_ai.request.model' => 'gpt-4',
          prompt: 'What is the capital of Japan?',
          response: 'Tokyo'
        },
        'metadata' => { optimization_run_id: 'integration-run' }
      })

      expect(collector.collected_count).to eq(1)
      expect(collector.llm_traces.size).to eq(1)
      expect(collector.module_traces.size).to eq(0)
    end

    it 'handles mixed trace types correctly' do
      # Add LLM trace
      collector.collect_trace('llm.response', {
        'trace_id' => 'llm-integration-trace',
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'attributes' => { prompt: 'Test prompt', response: 'Test response' },
        'metadata' => {}
      })

      # Add module trace
      collector.collect_trace('chain_of_thought.reasoning_complete', {
        'trace_id' => 'module-integration-trace',
        'event_name' => 'chain_of_thought.reasoning_complete',
        'timestamp' => Time.now,
        'attributes' => { reasoning: 'Step 1: Analyze...' },
        'metadata' => {}
      })

      expect(collector.collected_count).to eq(2)
      expect(collector.llm_traces.size).to eq(1)
      expect(collector.module_traces.size).to eq(1)
    end
  end

  describe 'ReflectionEngine integration' do
    let(:engine_config) do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      reflection_lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      config.reflection_lm = reflection_lm
      config
    end
    let(:engine) { DSPy::Teleprompt::GEPA::ReflectionEngine.new(engine_config) }
    let(:sample_traces) do
      [
        DSPy::Teleprompt::GEPA::ExecutionTrace.new(
          trace_id: 'reflection-test-1',
          event_name: 'llm.response',
          timestamp: Time.now,
          attributes: {
            'gen_ai.request.model' => 'gpt-4',
            'gen_ai.usage.total_tokens' => 150,
            prompt: 'What is artificial intelligence?',
            response: 'AI is a field of computer science focused on creating systems that can perform tasks typically requiring human intelligence.'
          },
          metadata: { optimization_run_id: 'reflection-run' }
        ),
        DSPy::Teleprompt::GEPA::ExecutionTrace.new(
          trace_id: 'reflection-test-2',
          event_name: 'chain_of_thought.reasoning_complete',
          timestamp: Time.now + 1,
          attributes: {
            'dspy.signature' => 'QuestionAnswering',
            reasoning: 'First, I need to define what AI means. Then I should explain its key characteristics...'
          },
          metadata: { optimization_run_id: 'reflection-run' }
        )
      ]
    end

    it 'performs complete reflective analysis', vcr: { cassette_name: "gepa_reflection_analysis" } do
      result = engine.reflect_on_traces(sample_traces)
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.trace_id).to match(/^reflection-\h{8}$/)
      expect(result.confidence).to be_between(0.0, 1.0)
      expect(result.diagnosis).not_to be_empty
      expect(result.improvements).to be_an(Array)
      expect(result.suggested_mutations).to be_an(Array)
      expect(result.metadata).to include(
        :reflection_model,
        :analysis_timestamp,
        :trace_count
      )
    end

    it 'analyzes execution patterns correctly' do
      patterns = engine.analyze_execution_patterns(sample_traces)
      
      expect(patterns).to include(
        :llm_traces_count,
        :module_traces_count,
        :total_tokens,
        :unique_models,
        :avg_response_length,
        :trace_timespan
      )
      
      expect(patterns[:llm_traces_count]).to eq(1)
      expect(patterns[:module_traces_count]).to eq(1)
      expect(patterns[:total_tokens]).to eq(150)
      expect(patterns[:unique_models]).to include('gpt-4')
    end

    it 'generates actionable improvement suggestions' do
      patterns = {
        llm_traces_count: 3,
        module_traces_count: 1,
        total_tokens: 600,
        unique_models: ['gpt-4', 'gpt-3.5'],
        avg_response_length: 8
      }

      suggestions = engine.generate_improvement_suggestions(patterns)
      
      expect(suggestions).to be_an(Array)
      expect(suggestions).not_to be_empty
      expect(suggestions).to include('Consider reducing prompt length to lower token usage')
      expect(suggestions).to include('Multiple models used - consider standardizing on one model for consistency')
      expect(suggestions).to include('Responses seem brief - consider asking for more detailed explanations')
    end
  end

  describe 'Component interaction integration' do
    let(:collector) { DSPy::Teleprompt::GEPA::TraceCollector.new }
    let(:engine_config) do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      reflection_lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      config.reflection_lm = reflection_lm
      config
    end
    let(:engine) { DSPy::Teleprompt::GEPA::ReflectionEngine.new(engine_config) }

    it 'works with TraceCollector feeding ReflectionEngine', vcr: { cassette_name: "gepa_component_interaction" } do
      # Collect some traces
      collector.collect_trace('llm.response', {
        'trace_id' => 'interaction-test-1',
        'event_name' => 'llm.response',
        'timestamp' => Time.now,
        'attributes' => {
          'gen_ai.usage.total_tokens' => 200,
          prompt: 'Explain quantum computing',
          response: 'Quantum computing uses quantum mechanical phenomena...'
        },
        'metadata' => {}
      })

      collector.collect_trace('llm.response', {
        'trace_id' => 'interaction-test-2',
        'event_name' => 'llm.response',
        'timestamp' => Time.now + 2,
        'attributes' => {
          'gen_ai.usage.total_tokens' => 180,
          prompt: 'What are qubits?',
          response: 'Qubits are the basic units of quantum information...'
        },
        'metadata' => {}
      })

      # Analyze collected traces with reflection engine
      reflection_result = engine.reflect_on_traces(collector.traces)
      
      expect(reflection_result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(reflection_result.metadata[:trace_count]).to eq(2)
      expect(reflection_result.diagnosis).not_to be_empty
      expect(reflection_result.improvements).not_to be_empty
      
      # Verify pattern analysis worked correctly
      patterns = engine.analyze_execution_patterns(collector.traces)
      expect(patterns[:llm_traces_count]).to eq(2)
      expect(patterns[:total_tokens]).to eq(380)
    end
  end

  describe 'Error handling and edge cases' do
    let(:collector) { DSPy::Teleprompt::GEPA::TraceCollector.new }
    let(:engine_config) do
      config = DSPy::Teleprompt::GEPA::GEPAConfig.new
      reflection_lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      config.reflection_lm = reflection_lm
      config
    end
    let(:engine) { DSPy::Teleprompt::GEPA::ReflectionEngine.new(engine_config) }

    it 'handles empty trace collection gracefully', vcr: { cassette_name: "gepa_empty_traces" } do
      expect(collector.collected_count).to eq(0)
      expect(collector.traces).to be_empty
      
      # Reflection on empty traces should work
      result = engine.reflect_on_traces(collector.traces)
      expect(result.confidence).to eq(0.0)
      expect(result.diagnosis).to include('No traces')
    end

    it 'handles malformed trace data gracefully' do
      # Collect trace with minimal data
      collector.collect_trace('test.event', {})
      
      expect(collector.collected_count).to eq(1)
      trace = collector.traces.first
      expect(trace.trace_id).to match(/^gepa-trace-\h{8}$/) # Generated ID
      expect(trace.event_name).to eq('test.event')
    end

    it 'maintains thread safety across components', vcr: { cassette_name: "gepa_thread_safety" } do
      threads = []
      
      # Multiple threads collecting traces
      5.times do |i|
        threads << Thread.new do
          collector.collect_trace('llm.response', {
            'trace_id' => "thread-test-#{i}",
            'event_name' => 'llm.response',
            'timestamp' => Time.now,
            'attributes' => { prompt: "Test #{i}" },
            'metadata' => {}
          })
        end
      end
      
      # Multiple threads analyzing traces
      5.times do |i|
        threads << Thread.new do
          engine.reflect_on_traces(collector.traces)
        end
      end
      
      threads.each(&:join)
      
      # Should have collected all traces without race conditions
      expect(collector.collected_count).to eq(5)
    end
  end
end