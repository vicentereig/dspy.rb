# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Ollama Integration', :integration do
  let(:api_key) { 'ollama' }
  
  describe 'local Ollama instance' do
    let(:lm) { DSPy::LM.new('ollama/llama3.2', api_key: nil) }
    
    it 'executes basic completion', vcr: { cassette_name: 'ollama/basic_completion' } do
      response = lm.raw_chat([
        { role: 'user', content: 'What is 2+2? Reply with just the number.' }
      ])
      
      expect(response).to match(/4/)
    end
  end
  
  describe 'structured outputs with Ollama' do
    class WeatherInfo < DSPy::Signature
      input do
        const :location, String
      end
      output do
        const :temperature, Integer
        const :conditions, String
        const :humidity, Integer
      end
    end
    
    class SimpleAnswer < DSPy::Signature
      input do
        const :question, String
      end
      output do
        const :answer, String
        const :confidence, Float
      end
    end
    
    let(:lm) { DSPy::LM.new('ollama/llama3.2', api_key: nil, structured_outputs: true) }
    let(:predict) { DSPy::Predict.new(WeatherInfo) }
    let(:simple_predict) { DSPy::Predict.new(SimpleAnswer) }
    
    before do
      DSPy.config.lm = lm
    end
    
    it 'generates structured output for weather query', vcr: { cassette_name: 'ollama/structured_weather' } do
      result = predict.forward(location: "San Francisco")
      
      expect(result.class.superclass).to eq(T::Struct)
      expect(result.temperature).to be_a(Integer)
      expect(result.conditions).to be_a(String)
      expect(result.humidity).to be_a(Integer)
      expect(result.humidity).to be_between(0, 100)
    end
    
    it 'handles simple Q&A with confidence', vcr: { cassette_name: 'ollama/structured_qa' } do
      result = simple_predict.forward(question: "What is the capital of France?")
      
      expect(result.class.superclass).to eq(T::Struct)
      expect(result.answer).to match(/Paris/i)
      expect(result.confidence).to be_a(Float)
      expect(result.confidence).to be_between(0.0, 1.0)
    end
    
    it 'falls back gracefully when structured output fails', vcr: { cassette_name: 'ollama/structured_fallback' } do
      # Use a complex signature that might challenge structured outputs
      class ComplexAnalysis < DSPy::Signature
        input do
          const :text, String
        end
        output do
          const :sentiment, String
          const :key_phrases, T::Array[String]
          const :entities, T::Array[T::Hash[Symbol, String]]
        end
      end
      
      complex_predict = DSPy::Predict.new(ComplexAnalysis)
      DSPy.config.lm = lm
      
      result = complex_predict.forward(text: "Apple Inc. announced new products in Cupertino.")
      
      expect(result.class.superclass).to eq(T::Struct)
      expect(result.sentiment).to be_a(String)
      expect(result.key_phrases).to be_a(Array)
      expect(result.entities).to be_a(Array)
    end
  end
  
  describe 'remote Ollama with authentication' do
    let(:remote_lm) do
      DSPy::LM.new('ollama/llama3.2', 
        api_key: 'test-auth-key',
        base_url: 'https://ollama.example.com/v1'
      )
    end
    
    it 'configures remote endpoint correctly' do
      adapter = remote_lm.adapter
      expect(adapter).to be_a(DSPy::OpenAI::LM::Adapters::OllamaAdapter)
      expect(adapter.instance_variable_get(:@base_url)).to eq('https://ollama.example.com/v1')
      expect(adapter.instance_variable_get(:@api_key)).to eq('test-auth-key')
    end
  end
  
  describe 'Chain of Thought with Ollama' do
    class MathProblem < DSPy::Signature
      input do
        const :question, String
      end
      output do
        const :answer, Integer
      end
    end
    
    let(:lm) { DSPy::LM.new('ollama/llama3.2', api_key: nil) }
    let(:cot) { DSPy::ChainOfThought.new(MathProblem) }
    
    before do
      DSPy.config.lm = lm
    end
    
    it 'generates reasoning steps', vcr: { cassette_name: 'ollama/chain_of_thought' } do
      result = cot.forward(question: "If a train travels 60 mph for 2.5 hours, how many miles did it travel?")
      
      expect(result.class.superclass).to eq(T::Struct)
      expect(result.reasoning).to be_a(String)
      expect(result.reasoning).to include('60')
      expect(result.reasoning).to include('2.5')
      expect(result.answer).to eq(150)
    end
  end
end