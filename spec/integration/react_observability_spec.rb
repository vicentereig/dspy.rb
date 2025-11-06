# frozen_string_literal: true

require 'spec_helper'
require 'dspy/re_act'
require 'dspy/tools'

class TestReActSignature < DSPy::Signature
  description "Test signature for ReAct observability"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

RSpec.describe 'ReAct Observability Integration' do
  let(:add_tool) { SorbetAddNumbers.new }
  let(:tools) { [add_tool] }
  let(:react_agent) { DSPy::ReAct.new(TestReActSignature, tools: tools, max_iterations: 2) }
  
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end
  
  before(:each) do
    # Enable observability for logging but disable async processing
    allow(DSPy::Observability).to receive(:enabled?).and_return(true)
    allow(DSPy::Observability).to receive(:tracer).and_return(nil)
  end

  describe 'observation type emission' do
    it 'emits agent observation type for ReAct iterations' do
      logged_events = []
      
      # Mock the LM to return a finish action
      mock_lm = instance_double(DSPy::LM)
      allow(mock_lm).to receive(:schema_format).and_return(:json)
      allow(mock_lm).to receive(:data_format).and_return(:json)
      allow(DSPy).to receive(:current_lm).and_return(mock_lm)
      allow(mock_lm).to receive(:chat).and_return(
        { thought: 'I can answer directly', action: 'finish', action_input: '8' }
      )
      
      # Capture span.start events (following pattern from context_spec.rb)
      allow(DSPy).to receive(:log) do |event_name, **attributes|
        logged_events << { event: event_name, attributes: attributes } if event_name == 'span.start'
      end

      # Execute ReAct agent
      react_agent.forward(question: "What is 5 + 3?")
      
      # Find agent spans
      agent_spans = logged_events.select do |event|
        event[:attributes]['langfuse.observation.type'] == 'agent'
      end

      expect(agent_spans).not_to be_empty
      
      # Verify agent span has correct operation
      agent_iteration_spans = agent_spans.select do |event|
        event[:attributes][:operation] == 'react.iteration'
      end
      
      expect(agent_iteration_spans).not_to be_empty
      
      # Verify agent-specific attributes
      agent_span = agent_iteration_spans.first
      attributes = agent_span[:attributes]
      
      expect(attributes).to include('dspy.module' => 'ReAct')
      expect(attributes).to include('react.iteration')
      expect(attributes).to include('react.max_iterations')
    end
    
    it 'emits tool observation type for tool calls' do
      logged_events = []
      captured_tracer_attributes = nil
      tracer_span = instance_double('TracerSpan', set_attribute: nil)
      tracer = double('Tracer')
      allow(DSPy::Observability).to receive(:tracer).and_return(tracer)
      allow(tracer).to receive(:in_span) do |operation, attributes:, kind:, &block|
        captured_tracer_attributes = attributes if attributes['tool.input'] || attributes[:'tool.input']
        block&.call(tracer_span)
      end
      
      # Mock the LM with call tracking
      mock_lm = instance_double(DSPy::LM)
      allow(mock_lm).to receive(:schema_format).and_return(:json)
      allow(mock_lm).to receive(:data_format).and_return(:json)
      allow(DSPy).to receive(:current_lm).and_return(mock_lm)
      
      call_count = 0
      allow(mock_lm).to receive(:chat) do |inference_module, input_values|
        call_count += 1
        case call_count
        when 1
          { thought: 'I need to use the add tool', action: 'add_numbers', action_input: { "x" => 5, "y" => 3 } }
        when 2
          { interpretation: 'The tool returned 8', next_step: 'finish' }
        else
          { thought: 'I have the answer', action: 'finish', action_input: '8' }
        end
      end
      
      # Capture span.start events (following pattern from context_spec.rb)
      allow(DSPy).to receive(:log) do |event_name, **attributes|
        logged_events << { event: event_name, attributes: attributes } if event_name == 'span.start'
      end

      # Execute ReAct agent
      react_agent.forward(question: "What is 5 + 3?")
      
      # Find tool spans
      tool_spans = logged_events.select do |event|
        event[:attributes]['langfuse.observation.type'] == 'tool'
      end

      expect(tool_spans).not_to be_empty
      
      # Verify tool span has correct operation and attributes
      tool_call_spans = tool_spans.select do |event|
        event[:attributes][:operation] == 'react.tool_call'
      end
      
      expect(tool_call_spans).not_to be_empty
      
      tool_span = tool_call_spans.first
      attributes = tool_span[:attributes]
      
      expect(attributes).to include('dspy.module' => 'ReAct')
      expect(attributes).to include('tool.name' => 'add_numbers')
      expect(attributes['tool.input']).to be_a(String)
      expect(attributes).to include('react.iteration')
      expect(captured_tracer_attributes['tool.input']).to be_a(String)
    end
  end
end
