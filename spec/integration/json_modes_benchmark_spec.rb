# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/benchmark_types'
require_relative '../../examples/json_modes_benchmark'
require_relative '../../examples/json_modes_benchmark_util'

RSpec.describe 'JSON Extraction Modes Benchmark' do
  # Model constants for 2025 testing
  OPENAI_MODELS = %w[
    gpt-5 gpt-5-mini gpt-5-nano 
    gpt-4o gpt-4o-mini 
    o1 o1-mini
  ].freeze

  ANTHROPIC_MODELS = %w[
    claude-opus-4.1 claude-sonnet-4 
    claude-3-5-sonnet claude-3-5-haiku
  ].freeze

  GOOGLE_MODELS = %w[
    gemini-1.5-pro gemini-1.5-flash 
    gemini-2.0-flash-exp
  ].freeze

  ALL_MODELS = (OPENAI_MODELS + ANTHROPIC_MODELS + GOOGLE_MODELS).freeze

  EXTRACTION_STRATEGIES = %w[
    enhanced_prompting
    openai_structured_output
    anthropic_tool_use
    anthropic_extraction
    gemini_structured_output
  ].freeze

  let(:test_query) { "Create a todo for implementing JSON benchmark tests with high priority" }
  let(:test_context) do
    ProjectContext.new(
      project_id: "proj-123",
      active_lists: ["main-backlog", "sprint-current"],
      available_tags: ["backend", "testing", "priority"]
    )
  end
  let(:test_user_profile) do
    UserProfile.new(
      user_id: "user-456",
      role: UserRole::Admin,
      timezone: "UTC"
    )
  end

  describe 'TodoListManagementSignature complex type handling' do
    before do
      # Ensure we have a clean configuration for each test
      DSPy.configure { |c| c.structured_outputs.strategy = nil }
    end

    context 'with enhanced_prompting strategy' do
      before do
        DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Compatible }
      end

      it 'processes complex nested types with enums and unions', vcr: { cassette_name: 'json_benchmark_enhanced_prompting' } do
        skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
        
        # This test will fail until we implement TodoListManagementSignature
        expect { TodoListManagementSignature }.not_to raise_error
        
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
        DSPy.configure { |c| c.lm = lm }
        predictor = DSPy::Predict.new(TodoListManagementSignature)
        
        result = predictor.call(
          query: test_query,
          context: test_context,
          user_profile: test_user_profile
        )
        
        # Verify complex type structure
        expect(result.action).to be_a(T::Struct) # Should be one of the action structs
        expect(result.affected_todos).to be_a(Array)
        expect(result.affected_todos.first).to be_a(TodoItem) if result.affected_todos.any?
        expect(result.summary).to be_a(TodoSummary)
        expect(result.related_actions).to be_a(Array)
      end

    end

    context 'with openai_structured_output strategy' do
      before do
        DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      end

      it 'successfully processes union types via anyOf conversion', vcr: { cassette_name: 'json_benchmark_openai_structured_output' } do
        skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
        
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'], structured_outputs: true)
        DSPy.configure { |c| c.lm = lm }
        
        predictor = DSPy::Predict.new(TodoListManagementSignature)
        result = predictor.call(
          query: test_query,
          context: test_context,
          user_profile: test_user_profile
        )
        
        # Verify complex type structure (same as enhanced_prompting test)
        expect(result.action).to be_a(T::Struct) # Should be one of the action structs
        expect(result.affected_todos).to be_a(Array)
        expect(result.affected_todos.first).to be_a(TodoItem) if result.affected_todos.any?
        expect(result.summary).to be_a(TodoSummary)
        expect(result.related_actions).to be_a(Array)
      end
    end

    context 'with anthropic strategies' do
      before do
        DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      end

      it 'forces Anthropic tool use strategy', vcr: { cassette_name: 'json_benchmark_anthropic_tool_use' } do
        skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
        
        lm = DSPy::LM.new('anthropic/claude-3-haiku-20240307', api_key: ENV['ANTHROPIC_API_KEY'])
        DSPy.configure { |c| c.lm = lm }
        
        allow(DSPy.logger).to receive(:debug).and_call_original
        
        predictor = DSPy::Predict.new(TodoListManagementSignature)
        result = predictor.call(
          query: test_query,
          context: test_context,
          user_profile: test_user_profile
        )
        
        expect(DSPy.logger).to have_received(:debug).with(/anthropic_tool_use/)
        expect(result.action).to be_a(T::Struct) # Union type should resolve to specific struct
        expect(result.action.class.name).to match(/Action$/) # Should be one of our action types
      end

      it 'tests anthropic extraction strategy fallback' do
        skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
        
        # This would test the fallback to anthropic_extraction if tool_use isn't available
        # Implementation details will depend on how we force specific strategies
      end
    end

    context 'with gemini_structured_output strategy' do
      before do
        DSPy.configure { |c| c.structured_outputs.strategy = DSPy::Strategy::Strict }
      end

      it 'successfully processes union types via Gemini native structured outputs', vcr: { cassette_name: 'json_benchmark_gemini_structured_output' } do
        skip 'Requires GEMINI_API_KEY or GOOGLE_API_KEY' unless ENV['GEMINI_API_KEY'] || ENV['GOOGLE_API_KEY']
        
        api_key = ENV['GEMINI_API_KEY'] || ENV['GOOGLE_API_KEY']
        lm = DSPy::LM.new('gemini/gemini-1.5-pro', api_key: api_key, structured_outputs: true)
        DSPy.configure { |c| c.lm = lm }
        
        allow(DSPy.logger).to receive(:debug).and_call_original
        
        predictor = DSPy::Predict.new(TodoListManagementSignature)
        result = predictor.call(
          query: test_query,
          context: test_context,
          user_profile: test_user_profile
        )
        
        expect(DSPy.logger).to have_received(:debug).with(/gemini_structured_output/).at_least(:once)
        expect(result.action).to be_a(T::Struct) # Union type should resolve to specific struct
        expect(result.action.class.name).to match(/Action$/) # Should be one of our action types
        expect(result.affected_todos).to be_a(Array)
        expect(result.summary).to be_a(TodoSummary)
        expect(result.related_actions).to be_a(Array)
      end
    end
  end

  describe 'Union type discrimination' do
    let(:lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }
    let(:predictor) { DSPy::Predict.new(TodoListManagementSignature) }
    
    before do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      DSPy.configure { |c| c.lm = lm }
    end

    it 'correctly deserializes different action types based on _type field', vcr: { cassette_name: 'union_discrimination_create_action' } do
      result = predictor.call(
        query: "Create a high-priority todo for implementing union type tests",
        context: test_context,
        user_profile: test_user_profile
      )
      
      # Verify the action field is properly deserialized to a struct, not a hash
      expect(result.action).to be_a(T::Struct)
      expect(result.action.class.name).to match(/Action$/)
      
      # Verify _type discrimination worked
      if result.action.respond_to?(:_type)
        expect(result.action._type).to be_a(String)
        expect(result.action._type).to match(/Action$/)
      end
      
      # Verify it's likely a CreateTodoAction based on query
      if result.action.respond_to?(:title)
        expect(result.action.title).to be_a(String)
        expect(result.action.title.downcase).to include('union')
      end
    end

    it 'handles arrays of union types', vcr: { cassette_name: 'union_discrimination_related_actions' } do
      result = predictor.call(
        query: "Create a todo and suggest related follow-up actions",
        context: test_context,
        user_profile: test_user_profile
      )
      
      # Verify related_actions is an array
      expect(result.related_actions).to be_a(Array)
      
      # If we have related actions, verify they're properly deserialized structs
      if result.related_actions.any?
        result.related_actions.each do |action|
          expect(action).to be_a(T::Struct)
          expect(action.class.name).to match(/Action$/)
        end
      end
    end

    it 'falls back gracefully when _type field is missing', vcr: { cassette_name: 'union_discrimination_graceful_fallback' } do
      # This test verifies our type coercion handles malformed JSON gracefully
      # Test with actual LLM call but check that it doesn't crash on edge cases
      
      # Use a query that might produce ambiguous action types
      result = predictor.call(
        query: "Do something with todos",
        context: test_context,
        user_profile: test_user_profile
      )
      
      # Should complete successfully even with ambiguous input
      expect(result).not_to be_nil
      expect(result.action).not_to be_nil
      
      # Basic structure should be preserved
      expect(result.affected_todos).to be_a(Array)
      expect(result.summary).to be_a(T::Struct)
      expect(result.related_actions).to be_a(Array)
    end
  end

  describe 'Benchmark data collection' do
    let(:lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }
    let(:predictor) { DSPy::Predict.new(TodoListManagementSignature) }
    
    before do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      DSPy.configure { |c| c.lm = lm }
    end

    it 'collects timing metrics for each strategy', vcr: { cassette_name: 'benchmark_timing_metrics' } do
      strategies_to_test = ['enhanced_prompting', 'openai_structured_output']
      
      timing_results = []
      
      strategies_to_test.each do |strategy|
        start_time = Time.now
        
        JSONModesBenchmark.force_strategy(strategy)
        
        result = predictor.call(
          query: "Create a benchmark timing test todo",
          context: test_context,
          user_profile: test_user_profile
        )
        
        end_time = Time.now
        duration_ms = ((end_time - start_time) * 1000).round(2)
        
        timing_results << {
          strategy: strategy,
          duration_ms: duration_ms,
          success: !result.nil? && result.action.is_a?(T::Struct)
        }
      end
      
      # Verify we collected timing data for each strategy
      expect(timing_results.length).to eq(2)
      timing_results.each do |result|
        expect(result[:duration_ms]).to be > 0
        expect(result[:success]).to be true
        expect(strategies_to_test).to include(result[:strategy])
      end
      
      # Log results for analysis
      timing_results.each do |result|
        puts "#{result[:strategy]}: #{result[:duration_ms]}ms (success: #{result[:success]})"
      end
    end

    it 'collects token usage and cost metrics', vcr: { cassette_name: 'benchmark_token_usage' } do
      # Use single benchmark method to get detailed token usage
      result = JSONModesBenchmark.run_single_benchmark(
        'enhanced_prompting',
        'openai/gpt-4o-mini',
        predictor,
        "Create a token usage test todo",
        test_context,
        test_user_profile
      )
      
      # Verify benchmark result structure
      expect(result).to be_a(JSONModesBenchmark::BenchmarkResult)
      expect(result.strategy).to eq('enhanced_prompting')
      expect(result.model).to eq('openai/gpt-4o-mini')
      expect(result.success).to be true
      expect(result.duration_ms).to be > 0
      
      # Token usage may be nil in VCR mode, but structure should be correct
      expect(result.input_tokens).to be_a(Integer).or be_nil
      expect(result.output_tokens).to be_a(Integer).or be_nil
      expect(result.total_tokens).to be_a(Integer).or be_nil
      
      # Test derived metrics
      expect(result.tokens_per_second).to be >= 0.0
      expect(result.to_h).to be_a(Hash)
      expect(result.to_h[:strategy]).to eq('enhanced_prompting')
    end

    it 'measures type validation success rates' do
      # Test multiple predictions to measure validation success
      test_queries = [
        "Create a valid todo item",
        "Update an existing todo",
        "Delete a completed todo",
        "Assign a todo to someone"
      ]
      
      results = JSONModesBenchmark::BenchmarkResults.new
      
      test_queries.each_with_index do |query, index|
        vcr_cassette_name = "benchmark_validation_#{index}"
        
        VCR.use_cassette(vcr_cassette_name) do
          benchmark_result = JSONModesBenchmark.run_single_benchmark(
            'enhanced_prompting',
            'openai/gpt-4o-mini',
            predictor,
            query,
            test_context,
            test_user_profile
          )
          
          results.add_result(benchmark_result)
        end
      end
      
      results.mark_completed!
      
      # Analyze validation success rates
      expect(results.results.length).to eq(4)
      expect(results.success_rate).to be >= 0.0
      expect(results.success_rate).to be <= 100.0
      
      # Summary statistics
      summary = results.summary
      expect(summary[:total_tests]).to eq(4)
      expect(summary[:success_rate]).to be_a(Float)
      expect(summary[:total_duration_ms]).to be > 0
      expect(summary[:avg_duration_ms]).to be > 0
      
      # Log detailed results
      puts "\nValidation Success Rate Analysis:"
      puts "Total Tests: #{summary[:total_tests]}"
      puts "Success Rate: #{summary[:success_rate].round(1)}%"
      puts "Average Duration: #{summary[:avg_duration_ms].round(1)}ms"
      
      # Group by success/failure
      successful_results = results.results.select(&:success)
      failed_results = results.results.reject(&:success)
      
      puts "Successful: #{successful_results.length}"
      puts "Failed: #{failed_results.length}"
      
      if failed_results.any?
        puts "Failure reasons:"
        failed_results.each do |result|
          puts "  - #{result.error_message}"
        end
      end
    end

    it 'generates comprehensive benchmark report' do
      # Create a small benchmark results set for testing
      results = JSONModesBenchmark::BenchmarkResults.new
      
      # Add some mock results
      result1 = JSONModesBenchmark::BenchmarkResult.new(
        strategy: 'enhanced_prompting',
        model: 'openai/gpt-4o-mini',
        duration_ms: 1500.0,
        success: true,
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      )
      
      result2 = JSONModesBenchmark::BenchmarkResult.new(
        strategy: 'openai_structured_output', 
        model: 'openai/gpt-4o-mini',
        duration_ms: 1200.0,
        success: true,
        input_tokens: 120,
        output_tokens: 60,
        total_tokens: 180
      )
      
      results.add_result(result1)
      results.add_result(result2)
      results.mark_completed!
      
      # Generate report
      report = JSONModesBenchmark.format_benchmark_report(results)
      
      # Verify report structure
      expect(report).to include('# JSON Extraction Modes Benchmark Report')
      expect(report).to include('## Summary')
      expect(report).to include('**Total Tests**: 2')
      expect(report).to include('Success Rate: 100.0%')
      expect(report).to include('## Results by Strategy')
      expect(report).to include('Enhanced Prompting')
      expect(report).to include('Openai Structured Output')
      expect(report).to include('## Results by Model')
      expect(report).to include('openai/gpt-4o-mini')
      
      puts "\nGenerated Benchmark Report:"
      puts report
    end
  end

  describe 'Strategy forcing mechanism' do
    before do
      # Reset configuration before each test
      DSPy.configure { |c| c.structured_outputs.strategy = nil }
    end

    EXTRACTION_STRATEGIES.each do |strategy|
      context "when forcing #{strategy} strategy" do
        it "successfully applies #{strategy}" do
          expect { 
            JSONModesBenchmark.force_strategy(strategy)
          }.not_to raise_error
          
          # Verify the configuration was set correctly
          case strategy
          when 'enhanced_prompting'
            expect(DSPy.config.structured_outputs.strategy).to eq(DSPy::Strategy::Compatible)
          when 'openai_structured_output', 'anthropic_tool_use', 'anthropic_extraction', 'gemini_structured_output'
            expect(DSPy.config.structured_outputs.strategy).to eq(DSPy::Strategy::Strict)
          end
        end
      end
    end

    it 'raises error for unknown strategy' do
      expect {
        JSONModesBenchmark.force_strategy('unknown_strategy')
      }.to raise_error(ArgumentError, /Unknown strategy: unknown_strategy/)
    end

    it 'provides list of available strategies' do
      strategies = JSONModesBenchmark.available_strategies
      expect(strategies).to be_a(Array)
      expect(strategies).to include('enhanced_prompting')
      expect(strategies).to include('openai_structured_output')
      expect(strategies).to include('gemini_structured_output')
    end

    it 'generates strategy compatibility matrix' do
      matrix = JSONModesBenchmark.get_strategy_compatibility_matrix(TodoListManagementSignature)
      
      expect(matrix).to be_a(Hash)
      expect(matrix.keys).to include('openai', 'anthropic', 'gemini')
      
      # OpenAI should support enhanced_prompting and openai_structured_output
      expect(matrix['openai']).to include('enhanced_prompting')
      expect(matrix['openai']).to include('openai_structured_output')
      
      # Gemini should support enhanced_prompting and gemini_structured_output
      expect(matrix['gemini']).to include('enhanced_prompting')
      expect(matrix['gemini']).to include('gemini_structured_output')
      
      # Anthropic should support enhanced_prompting and anthropic strategies
      expect(matrix['anthropic']).to include('enhanced_prompting')
      expect(matrix['anthropic']).to include('anthropic_tool_use')
    end

    it 'checks strategy availability for specific models' do
      # OpenAI model should support OpenAI strategies
      expect(
        JSONModesBenchmark.strategy_available_for_model?('openai_structured_output', 'openai/gpt-4o', TodoListManagementSignature)
      ).to be true
      
      # OpenAI model should NOT support Gemini strategies
      expect(
        JSONModesBenchmark.strategy_available_for_model?('gemini_structured_output', 'openai/gpt-4o', TodoListManagementSignature)
      ).to be false
      
      # All models should support enhanced_prompting
      expect(
        JSONModesBenchmark.strategy_available_for_model?('enhanced_prompting', 'openai/gpt-4o', TodoListManagementSignature)
      ).to be true
      
      expect(
        JSONModesBenchmark.strategy_available_for_model?('enhanced_prompting', 'gemini/gemini-1.5-pro', TodoListManagementSignature)
      ).to be true
    end
  end

  describe 'Model compatibility matrix' do
    context 'OpenAI models' do
      OPENAI_MODELS.each do |model|
        it "tests #{model} with all compatible strategies" do
          skip "Will implement comprehensive model testing for #{model}"
        end
      end
    end

    context 'Anthropic models' do
      ANTHROPIC_MODELS.each do |model|
        it "tests #{model} with all compatible strategies" do
          skip "Will implement comprehensive model testing for #{model}"
        end
      end
    end

    context 'Google models' do
      GOOGLE_MODELS.each do |model|
        it "tests #{model} with all compatible strategies" do
          skip "Will implement comprehensive model testing for #{model}"
        end
      end
    end
  end
end