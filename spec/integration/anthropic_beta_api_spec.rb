# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Anthropic Beta API Structured Outputs', :vcr do
  before(:all) do
    skip "ANTHROPIC_API_KEY not set" unless ENV['ANTHROPIC_API_KEY']
  end

  it 'uses Beta API structured outputs with Claude 4.5 Sonnet', vcr: { cassette_name: 'anthropic/beta_api_structured_outputs' } do
    # Define a simple signature
    signature = Class.new(DSPy::Signature) do
      description "Answer a question with reasoning"

      input do
        const :question, String, description: "The question to answer"
      end

      output do
        const :answer, String, description: "The answer"
        const :confidence, Float, description: "Confidence score between 0 and 1"
      end
    end

    # Create LM with Beta API structured outputs explicitly enabled
    # Using claude-sonnet-4-5-20250929 which supports structured outputs
    lm = DSPy::LM.new('anthropic/claude-sonnet-4-5-20250929', api_key: ENV['ANTHROPIC_API_KEY'], structured_outputs: true)

    # Configure with the LM
    DSPy.configure { |config| config.lm = lm }

    predictor = DSPy::Predict.new(signature)

    # Make prediction
    result = predictor.call(question: "What is 2+2?")

    # Verify structured output
    expect(result).to respond_to(:answer)
    expect(result).to respond_to(:confidence)
    expect(result.answer).to be_a(String)
    expect(result.answer).not_to be_empty
    expect(result.confidence).to be_a(Float)
    expect(result.confidence).to be >= 0.0
    expect(result.confidence).to be <= 1.0
  end
end
