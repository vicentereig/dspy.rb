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

class SimpleResponse < DSPy::Signature
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
  describe "basic functionality" do
    it "works with basic chat completion (auto-fallback from structured outputs)", vcr: { cassette_name: "openrouter_basic_chat" } do
      skip 'Requires OPENROUTER_API_KEY' unless ENV['OPENROUTER_API_KEY']

      # Use deepseek without explicitly setting structured_outputs - should auto-fallback
      lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free',
                        api_key: ENV['OPENROUTER_API_KEY'])
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(SimpleResponse)
      result = predictor.call(prompt: "Say hello in exactly three words")

      expect(result.response).to be_a(String)
      expect(result.response).not_to be_empty
      expect(result.word_count).to be_a(Integer)
      expect(result.word_count).to be > 0
    end
  end

  describe "structured outputs with fallback" do
    it "attempts structured outputs first, falls back on failure (default behavior)", vcr: { cassette_name: "openrouter_structured_fallback" } do
      skip 'Requires OPENROUTER_API_KEY' unless ENV['OPENROUTER_API_KEY']

      # Use a model that doesn't support structured outputs - should fallback automatically
      # (structured_outputs defaults to true for OpenRouter)
      lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free',
                        api_key: ENV['OPENROUTER_API_KEY'])
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(OpenRouterSentimentAnalysis)
      result = predictor.call(text: "I absolutely love this product! It's amazing.")

      # Should work regardless of whether structured outputs succeeded or fell back
      expect(result.sentiment).to be_a(OpenRouterSentiment)
      expect(result.confidence).to be_a(Float)
      expect(result.confidence).to be_between(0, 1)
      expect(result.reasoning).to be_a(String)
      expect(result.reasoning).not_to be_empty
    end

    it "works with structured outputs explicitly disabled", vcr: { cassette_name: "openrouter_no_structured" } do
      skip 'Requires OPENROUTER_API_KEY' unless ENV['OPENROUTER_API_KEY']

      # Explicitly disable structured outputs from the start
      lm = DSPy::LM.new('openrouter/deepseek/deepseek-chat-v3.1:free',
                        api_key: ENV['OPENROUTER_API_KEY'],
                        structured_outputs: false)
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(OpenRouterSentimentAnalysis)
      result = predictor.call(text: "This product is okay, nothing special.")

      # Should work with enhanced prompting
      expect(result.sentiment).to be_a(OpenRouterSentiment)
      expect([OpenRouterSentiment::Positive, OpenRouterSentiment::Negative, OpenRouterSentiment::Neutral]).to include(result.sentiment)
      expect(result.confidence).to be_a(Float)
      expect(result.reasoning).to be_a(String)
    end

    it "works with structured outputs natively supported (no fallback needed)", vcr: { cassette_name: "openrouter_structured_native" } do
      skip 'Requires OPENROUTER_API_KEY' unless ENV['OPENROUTER_API_KEY']

      # Use Grok which supports structured outputs natively
      # (structured_outputs defaults to true for OpenRouter)
      lm = DSPy::LM.new('openrouter/x-ai/grok-4-fast:free',
                        api_key: ENV['OPENROUTER_API_KEY'])
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(OpenRouterSentimentAnalysis)
      result = predictor.call(text: "This is an excellent product, highly recommended!")

      # Should work with native structured outputs
      expect(result.sentiment).to be_a(OpenRouterSentiment)
      expect(result.confidence).to be_a(Float)
      expect(result.confidence).to be_between(0, 1)
      expect(result.reasoning).to be_a(String)
      expect(result.reasoning).not_to be_empty
    end
  end

  describe "OpenRouter-specific features" do
    it "includes custom headers when configured", vcr: { cassette_name: "openrouter_custom_headers" } do
      skip 'Requires OPENROUTER_API_KEY' unless ENV['OPENROUTER_API_KEY']

      lm = DSPy::LM.new('openrouter/x-ai/grok-4-fast:free',
                        api_key: ENV['OPENROUTER_API_KEY'],
                        http_referrer: 'https://vicentereig.github.io/dspy.rb/',
                        x_title: 'DSPy.rb Integration Test')
      DSPy.configure { |config| config.lm = lm }

      predictor = DSPy::Predict.new(SimpleResponse)
      result = predictor.call(prompt: "Respond with 'Header test successful'")

      expect(result.response).to be_a(String)
      expect(result.word_count).to be_a(Integer)

      # Verify headers are properly set in the adapter
      adapter = lm.instance_variable_get(:@adapter)
      request_params = adapter.send(:default_request_params)
      expect(request_params).to have_key(:request_options)
      expect(request_params[:request_options]).to have_key(:extra_headers)
      expect(request_params[:request_options][:extra_headers]).to include(
        'X-Title' => 'DSPy.rb Integration Test',
        'HTTP-Referer' => 'https://vicentereig.github.io/dspy.rb/'
      )
    end
  end

  describe "model compatibility" do
    context "with different OpenRouter models" do
      let(:test_models) do
        [
          'openrouter/deepseek/deepseek-chat-v3.1:free',
          'openrouter/x-ai/grok-4-fast:free'
        ]
      end

      it "works with various free OpenRouter models", vcr: { cassette_name: "openrouter_model_compatibility" } do
        skip 'Requires OPENROUTER_API_KEY' unless ENV['OPENROUTER_API_KEY']

        # Test with just one model to avoid too many API calls in tests
        model = test_models.first
        lm = DSPy::LM.new(model, api_key: ENV['OPENROUTER_API_KEY'])
        DSPy.configure { |config| config.lm = lm }

        predictor = DSPy::Predict.new(SimpleResponse)
        result = predictor.call(prompt: "Test model compatibility")

        expect(result.response).to be_a(String)
        expect(result.response).not_to be_empty
        expect(result.word_count).to be_a(Integer)
      end
    end
  end
end
