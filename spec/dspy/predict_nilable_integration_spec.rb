require 'spec_helper'

RSpec.describe 'DSPy::Predict with T.nilable fields integration' do
  # This tests the exact scenario described in the plan where MIPROv2 optimization
  # would fail due to nilable fields containing nil values during struct instantiation

  class NilableFieldsSignature < DSPy::Signature
    description "Test signature with nilable output fields"

    input do
      const :query, String
    end

    output do
      const :answer, String
      const :confidence, T.nilable(Float)
      const :explanation, T.nilable(String)
      const :metadata, T.nilable(T::Hash[String, T.untyped])
    end
  end

  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'] || 'stub-key')
      # Preserve the logger configuration from spec_helper
      c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
    end
  end

  let(:predict) { DSPy::Predict.new(NilableFieldsSignature) }

  describe 'struct instantiation with nilable fields' do
    it 'successfully creates prediction when nilable fields are nil', vcr: { cassette_name: 'predict_nilable_integration' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Mock the LLM to return parsed attributes with nil values for nilable fields
      allow_any_instance_of(DSPy::LM).to receive(:chat).and_return(
        {
          answer: 'This is the answer',
          confidence: nil,      # nilable field with nil value
          explanation: nil,     # nilable field with nil value  
          metadata: nil         # nilable field with nil value
        }
      )

      # This should not throw PredictionInvalidError or struct instantiation errors
      expect {
        result = predict.call(query: "What is 2+2?")
        
        # Verify the result structure
        expect(result.answer).to eq('This is the answer')
        expect(result.confidence).to be_nil
        expect(result.explanation).to be_nil
        expect(result.metadata).to be_nil
      }.not_to raise_error
    end

    it 'successfully creates prediction when nilable fields have values', vcr: { cassette_name: 'predict_nilable_with_values' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Mock the LLM to return parsed attributes with values for nilable fields
      allow_any_instance_of(DSPy::LM).to receive(:chat).and_return(
        {
          answer: 'This is the answer',
          confidence: 0.95,
          explanation: 'Simple arithmetic',
          metadata: { 'source' => 'calculator' }
        }
      )

      expect {
        result = predict.call(query: "What is 2+2?")
        
        # Verify the result structure
        expect(result.answer).to eq('This is the answer')
        expect(result.confidence).to eq(0.95)
        expect(result.explanation).to eq('Simple arithmetic')
        expect(result.metadata).to eq({ 'source' => 'calculator' })
      }.not_to raise_error
    end

    it 'handles mixed nilable field scenarios', vcr: { cassette_name: 'predict_nilable_mixed' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Mock the LLM to return parsed attributes with some nilable fields nil and some with values
      allow_any_instance_of(DSPy::LM).to receive(:chat).and_return(
        {
          answer: 'This is the answer',
          confidence: 0.8,          # has value
          explanation: nil,         # nil
          metadata: { 'key' => 'val' }  # has value
        }
      )

      expect {
        result = predict.call(query: "What is 2+2?")
        
        # Verify the result structure
        expect(result.answer).to eq('This is the answer')
        expect(result.confidence).to eq(0.8)
        expect(result.explanation).to be_nil
        expect(result.metadata).to eq({ 'key' => 'val' })
      }.not_to raise_error
    end
  end

  describe 'optimization scenario simulation' do
    # This simulates what happens during MIPROv2 optimization when it tries to
    # create predictions from LLM outputs that contain nil for nilable fields
    
    it 'handles the exact scenario that would cause optimization to fail' do
      # Simulate the attributes that would come from LLM output processing
      # This is exactly what would be passed to create_prediction_result during optimization
      input_values = { query: "What is the meaning of life?" }
      output_attributes = {
        answer: "42",
        confidence: nil,    # This used to cause PredictionInvalidError
        explanation: nil,   # This used to cause PredictionInvalidError
        metadata: nil       # This used to cause PredictionInvalidError
      }
      
      # This should not raise any errors
      expect {
        # Directly test the internal method that was failing
        prediction_result = predict.send(:create_prediction_result, input_values, output_attributes)
        
        expect(prediction_result.query).to eq("What is the meaning of life?")
        expect(prediction_result.answer).to eq("42")
        expect(prediction_result.confidence).to be_nil
        expect(prediction_result.explanation).to be_nil
        expect(prediction_result.metadata).to be_nil
      }.not_to raise_error(DSPy::PredictionInvalidError)
    end
  end
end