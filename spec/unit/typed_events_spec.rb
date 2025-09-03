# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Type-Safe Event Structures' do
  describe 'Base Event class' do
    it 'provides a base Event structure with common fields' do
      event = DSPy::Events::Event.new(
        name: 'test.event',
        timestamp: Time.now,
        attributes: { key: 'value' }
      )
      
      expect(event.name).to eq('test.event')
      expect(event.timestamp).to be_a(Time)
      expect(event.attributes).to eq({ key: 'value' })
    end
    
    it 'requires name to be present' do
      expect {
        DSPy::Events::Event.new(timestamp: Time.now)
      }.to raise_error(ArgumentError)
    end
    
    it 'automatically sets timestamp if not provided' do
      event = DSPy::Events::Event.new(name: 'test.event')
      expect(event.timestamp).to be_a(Time)
      expect(event.timestamp).to be_within(1).of(Time.now)
    end
  end
  
  describe 'LLMEvent' do
    it 'creates structured LLM events with semantic conventions' do
      event = DSPy::Events::LLMEvent.new(
        name: 'llm.generate',
        provider: 'openai',
        model: 'gpt-4',
        usage: DSPy::Events::TokenUsage.new(
          prompt_tokens: 100,
          completion_tokens: 50
        ),
        duration_ms: 1250
      )
      
      expect(event.name).to eq('llm.generate')
      expect(event.provider).to eq('openai')
      expect(event.model).to eq('gpt-4')
      expect(event.usage.prompt_tokens).to eq(100)
      expect(event.usage.completion_tokens).to eq(50)
      expect(event.usage.total_tokens).to eq(150)
      expect(event.duration_ms).to eq(1250)
    end
    
    it 'validates provider is a known LLM provider' do
      expect {
        DSPy::Events::LLMEvent.new(
          name: 'llm.generate',
          provider: 'unknown_provider',
          model: 'test-model'
        )
      }.to raise_error(ArgumentError, /Invalid provider/)
    end
    
    it 'converts to OpenTelemetry semantic convention attributes' do
      event = DSPy::Events::LLMEvent.new(
        name: 'llm.generate',
        provider: 'openai',
        model: 'gpt-4',
        usage: DSPy::Events::TokenUsage.new(
          prompt_tokens: 100,
          completion_tokens: 50
        )
      )
      
      otel_attrs = event.to_otel_attributes
      expect(otel_attrs).to include(
        'gen_ai.system' => 'openai',
        'gen_ai.request.model' => 'gpt-4',
        'gen_ai.usage.prompt_tokens' => 100,
        'gen_ai.usage.completion_tokens' => 50,
        'gen_ai.usage.total_tokens' => 150
      )
    end
  end
  
  describe 'ModuleEvent' do
    it 'creates structured module execution events' do
      event = DSPy::Events::ModuleEvent.new(
        name: 'module.forward',
        module_name: 'ChainOfThought',
        signature_name: 'QuestionAnswering',
        input_fields: ['question'],
        output_fields: ['answer'],
        duration_ms: 500
      )
      
      expect(event.name).to eq('module.forward')
      expect(event.module_name).to eq('ChainOfThought')
      expect(event.signature_name).to eq('QuestionAnswering')
      expect(event.input_fields).to eq(['question'])
      expect(event.output_fields).to eq(['answer'])
    end
  end
  
  describe 'OptimizationEvent' do
    it 'creates structured optimization events' do
      event = DSPy::Events::OptimizationEvent.new(
        name: 'optimization.trial_complete',
        optimizer_name: 'MIPROv2',
        trial_number: 5,
        score: 0.85,
        best_score: 0.92,
        parameters: { temperature: 0.7 }
      )
      
      expect(event.name).to eq('optimization.trial_complete')
      expect(event.optimizer_name).to eq('MIPROv2')
      expect(event.trial_number).to eq(5)
      expect(event.score).to eq(0.85)
      expect(event.best_score).to eq(0.92)
    end
  end
  
  describe 'DSPy.event with typed objects' do
    after do
      DSPy.events.clear_listeners
    end
    
    it 'accepts typed event objects and extracts attributes' do
      received_events = []
      
      DSPy.events.subscribe('llm.generate') do |event_name, attributes|
        received_events << [event_name, attributes]
      end
      
      event = DSPy::Events::LLMEvent.new(
        name: 'llm.generate',
        provider: 'anthropic',
        model: 'claude-3',
        duration_ms: 800
      )
      
      DSPy.event(event)
      
      expect(received_events.length).to eq(1)
      expect(received_events[0][0]).to eq('llm.generate')
      expect(received_events[0][1]).to include(
        provider: 'anthropic',
        model: 'claude-3',
        duration_ms: 800
      )
    end
    
    it 'creates OpenTelemetry spans with proper semantic conventions from typed events' do
      mock_span = double('span')
      
      allow(DSPy::Observability).to receive(:enabled?).and_return(true)
      expect(DSPy::Observability).to receive(:start_span).with(
        'llm.generate',
        hash_including(
          'gen_ai.system' => 'openai',
          'gen_ai.request.model' => 'gpt-4',
          'gen_ai.usage.prompt_tokens' => 100,
          'gen_ai.usage.completion_tokens' => 50
        )
      ).and_return(mock_span)
      expect(DSPy::Observability).to receive(:finish_span).with(mock_span)
      
      event = DSPy::Events::LLMEvent.new(
        name: 'llm.generate',
        provider: 'openai',
        model: 'gpt-4',
        usage: DSPy::Events::TokenUsage.new(
          prompt_tokens: 100,
          completion_tokens: 50
        )
      )
      
      DSPy.event(event)
    end
    
    it 'maintains backward compatibility with hash-based events' do
      received_events = []
      
      DSPy.events.subscribe('test.event') do |event_name, attributes|
        received_events << [event_name, attributes]
      end
      
      # Both should work
      DSPy.event('test.event', data: 'hash_style')
      
      event = DSPy::Events::Event.new(
        name: 'test.event',
        attributes: { data: 'typed_style' }
      )
      DSPy.event(event)
      
      expect(received_events.length).to eq(2)
      expect(received_events[0][1][:data]).to eq('hash_style')
      expect(received_events[1][1][:data]).to eq('typed_style')
    end
  end
  
  describe 'Type validation' do
    it 'provides helpful error messages for invalid types' do
      expect {
        DSPy::Events::LLMEvent.new(
          name: 'llm.generate',
          provider: 'openai',
          model: 123  # Should be string
        )
      }.to raise_error(TypeError)
    end
    
    it 'validates nested type structures' do
      expect {
        DSPy::Events::LLMEvent.new(
          name: 'llm.generate',
          provider: 'openai',
          model: 'gpt-4',
          usage: { prompt_tokens: 100 }  # Should be TokenUsage object
        )
      }.to raise_error(TypeError)
    end
  end
end