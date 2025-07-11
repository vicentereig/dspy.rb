# frozen_string_literal: true

require 'spec_helper'
require 'dspy'

RSpec.describe 'Default values integration' do
  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end
  end

  # Define a test signature with defaults
  class WeatherReport < DSPy::Signature
    description "Generate a weather report"
    
    input do
      const :location, String
      const :units, String, default: "celsius"
    end
    
    output do
      const :temperature, Float
      const :conditions, String
      const :humidity, Float, default: 50.0
      const :wind_speed, Float, default: 0.0
    end
  end

  describe 'with real LLM responses' do
    skip "Requires OpenAI API key" unless ENV['OPENAI_API_KEY']
    
    let(:predictor) { DSPy::Predict.new(WeatherReport) }
    
    it 'applies defaults when LLM omits optional output fields' do
      # The LLM might not always return humidity and wind_speed
      VCR.use_cassette('integration/default_values_weather') do
        result = predictor.call(location: "London")
        
        # Required fields should be present
        expect(result.temperature).to be_a(Float)
        expect(result.conditions).to be_a(String)
        
        # Optional fields should have defaults if not provided
        expect(result.humidity).to be_a(Float)
        expect(result.wind_speed).to be_a(Float)
        
        # Input defaults should also work
        expect(result.units).to eq("celsius")
      end
    end
  end
end