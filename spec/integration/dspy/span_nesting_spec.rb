# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Span Nesting in DSPy::Predict" do
  let(:signature_class) do
    Class.new(DSPy::Signature) do
      description "Test signature for span nesting"
      
      input do
        const :query, String
      end
      
      output do
        const :response, String
      end
    end
  end

  let(:captured_context_calls) { [] }
  let(:mock_lm) { instance_double(DSPy::LM) }
  
  before do
    # Enable observability
    allow(DSPy::Observability).to receive(:enabled?).and_return(true)
    allow(DSPy::Observability).to receive(:tracer).and_return(nil) # Disable actual OpenTelemetry
    
    # Capture DSPy::Context.with_span calls to verify context propagation
    original_with_span = DSPy::Context.method(:with_span)
    allow(DSPy::Context).to receive(:with_span).and_wrap_original do |method, operation:, **attributes, &block|
      context_info = {
        operation: operation,
        attributes: attributes,
        context_trace_id: DSPy::Context.current[:trace_id],
        context_stack_length: DSPy::Context.current[:span_stack].length,
        fiber_id: Fiber.current.object_id,
        timestamp: Time.now
      }
      captured_context_calls << context_info
      
      # Call the original method
      method.call(operation: operation, **attributes, &block)
    end
    
    # Mock the LM to simulate the real flow without API calls
    allow(mock_lm).to receive(:schema_format).and_return(:json)
    allow(mock_lm).to receive(:data_format).and_return(:json)
    allow(mock_lm).to receive(:chat) do |inference_module, input_values|
      # Simulate the LM.chat method creating its own span
      DSPy::Context.with_span(operation: 'llm.generate', 'langfuse.observation.type' => 'generation') do
        { response: "Mock LM response" }
      end
    end

    # Configure DSPy with mock LM
    DSPy.configure { |config| config.lm = mock_lm }
  end

  it "ensures llm.generate spans share the same trace context as DSPy::Predict.forward spans" do
    # Create predictor and make a call
    predictor = DSPy::Predict.new(signature_class)
    predictor.call(query: "test query")
    
    # Verify we captured both spans
    expect(captured_context_calls.length).to eq(2)
    
    # Find the spans
    predict_span = captured_context_calls.find { |s| s[:operation] == "DSPy::Predict.forward" }
    llm_span = captured_context_calls.find { |s| s[:operation] == "llm.generate" }
    
    expect(predict_span).not_to be_nil, "Should have DSPy::Predict.forward span"
    expect(llm_span).not_to be_nil, "Should have llm.generate span"
    
    # The critical test: both spans should share the same trace ID (proper nesting)
    expect(llm_span[:context_trace_id]).to eq(predict_span[:context_trace_id]), 
      "llm.generate should share the same trace ID as DSPy::Predict.forward for proper nesting"
    
    # llm.generate should have a higher stack length (nested deeper)
    expect(llm_span[:context_stack_length]).to be > predict_span[:context_stack_length],
      "llm.generate should be nested deeper in the span stack"
  end
  
  it "maintains proper span hierarchy with multiple nested operations" do
    # Test nested context scenario
    DSPy::Context.with_span(operation: 'outer.operation') do
      predictor = DSPy::Predict.new(signature_class)
      predictor.call(query: "nested test query")
    end
    
    # Should have: outer.operation -> DSPy::Predict.forward -> llm.generate
    expect(captured_context_calls.length).to eq(3)
    
    outer_span = captured_context_calls.find { |s| s[:operation] == "outer.operation" }
    predict_span = captured_context_calls.find { |s| s[:operation] == "DSPy::Predict.forward" }
    llm_span = captured_context_calls.find { |s| s[:operation] == "llm.generate" }
    
    expect(outer_span).not_to be_nil
    expect(predict_span).not_to be_nil  
    expect(llm_span).not_to be_nil
    
    # All spans should share the same trace ID
    expect(predict_span[:context_trace_id]).to eq(outer_span[:context_trace_id])
    expect(llm_span[:context_trace_id]).to eq(outer_span[:context_trace_id])
    
    # Stack depth should increase with nesting
    expect(predict_span[:context_stack_length]).to be > outer_span[:context_stack_length]
    expect(llm_span[:context_stack_length]).to be > predict_span[:context_stack_length]
  end
  
  context "ChainOfThought span nesting" do
    let(:chain_signature_class) do
      Class.new(DSPy::Signature) do
        description "Test signature for ChainOfThought span nesting"
        
        input do
          const :query, String
        end
        
        output do
          const :answer, String
        end
      end
    end
    
    it "should create only ONE span for ChainOfThought, not duplicate spans" do
      # Mock LM to return reasoning + answer
      allow(mock_lm).to receive(:chat) do |inference_module, input_values|
        DSPy::Context.with_span(operation: 'llm.generate', 'langfuse.observation.type' => 'generation') do
          { reasoning: "Step by step thinking", answer: "42" }
        end
      end
      
      chain_of_thought = DSPy::ChainOfThought.new(chain_signature_class)
      chain_of_thought.call(query: "What is the answer?")
      
      # Count span calls by operation
      chain_spans = captured_context_calls.select { |s| s[:operation] == "DSPy::ChainOfThought.forward" }
      predict_spans = captured_context_calls.select { |s| s[:operation] == "DSPy::Predict.forward" }
      llm_spans = captured_context_calls.select { |s| s[:operation] == "llm.generate" }
      
      # Should have 1 ChainOfThought span, 1 Predict span (via super), and 1 llm.generate span
      expect(chain_spans.length).to eq(1), "Should have exactly 1 ChainOfThought.forward span"
      expect(predict_spans.length).to eq(1), "Should have exactly 1 DSPy::Predict.forward span (via super)"
      expect(llm_spans.length).to eq(1), "Should have exactly 1 llm.generate span"
      
      # llm.generate should be nested under ChainOfThought
      chain_span = chain_spans.first
      llm_span = llm_spans.first
      
      expect(llm_span[:context_trace_id]).to eq(chain_span[:context_trace_id])
      expect(llm_span[:context_stack_length]).to be > chain_span[:context_stack_length]
    end
    
    it "ensures ChainOfThought spans are properly traced in Langfuse hierarchy" do
      allow(mock_lm).to receive(:chat) do |inference_module, input_values|
        DSPy::Context.with_span(operation: 'llm.generate', 'langfuse.observation.type' => 'generation') do
          { reasoning: "Logical steps", answer: "result" }
        end
      end
      
      # Test with an outer application span (like CoffeeShopAgent would create)
      DSPy::Context.with_span(operation: 'CoffeeShopAgent.handle_customer') do
        chain_of_thought = DSPy::ChainOfThought.new(chain_signature_class)
        chain_of_thought.call(query: "Test query")
      end
      
      # Should have proper hierarchy: CoffeeShopAgent -> ChainOfThought -> llm.generate
      app_spans = captured_context_calls.select { |s| s[:operation] == "CoffeeShopAgent.handle_customer" }
      chain_spans = captured_context_calls.select { |s| s[:operation] == "DSPy::ChainOfThought.forward" }
      llm_spans = captured_context_calls.select { |s| s[:operation] == "llm.generate" }
      
      expect(app_spans.length).to eq(1)
      expect(chain_spans.length).to eq(1)
      expect(llm_spans.length).to eq(1)
      
      app_span = app_spans.first
      chain_span = chain_spans.first
      llm_span = llm_spans.first
      
      # All should share same trace
      expect(chain_span[:context_trace_id]).to eq(app_span[:context_trace_id])
      expect(llm_span[:context_trace_id]).to eq(app_span[:context_trace_id])
      
      # Stack depth should increase properly
      expect(chain_span[:context_stack_length]).to be > app_span[:context_stack_length]
      expect(llm_span[:context_stack_length]).to be > chain_span[:context_stack_length]
    end
  end
end
