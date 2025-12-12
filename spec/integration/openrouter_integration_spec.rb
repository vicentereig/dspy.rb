# frozen_string_literal: true

require 'spec_helper'

# Test signature for OpenRouter structured output testing
class OpenRouterSentiment < T::Enum
  enums do
    Positive = new('positive')
    Negative = new('negative')
    Neutral = new('neutral')
  end
end

class OpenRouterSentimentAnalysis < DSPy::Signature
  description "Analyze the sentiment of a text using OpenRouter"

  input do
    const :text, String, description: "Text to analyze"
  end

  output do
    const :sentiment, OpenRouterSentiment, description: "Detected sentiment"
    const :confidence, Float, description: "Confidence score between 0 and 1"
    const :reasoning, String, description: "Explanation for the sentiment"
  end
end

class OpenRouterSimpleResponse < DSPy::Signature
  description "Generate a simple response"

  input do
    const :prompt, String, description: "Input prompt"
  end

  output do
    const :response, String, description: "Response content"
    const :word_count, Integer, description: "Number of words in response"
  end
end

RSpec.describe "OpenRouter Integration" do
  let(:api_key_name) { 'OPENROUTER_API_KEY' }
  let(:api_key) { ENV[api_key_name] }

  describe "basic functionality" do
    it "works with structured outputs explicitly disabled", vcr: { cassette_name: "openrouter_no_structured" } do
      require_api_key!

      # Explicitly disable structured outputs from the start
      lm = DSPy::LM.new(
        'openrouter/deepseek/deepseek-chat-v3.1:free',
        api_key: api_key,
        structured_outputs: false
      )
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(OpenRouterSentimentAnalysis)
      result = predictor.call(text: "This product is okay, nothing special.")

      # Should work with enhanced prompting
      expect(result.sentiment).to be_a(OpenRouterSentiment)
      expect(result.sentiment).to eq(OpenRouterSentiment::Neutral)
      expect(result.confidence).to be_a(Float)
      expect(result.reasoning).to be_a(String)
    end

    it "works with structured outputs natively supported (no fallback needed)", vcr: { cassette_name: "openrouter_structured_native" } do
      require_api_key!

      # Use a model that supports structured outputs natively
      # (structured_outputs defaults to true for OpenRouter)
      # Using google/gemini-2.5-flash as it's available and supports structured outputs
      lm = DSPy::LM.new(
        'openrouter/google/gemini-2.5-flash',
        api_key: api_key
      )
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(OpenRouterSentimentAnalysis)
      result = predictor.call(text: "This is an excellent product, highly recommended!")

      # Should work with native structured outputs
      expect(result.sentiment).to be_a(OpenRouterSentiment)
      expect(result.sentiment).to eq(OpenRouterSentiment::Positive)
      expect(result.confidence).to be_a(Float)
      expect(result.confidence).to be_between(0, 1)
      expect(result.reasoning).to be_a(String)
      expect(result.reasoning).not_to be_empty
    end
  end

  describe "OpenRouter-specific features" do
    it "includes custom headers when configured", vcr: { cassette_name: "openrouter_custom_headers" } do
      require_api_key!

      lm = DSPy::LM.new(
        'openrouter/google/gemini-2.5-flash',
        api_key: api_key,
        http_referrer: 'https://oss.vicente.services/dspy.rb/',
        x_title: 'DSPy.rb Integration Test'
      )
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(OpenRouterSimpleResponse)
      result = predictor.call(prompt: "Respond with 'Header test successful'")

      expect(result.response).to be_a(String)
      expect(result.response).to include("Header test successful")
      expect(result.word_count).to be_a(Integer)

      # Verify headers are properly set in the adapter
      adapter = lm.instance_variable_get(:@adapter)
      request_params = adapter.send(:default_request_params)
      expect(request_params).to have_key(:request_options)
      expect(request_params[:request_options]).to have_key(:extra_headers)
      expect(request_params[:request_options][:extra_headers]).to include(
        'X-Title' => 'DSPy.rb Integration Test',
        'HTTP-Referer' => 'https://oss.vicente.services/dspy.rb/'
      )
    end
  end
end
