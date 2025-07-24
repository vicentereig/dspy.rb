# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::LM#raw_chat integration', :vcr do
  let(:captured_events) { [] }

  before do
    # Capture all events for testing
    DSPy::Instrumentation.subscribe do |event|
      captured_events << event
    end
  end

  after do
    captured_events.clear
  end

  describe 'with OpenAI provider' do
    let(:openai_lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }

    it 'executes raw prompt and returns text response' do
      result = openai_lm.raw_chat([
        { role: 'system', content: 'You are a helpful assistant. Keep responses concise.' },
        { role: 'user', content: 'What is 2+2? Just give the number.' }
      ])

      expect(result).to be_a(String)
      expect(result).to include('4')
    end

    it 'supports DSL builder for messages' do
      result = openai_lm.raw_chat do |m|
        m.system 'You are a math tutor. Be very brief.'
        m.user 'What is the derivative of x^2? Just the answer.'
      end

      expect(result).to be_a(String)
      expect(result.downcase).to include('2x')
    end

    it 'emits correct instrumentation events' do
      openai_lm.raw_chat([{ role: 'user', content: 'Hello' }])

      # Check dspy.lm.request event
      request_events = captured_events.select { |e| e.id == 'dspy.lm.request' }
      expect(request_events.length).to eq(1)
      
      request_event = request_events.first
      expect(request_event.payload[:signature_class]).to eq('RawPrompt')
      expect(request_event.payload[:provider]).to eq('openai')
      expect(request_event.payload[:gen_ai_request_model]).to eq('gpt-4o-mini')

      # Check dspy.lm.tokens event
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      expect(token_events.length).to eq(1)
      
      token_event = token_events.first
      expect(token_event.payload[:signature_class]).to eq('RawPrompt')
      expect(token_event.payload[:input_tokens]).to be_a(Integer)
      expect(token_event.payload[:output_tokens]).to be_a(Integer)

      # Ensure NO dspy.lm.response.parsed event
      parsed_events = captured_events.select { |e| e.id == 'dspy.lm.response.parsed' }
      expect(parsed_events).to be_empty
    end
  end

  describe 'with Anthropic provider' do
    let(:anthropic_lm) { DSPy::LM.new('anthropic/claude-3-5-sonnet-20241022', api_key: ENV['ANTHROPIC_API_KEY']) }

    it 'executes raw prompt and returns text response' do
      result = anthropic_lm.raw_chat([
        { role: 'user', content: 'What is 3+3? Just give the number, nothing else.' }
      ])

      expect(result).to be_a(String)
      expect(result.strip).to match(/6/)
    end

    it 'supports conversation with multiple turns' do
      result = anthropic_lm.raw_chat do |m|
        m.user 'My name is Alice'
        m.assistant 'Nice to meet you, Alice!'
        m.user 'What is my name?'
      end

      expect(result).to be_a(String)
      expect(result).to include('Alice')
    end

    it 'emits correct instrumentation events' do
      anthropic_lm.raw_chat([{ role: 'user', content: 'Hi' }])

      # Check events
      request_events = captured_events.select { |e| e.id == 'dspy.lm.request' }
      expect(request_events.length).to eq(1)
      
      request_event = request_events.first
      expect(request_event.payload[:signature_class]).to eq('RawPrompt')
      expect(request_event.payload[:provider]).to eq('anthropic')
      expect(request_event.payload[:gen_ai_request_model]).to eq('claude-3-5-sonnet-20241022')

      # Token events
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      expect(token_events.length).to eq(1)
      
      # No parsed events for raw prompts
      parsed_events = captured_events.select { |e| e.id == 'dspy.lm.response.parsed' }
      expect(parsed_events).to be_empty
    end
  end

  describe 'benchmarking use case' do
    let(:openai_lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }
    
    # Example monolithic prompt from the issue
    let(:monolithic_prompt) do
      <<~PROMPT
        You are a changelog generator. Given a list of commits, generate a well-formatted changelog.
        
        Format:
        - Group commits by type (feat, fix, chore, etc.)
        - Use clear, user-friendly descriptions
        - Highlight breaking changes
      PROMPT
    end

    let(:commits_data) do
      <<~DATA
        feat: Add user authentication
        fix: Resolve memory leak in worker process
        chore: Update dependencies
      DATA
    end

    it 'allows benchmarking of monolithic prompts with instrumentation' do
      # Execute the monolithic prompt
      result = openai_lm.raw_chat do |m|
        m.system monolithic_prompt
        m.user commits_data
      end

      expect(result).to be_a(String)
      expect(result.downcase).to include('feat')
      
      # Verify we can access token usage for benchmarking
      token_events = captured_events.select { |e| e.id == 'dspy.lm.tokens' }
      expect(token_events).not_to be_empty
      
      last_token_event = token_events.last
      expect(last_token_event.payload[:input_tokens]).to be > 0
      expect(last_token_event.payload[:output_tokens]).to be > 0
      
      # This data can be compared against modular DSPy implementation
      puts "Monolithic prompt tokens: input=#{last_token_event.payload[:input_tokens]}, output=#{last_token_event.payload[:output_tokens]}"
    end
  end
end