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
end