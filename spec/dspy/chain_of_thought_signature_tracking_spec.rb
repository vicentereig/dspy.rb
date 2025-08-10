# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ChainOfThought signature name tracking' do
  let(:test_signature) do
    Class.new(DSPy::Signature) do
      description "Test signature for tracking"
      
      def self.name
        "TestSignatureForTracking"
      end
      
      input do
        const :question, String
      end
      
      output do
        const :answer, String
      end
    end
  end

  it 'preserves original signature name in enhanced signature class' do
    cot = DSPy::ChainOfThought.new(test_signature)
    
    # The enhanced signature should preserve the original name
    expect(cot.instance_variable_get(:@signature_class).name).to eq("TestSignatureForTracking")
  end

  it 'stores original signature reference' do
    cot = DSPy::ChainOfThought.new(test_signature)
    
    # Should have a reference to the original signature
    expect(cot.original_signature).to eq(test_signature)
    expect(cot.original_signature.name).to eq("TestSignatureForTracking")
  end

  it 'uses original signature name in reasoning analysis events' do
    # Create a simple test to verify the logging uses the correct signature name
    cot = DSPy::ChainOfThought.new(test_signature)
    
    # Mock DSPy.log to capture the event
    logged_event = nil
    allow(DSPy).to receive(:log) do |event_name, **attrs|
      if event_name == 'chain_of_thought.reasoning_complete'
        logged_event = attrs
      end
    end
    
    # Call the private method directly to test logging
    cot.send(:emit_reasoning_analysis, "Step 1: Test. Step 2: More test.")
    
    # Verify the logged event uses the correct signature name
    expect(logged_event).not_to be_nil
    expect(logged_event['dspy.signature']).to eq('TestSignatureForTracking')
    expect(logged_event['cot.has_reasoning']).to eq(true)
    expect(logged_event['cot.reasoning_steps']).to be > 0
  end

  it 'handles signatures without explicit name correctly' do
    anonymous_signature = Class.new(DSPy::Signature) do
      description "Anonymous test signature"
      
      input do
        const :input, String
      end
      
      output do
        const :output, String
      end
    end
    
    cot = DSPy::ChainOfThought.new(anonymous_signature)
    
    # Anonymous classes don't have names, so the enhanced signature won't either
    # This is expected behavior - the name will be nil
    signature_name = cot.instance_variable_get(:@signature_class).name
    expect(signature_name).to be_nil
  end
end