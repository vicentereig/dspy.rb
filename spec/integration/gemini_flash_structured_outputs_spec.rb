# frozen_string_literal: true

require 'spec_helper'

# Test signature for Flash model testing
class FlashTestSentiment < T::Enum
  enums do
    Positive = new('positive')
    Negative = new('negative')
    Neutral = new('neutral')
  end
end

class FlashTestSignature < DSPy::Signature
  description "Simple test signature for Flash model validation"
  
  input do
    const :text, String, description: "Text to analyze"
  end
  
  output do
    const :sentiment, FlashTestSentiment, description: "Detected sentiment"
    const :confidence, Float, description: "Confidence score"
    const :summary, String, description: "Brief summary"
  end
end

RSpec.describe "Gemini Flash Models Structured Outputs Integration" do
  # Test all Flash model variants to ensure they use structured outputs
  FLASH_MODELS = [
    'gemini-1.5-flash',
    'gemini-1.5-flash-8b',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001'
  ].freeze
  
  FLASH_MODELS.each do |model|
    describe "#{model} with structured outputs" do
      it "uses gemini_structured_output strategy" do
        skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
        
        lm = DSPy::LM.new("gemini/#{model}", api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        selector = DSPy::LM::StrategySelector.new(lm.adapter, FlashTestSignature)
        
        selected = selector.select
        expect(selected.name).to eq('gemini_structured_output')
        expect(selected).to be_available
      end
      
      it "generates valid structured output", vcr: { cassette_name: "flash_structured_#{model.gsub(/[.-]/, '_')}" } do
        skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
        
        lm = DSPy::LM.new("gemini/#{model}", api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        DSPy.configure { |config| config.lm = lm }
        
        predictor = DSPy::Predict.new(FlashTestSignature)
        result = predictor.call(text: "This is an amazing product that exceeds expectations!")
        
        # Verify structured output format
        expect(result.sentiment).to be_a(FlashTestSentiment)
        expect(result.sentiment).to eq(FlashTestSentiment::Positive)
        expect(result.confidence).to be_a(Float)
        expect(result.confidence).to be_between(0, 1)
        expect(result.summary).to be_a(String)
        expect(result.summary).not_to be_empty
      end
    end
  end
  
  describe "strategy comparison between models" do
    it "all Flash models use the same strategy" do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      strategies = FLASH_MODELS.map do |model|
        lm = DSPy::LM.new("gemini/#{model}", api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        selector = DSPy::LM::StrategySelector.new(lm.adapter, FlashTestSignature)
        selector.select.name
      end
      
      # All Flash models should use structured outputs
      expect(strategies.uniq).to eq(['gemini_structured_output'])
    end
  end
  
  describe "performance characteristics" do
    it "provides usage metrics for Flash models", vcr: { cassette_name: "flash_usage_metrics" } do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      # Test with fastest Flash model
      lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
      
      adapter = lm.instance_variable_get(:@adapter)
      response = adapter.chat(
        messages: [{ role: 'user', content: 'Analyze sentiment: "Great product!"' }]
      )
      
      expect(response.usage).to be_a(DSPy::LM::Usage)
      expect(response.usage.input_tokens).to be > 0
      expect(response.usage.output_tokens).to be > 0
      expect(response.usage.total_tokens).to eq(response.usage.input_tokens + response.usage.output_tokens)
    end
  end
end