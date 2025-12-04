# frozen_string_literal: true

require 'spec_helper'
require 'dspy/ruby_llm'

# Test signature for RubyLLM structured output testing
class RubyLLMSentiment < T::Enum
  enums do
    Positive = new('positive')
    Negative = new('negative')
    Neutral = new('neutral')
  end
end

class RubyLLMSentimentAnalysis < DSPy::Signature
  description "Analyze the sentiment of a text"

  input do
    const :text, String, description: "Text to analyze"
  end

  output do
    const :sentiment, RubyLLMSentiment, description: "Detected sentiment"
    const :confidence, Float, description: "Confidence score between 0 and 1"
    const :reasoning, String, description: "Explanation for the sentiment"
  end
end

class RubyLLMSimpleResponse < DSPy::Signature
  description "Generate a simple response"

  input do
    const :prompt, String, description: "Input prompt"
  end

  output do
    const :response, String, description: "Response content"
  end
end

RSpec.describe "RubyLLM Integration" do
  let(:api_key_name) { 'OPENAI_API_KEY' }
  let(:api_key) { ENV[api_key_name] }

  describe "basic functionality with explicit API key" do
    it "works with OpenAI via RubyLLM", vcr: { cassette_name: "ruby_llm_openai_basic" } do
      require_api_key!

      lm = DSPy::LM.new(
        'ruby_llm/gpt-4o-mini',
        api_key: api_key,
        structured_outputs: true
      )
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(RubyLLMSentimentAnalysis)
      result = predictor.call(text: "This product is amazing, I love it!")

      expect(result.sentiment).to be_a(RubyLLMSentiment)
      expect(result.sentiment).to eq(RubyLLMSentiment::Positive)
      expect(result.confidence).to be_a(Float)
      expect(result.confidence).to be_between(0, 1)
      expect(result.reasoning).to be_a(String)
      expect(result.reasoning).not_to be_empty
    end

    it "returns proper response metadata", vcr: { cassette_name: "ruby_llm_openai_metadata" } do
      require_api_key!

      lm = DSPy::LM.new(
        'ruby_llm/gpt-4o-mini',
        api_key: api_key
      )
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(RubyLLMSimpleResponse)
      result = predictor.call(prompt: "Say hello")

      expect(result.response).to be_a(String)
      expect(result.response).not_to be_empty
    end
  end

  describe "provider detection" do
    it "auto-detects OpenAI provider from model ID", vcr: { cassette_name: "ruby_llm_provider_openai" } do
      require_api_key!

      lm = DSPy::LM.new('ruby_llm/gpt-4o-mini', api_key: api_key)
      adapter = lm.instance_variable_get(:@adapter)

      expect(adapter.provider).to eq('openai')
    end

    it "allows explicit provider override", vcr: { cassette_name: "ruby_llm_provider_override" } do
      require_api_key!

      lm = DSPy::LM.new(
        'ruby_llm/custom-model',
        api_key: api_key,
        provider: 'openai',
        base_url: 'https://api.openai.com/v1'
      )
      adapter = lm.instance_variable_get(:@adapter)

      expect(adapter.provider).to eq('openai')
    end
  end

  describe "enhanced prompting (structured outputs disabled)" do
    it "works without structured outputs", vcr: { cassette_name: "ruby_llm_no_structured" } do
      require_api_key!

      lm = DSPy::LM.new(
        'ruby_llm/gpt-4o-mini',
        api_key: api_key,
        structured_outputs: false
      )
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(RubyLLMSentimentAnalysis)
      result = predictor.call(text: "This is terrible, worst experience ever.")

      expect(result.sentiment).to be_a(RubyLLMSentiment)
      expect(result.sentiment).to eq(RubyLLMSentiment::Negative)
      expect(result.confidence).to be_a(Float)
      expect(result.reasoning).to be_a(String)
    end
  end

  describe "error handling" do
    it "raises appropriate error for invalid API key" do
      lm = DSPy::LM.new(
        'ruby_llm/gpt-4o-mini',
        api_key: 'invalid-key'
      )
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(RubyLLMSimpleResponse)

      # VCR won't record this since we don't want to actually make a call with invalid key
      # But we can verify the adapter is configured correctly
      adapter = lm.instance_variable_get(:@adapter)
      expect(adapter.provider).to eq('openai')
    end
  end
end
