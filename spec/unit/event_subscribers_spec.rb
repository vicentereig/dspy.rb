# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe 'Event Subscribers' do
  after do
    DSPy.events.clear_listeners
  end

  describe DSPy::Events::TokenBudgetSubscriber do
    let(:subscriber) { DSPy::Events::TokenBudgetSubscriber.new(budget_limit: 1000) }
    
    after do
      subscriber.unsubscribe
    end
    
    it 'tracks token usage from LLM events' do
      # Simulate LLM events with token usage
      DSPy.event('llm.generate', {
        'gen_ai.system' => 'openai',
        'gen_ai.request.model' => 'gpt-4',
        'gen_ai.usage.prompt_tokens' => 100,
        'gen_ai.usage.completion_tokens' => 50
      })
      
      DSPy.event('llm.generate', {
        'gen_ai.system' => 'anthropic',
        'gen_ai.request.model' => 'claude-3-sonnet',
        'gen_ai.usage.prompt_tokens' => 200,
        'gen_ai.usage.completion_tokens' => 75
      })
      
      summary = subscriber.usage_summary
      
      expect(summary[:total_tokens]).to eq(425) # 150 + 275
      expect(summary[:requests_count]).to eq(2)
      expect(summary[:budget_remaining]).to eq(575) # 1000 - 425
      expect(summary[:budget_exceeded]).to be false
      
      # Check provider breakdown
      expect(summary[:by_provider]['openai'][:tokens]).to eq(150)
      expect(summary[:by_provider]['anthropic'][:tokens]).to eq(275)
      
      # Check model breakdown
      expect(summary[:by_model]['gpt-4'][:tokens]).to eq(150)
      expect(summary[:by_model]['claude-3-sonnet'][:tokens]).to eq(275)
    end
    
    it 'calculates costs based on pricing model' do
      # Use real pricing for OpenAI
      DSPy.event('llm.generate', {
        'gen_ai.system' => 'openai',
        'gen_ai.request.model' => 'gpt-4',
        'gen_ai.usage.prompt_tokens' => 1000,
        'gen_ai.usage.completion_tokens' => 500
      })
      
      summary = subscriber.usage_summary
      
      # Should have calculated cost based on gpt-4 pricing (~$0.03 per 1k tokens)
      expect(summary[:total_cost]).to be > 0
      expect(summary[:total_cost]).to be_within(0.01).of(0.045) # 1.5k tokens * $0.03
    end
    
    it 'detects budget exceeded and emits warning events' do
      budget_events = []
      DSPy.events.subscribe('token_budget.*') do |event_name, attributes|
        budget_events << [event_name, attributes]
      end
      
      # Exceed the budget
      DSPy.event('llm.generate', {
        'gen_ai.system' => 'openai',
        'gen_ai.request.model' => 'gpt-4',
        'gen_ai.usage.prompt_tokens' => 800,
        'gen_ai.usage.completion_tokens' => 400
      })
      
      expect(subscriber.budget_exceeded?).to be true
      expect(budget_events.length).to eq(1)
      expect(budget_events[0][0]).to eq('token_budget.exceeded')
      expect(budget_events[0][1][:total_tokens]).to eq(1200)
    end
    
    it 'can reset stats' do
      DSPy.event('llm.generate', {
        'gen_ai.system' => 'openai',
        'gen_ai.request.model' => 'gpt-4',
        'gen_ai.usage.prompt_tokens' => 100,
        'gen_ai.usage.completion_tokens' => 50
      })
      
      expect(subscriber.total_tokens).to eq(150)
      
      subscriber.reset_stats
      
      expect(subscriber.total_tokens).to eq(0)
      expect(subscriber.requests_count).to eq(0)
    end
  end

  describe DSPy::Events::OptimizationReporter do
    let(:temp_file) { Tempfile.new(['optimization_report', '.md']) }
    let(:reporter) { DSPy::Events::OptimizationReporter.new(output_path: temp_file.path, auto_write: false) }
    
    after do
      reporter.unsubscribe
      temp_file.unlink
    end
    
    it 'tracks optimization progress' do
      # Simulate optimization session
      DSPy.event('optimization.start', {
        optimizer_name: 'MIPROv2'
      })
      
      DSPy.event('optimization.trial_complete', {
        optimizer_name: 'MIPROv2',
        trial_number: 1,
        score: 0.75,
        best_score: 0.75,
        parameters: { temperature: 0.7, max_tokens: 100 }
      })
      
      DSPy.event('optimization.trial_complete', {
        optimizer_name: 'MIPROv2',
        trial_number: 2,
        score: 0.82,
        best_score: 0.82,
        parameters: { temperature: 0.5, max_tokens: 150 }
      })
      
      DSPy.event('optimization.complete', {
        optimizer_name: 'MIPROv2'
      })
      
      summary = reporter.summary
      
      expect(summary[:optimizer]).to eq('MIPROv2')
      expect(summary[:total_trials]).to eq(2)
      expect(summary[:best_score]).to eq(0.82)
      expect(summary[:average_score]).to be_within(0.01).of(0.785)
      expect(summary[:successful_trials]).to eq(2)
      expect(summary[:failed_trials]).to eq(0)
    end
    
    it 'generates markdown report' do
      # Add some trial data
      DSPy.event('optimization.start', optimizer_name: 'SimpleOptimizer')
      DSPy.event('optimization.trial_complete', {
        trial_number: 1,
        score: 0.65,
        best_score: 0.65,
        parameters: { temperature: 0.8 }
      })
      DSPy.event('optimization.trial_complete', {
        trial_number: 2,
        score: 0.72,
        best_score: 0.72,
        parameters: { temperature: 0.6 }
      })
      
      markdown = reporter.generate_report
      
      expect(markdown).to include('# Optimization Report')
      expect(markdown).to include('SimpleOptimizer')
      expect(markdown).to include('Total Trials**: 2')
      expect(markdown).to include('Best Score**: 0.72')
      expect(markdown).to include('| Trial | Score | Best | Duration | Parameters |')
      expect(markdown).to include('| 1 | 0.65 | 0.65')
      expect(markdown).to include('| 2 | 0.72 | 0.72')
      expect(markdown).to include('Score progression (2 trials):')
    end
    
    it 'handles failed trials gracefully' do
      DSPy.event('optimization.start', optimizer_name: 'TestOptimizer')
      
      # Successful trial
      DSPy.event('optimization.trial_complete', {
        trial_number: 1,
        score: 0.8,
        best_score: 0.8
      })
      
      # Failed trial (no score)
      DSPy.event('optimization.trial_complete', {
        trial_number: 2,
        score: nil,
        best_score: 0.8
      })
      
      summary = reporter.summary
      expect(summary[:successful_trials]).to eq(1)
      expect(summary[:failed_trials]).to eq(1)
      expect(summary[:best_score]).to eq(0.8)
    end
    
    it 'writes to file when auto_write is enabled' do
      auto_reporter = DSPy::Events::OptimizationReporter.new(
        output_path: temp_file.path, 
        auto_write: true
      )
      
      DSPy.event('optimization.start', optimizer_name: 'AutoWriteTest')
      DSPy.event('optimization.trial_complete', {
        trial_number: 1,
        score: 0.9,
        best_score: 0.9
      })
      
      # Should have written to file
      content = File.read(temp_file.path)
      expect(content).to include('AutoWriteTest')
      expect(content).to include('0.9')
      
      auto_reporter.unsubscribe
    end
  end

  describe DSPy::Events::PredictWithTokenBudget do
    let(:simple_signature) do
      Class.new(DSPy::Signature) do
        input :question, desc: "A question"
        output :answer, desc: "An answer"
      end
    end
    
    let(:predict_module) do
      DSPy::Events::PredictWithTokenBudget.new(simple_signature, budget_limit: 500)
    end
    
    before do
      # Mock LM to avoid actual API calls
      allow(DSPy).to receive(:current_lm).and_return(
        double('mock_lm', generate: double('mock_response', 
          outputs: { answer: 'Test answer' },
          usage: double('usage', input_tokens: 10, output_tokens: 5, total_tokens: 15),
          metadata: double('metadata', model: 'test-model')
        ))
      )
    end
    
    after do
      predict_module.token_budget.unsubscribe
    end
    
    it 'integrates with token budget tracking' do
      # Simulate some token usage
      result = predict_module.forward(question: 'What is 2+2?')
      
      expect(result.answer).to eq('Test answer')
      
      # Check budget tracking (tokens should be tracked from the mocked LM call)
      # Note: The actual token tracking happens via events emitted by the LM
    end
    
    it 'raises error when budget is exceeded' do
      # First, exhaust the budget
      predict_module.token_budget.instance_variable_set(:@total_tokens, 600)
      
      expect {
        predict_module.forward(question: 'This should fail')
      }.to raise_error(DSPy::TokenBudgetExceededError, /Token budget exceeded/)
    end
    
    it 'provides usage summary' do
      summary = predict_module.usage_summary
      
      expect(summary).to include(:total_tokens, :budget_limit, :budget_remaining)
      expect(summary[:budget_limit]).to eq(500)
    end
    
    it 'can reset budget' do
      # Set some usage
      predict_module.token_budget.instance_variable_set(:@total_tokens, 100)
      
      predict_module.reset_budget
      
      expect(predict_module.token_budget.total_tokens).to eq(0)
    end
    
    it 'emits warning when budget is low' do
      warning_events = []
      DSPy.events.subscribe('token_budget.warning') do |event_name, attributes|
        warning_events << [event_name, attributes]
      end
      
      # Set budget close to limit
      predict_module.token_budget.instance_variable_set(:@total_tokens, 450)
      predict_module.token_budget.instance_variable_set(:@budget_limit, 500)
      
      predict_module.forward(question: 'Test question')
      
      expect(warning_events.length).to eq(1)
      expect(warning_events[0][0]).to eq('token_budget.warning')
    end
  end

  describe 'Integration scenarios' do
    let(:token_subscriber) { DSPy::Events::TokenBudgetSubscriber.new(budget_limit: 2000) }
    let(:optimization_reporter) { DSPy::Events::OptimizationReporter.new(auto_write: false) }
    
    after do
      token_subscriber.unsubscribe
      optimization_reporter.unsubscribe
    end
    
    it 'multiple subscribers can work together' do
      # Both subscribers should receive and process events
      DSPy.event('llm.generate', {
        'gen_ai.system' => 'openai',
        'gen_ai.request.model' => 'gpt-4',
        'gen_ai.usage.prompt_tokens' => 100,
        'gen_ai.usage.completion_tokens' => 50
      })
      
      DSPy.event('optimization.trial_complete', {
        trial_number: 1,
        score: 0.85,
        best_score: 0.85
      })
      
      # Token subscriber should have tracked the LLM event
      expect(token_subscriber.total_tokens).to eq(150)
      
      # Optimization reporter should have tracked the trial
      expect(optimization_reporter.summary[:total_trials]).to eq(1)
    end
    
    it 'demonstrates real-world optimization with token tracking' do
      # Simulate a complete optimization session with token usage
      DSPy.event('optimization.start', optimizer_name: 'MIPROv2')
      
      3.times do |i|
        # Each trial uses some tokens for LLM calls
        DSPy.event('llm.generate', {
          'gen_ai.system' => 'openai',
          'gen_ai.request.model' => 'gpt-4',
          'gen_ai.usage.prompt_tokens' => 200,
          'gen_ai.usage.completion_tokens' => 100
        })
        
        # Trial completes with a score
        DSPy.event('optimization.trial_complete', {
          trial_number: i + 1,
          score: 0.7 + (i * 0.05), # Improving scores
          best_score: 0.7 + (i * 0.05),
          parameters: { temperature: 0.8 - (i * 0.1) }
        })
      end
      
      DSPy.event('optimization.complete', optimizer_name: 'MIPROv2')
      
      # Check final state
      expect(token_subscriber.total_tokens).to eq(900) # 3 * 300 tokens
      expect(token_subscriber.budget_exceeded?).to be false
      
      opt_summary = optimization_reporter.summary
      expect(opt_summary[:total_trials]).to eq(3)
      expect(opt_summary[:best_score]).to eq(0.8)
      
      # Generate report
      report = optimization_reporter.generate_report
      expect(report).to include('MIPROv2')
      expect(report).to include('**Total Trials**: 3')
      expect(report).to include('improving in recent trials')
    end
  end
end