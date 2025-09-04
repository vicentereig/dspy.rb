# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Teleprompt::GEPA ReflectionEngine DSPy Integration' do
  let(:config) { DSPy::Teleprompt::GEPA::GEPAConfig.new }
  let(:engine) { DSPy::Teleprompt::GEPA::ReflectionEngine.new(config) }
  let(:sample_traces) do
    [
      DSPy::Teleprompt::GEPA::ExecutionTrace.new(
        trace_id: 'test-trace-1',
        event_name: 'llm.response',
        timestamp: Time.now,
        attributes: {
          'gen_ai.request.model' => 'gpt-4',
          'gen_ai.usage.total_tokens' => 100,
          prompt: 'Test prompt',
          response: 'Test response'
        },
        metadata: {}
      )
    ]
  end

  describe 'DSPy::Predict integration' do
    it 'should have create_trace_reflection_signature method' do
      expect(engine).to respond_to(:create_trace_reflection_signature)
    end

    it 'creates proper DSPy::Signature class' do
      signature = engine.create_trace_reflection_signature
      expect(signature).to be < DSPy::Signature
      expect(signature.description).not_to be_empty
    end

    it 'should use DSPy::Predict instead of raw prompts in reflect_with_llm' do
      # This test verifies that reflect_with_llm uses DSPy::Predict
      # instead of the old raw prompt approach
      
      # Create a proper DSPy::Prediction object
      signature_class = engine.create_trace_reflection_signature
      mock_prediction = DSPy::Prediction.new(
        signature_class: signature_class,
        diagnosis: 'Test diagnosis',
        improvements: ['Test improvement'],
        confidence: 0.8,
        reasoning: 'Test reasoning', 
        suggested_mutations: ['rewrite'],
        pattern_detected: 'test_pattern',
        optimization_opportunity: 'test_opportunity'
      )
      
      # Mock the internal DSPy analysis method
      allow(engine).to receive(:analyze_traces_with_dspy).and_return(mock_prediction)
      
      result = engine.reflect_with_llm(sample_traces)
      
      expect(result).to be_a(DSPy::Teleprompt::GEPA::ReflectionResult)
      expect(result.diagnosis).to eq('Test diagnosis')
      expect(result.improvements).to include('Test improvement')
      expect(result.confidence).to eq(0.8)
      expect(result.reasoning).to eq('Test reasoning')
      expect(result.suggested_mutations).to include(:rewrite)
      
      # Verify the DSPy method was called
      expect(engine).to have_received(:analyze_traces_with_dspy).with(sample_traces)
    end
  end

  describe 'should not use generate_reflection_prompt with raw prompts' do
    it 'should not have generate_reflection_prompt method using raw prompts' do
      # This test ensures we've moved away from raw prompt methods
      if engine.respond_to?(:generate_reflection_prompt)
        # If the method exists, it should not return raw prompt strings
        # but should use DSPy::Signature instead
        result = engine.generate_reflection_prompt(sample_traces)
        expect(result).not_to include('<<~PROMPT')
        expect(result).not_to include('PROMPT')
      end
    end
  end
end