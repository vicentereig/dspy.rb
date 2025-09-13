# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/benchmark_types'
require_relative '../../examples/json_modes_benchmark'

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
        lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: api_key, structured_outputs: true)
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
    it 'correctly deserializes different action types based on _type field' do
      # Test will verify that T.any() union types work with automatic _type discrimination
      skip 'Will implement after signature is created'
    end

    it 'handles arrays of union types' do
      # Test will verify related_actions array containing mixed action types
      skip 'Will implement after signature is created'
    end

    it 'falls back gracefully when _type field is missing' do
      # Test structural matching fallback behavior
      skip 'Will implement after signature is created'
    end
  end

  describe 'Benchmark data collection' do
    it 'collects timing metrics for each strategy' do
      skip 'Will implement with benchmark script'
    end

    it 'collects token usage and cost metrics' do
      skip 'Will implement with observability integration'
    end

    it 'measures type validation success rates' do
      skip 'Will implement with complex type validation checks'
    end
  end

  describe 'Strategy forcing mechanism' do
    EXTRACTION_STRATEGIES.each do |strategy|
      context "when forcing #{strategy} strategy" do
        it "successfully applies #{strategy}" do
          expect { 
            JSONModesBenchmark.force_strategy(strategy)
          }.not_to raise_error
          
          # Verify strategy is actually applied
          # Implementation will depend on our benchmark class
        end
      end
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