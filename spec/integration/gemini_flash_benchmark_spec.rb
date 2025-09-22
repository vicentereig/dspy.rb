# frozen_string_literal: true

require 'spec_helper'

# Benchmark test signature
class BenchmarkTestSignature < DSPy::Signature
  description "Benchmark comparison signature"
  
  input do
    const :text, String, description: "Text to analyze"
  end
  
  output do
    const :analysis, String, description: "Analysis result"
    const :sentiment, String, description: "Sentiment classification"
    const :confidence, Float, description: "Confidence score"
    const :keywords, T::Array[String], description: "Key terms extracted"
  end
end

RSpec.describe "Gemini Flash Models Benchmark Comparison" do
  let(:test_text) { "This is an excellent product that I highly recommend to everyone. The quality is outstanding and the price is very reasonable. I'm extremely satisfied with my purchase." }
  
  describe "strategy performance comparison" do
    it "compares enhanced_prompting vs gemini_structured_output for Flash models", vcr: { cassette_name: "flash_strategy_comparison" } do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      results = {}
      
      SSEVCR.use_cassette('flash_strategy_comparison') do
        # Test enhanced prompting strategy
        DSPy.configure do |config|
          config.lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: false)
          config.structured_outputs.strategy = DSPy::Strategy::Compatible
        end
        
        predictor_enhanced = DSPy::Predict.new(BenchmarkTestSignature)
        
        start_time = Time.now
        result_enhanced = predictor_enhanced.call(text: test_text)
        enhanced_duration = Time.now - start_time
        
        results[:enhanced] = {
          result: result_enhanced,
          duration: enhanced_duration,
          strategy: 'enhanced_prompting'
        }
        
        # Test structured output strategy
        DSPy.configure do |config|
          config.lm = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
          config.structured_outputs.strategy = DSPy::Strategy::Strict
        end
        
        predictor_structured = DSPy::Predict.new(BenchmarkTestSignature)
        
        start_time = Time.now
        result_structured = predictor_structured.call(text: test_text)
        structured_duration = Time.now - start_time
        
        results[:structured] = {
          result: result_structured,
          duration: structured_duration,
          strategy: 'gemini_structured_output'
        }
      end
      
      # Verify both strategies work
      expect(results[:enhanced][:result]).to be_a(T::Struct)
      expect(results[:structured][:result]).to be_a(T::Struct)
      
      # Both should have valid results
      [:enhanced, :structured].each do |strategy_key|
        result = results[strategy_key][:result]
        expect(result.analysis).to be_a(String)
        expect(result.analysis).not_to be_empty
        expect(result.sentiment).to be_a(String)
        expect(result.confidence).to be_a(Float)
        expect(result.confidence).to be_between(0, 1)
        expect(result.keywords).to be_a(Array)
        result.keywords.each { |keyword| expect(keyword).to be_a(String) }
      end
      
      # Performance comparison (informational)
      enhanced_time = results[:enhanced][:duration]
      structured_time = results[:structured][:duration]
      
      puts "\n--- Performance Comparison ---"
      puts "Enhanced Prompting: #{(enhanced_time * 1000).round(2)}ms"
      puts "Structured Output:  #{(structured_time * 1000).round(2)}ms"
      puts "Ratio: #{(enhanced_time / structured_time).round(2)}x"
      
      # Both should complete in reasonable time (< 30 seconds)
      expect(enhanced_time).to be < 30
      expect(structured_time).to be < 30
    end
  end
  
  describe "consistency comparison across Flash models" do
    FLASH_MODELS_SAMPLE = ['gemini-1.5-flash', 'gemini-2.0-flash-001'].freeze
    
    FLASH_MODELS_SAMPLE.each do |model|
      it "maintains consistency for #{model} with structured outputs", vcr: { cassette_name: "consistency_#{model.gsub(/[.-]/, '_')}" } do
        skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
        
        SSEVCR.use_cassette("consistency_#{model.gsub(/[.-]/, '_')}") do
          lm = DSPy::LM.new("gemini/#{model}", api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
          DSPy.configure { |config| config.lm = lm }
          
          predictor = DSPy::Predict.new(BenchmarkTestSignature)
          result = predictor.call(text: test_text)
          
          # Verify structured output format
          expect(result.analysis).to be_a(String)
          expect(result.sentiment).to be_a(String)
          expect(result.confidence).to be_a(Float)
          expect(result.keywords).to be_a(Array)
          
          # Sentiment should be reasonable for positive text
          expect(result.sentiment.downcase).to match(/positive|good|excellent|favorable/)
          
          # Confidence should be reasonably high for clear sentiment
          expect(result.confidence).to be > 0.5
          
          # Should extract relevant keywords
          expect(result.keywords).not_to be_empty
          expect(result.keywords.length).to be_between(1, 10)
        end
      end
    end
  end
  
  describe "token usage analysis" do
    it "compares token efficiency between strategies", vcr: { cassette_name: "token_usage_comparison" } do
      skip 'Requires GEMINI_API_KEY' unless ENV['GEMINI_API_KEY']
      
      SSEVCR.use_cassette('token_usage_comparison') do
        # Test with enhanced prompting
        lm_enhanced = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: false)
        adapter_enhanced = lm_enhanced.instance_variable_get(:@adapter)
        
        response_enhanced = adapter_enhanced.chat(
          messages: [{ role: 'user', content: "Analyze sentiment: #{test_text}" }]
        )
        
        # Test with structured outputs
        lm_structured = DSPy::LM.new('gemini/gemini-1.5-flash', api_key: ENV['GEMINI_API_KEY'], structured_outputs: true)
        adapter_structured = lm_structured.instance_variable_get(:@adapter)
        
        response_structured = adapter_structured.chat(
          messages: [{ role: 'user', content: "Analyze sentiment: #{test_text}" }]
        )
        
        # Both should have usage data
        expect(response_enhanced.usage).to be_a(DSPy::LM::Usage)
        expect(response_structured.usage).to be_a(DSPy::LM::Usage)
        
        # Compare token usage
        enhanced_tokens = response_enhanced.usage.total_tokens
        structured_tokens = response_structured.usage.total_tokens
        
        puts "\n--- Token Usage Comparison ---"
        puts "Enhanced Prompting: #{enhanced_tokens} tokens"
        puts "Structured Output:  #{structured_tokens} tokens"
        puts "Difference: #{structured_tokens - enhanced_tokens} tokens"
        
        # Both should use reasonable amounts of tokens
        expect(enhanced_tokens).to be > 0
        expect(structured_tokens).to be > 0
        expect(enhanced_tokens).to be < 5000  # Reasonable upper bound
        expect(structured_tokens).to be < 5000  # Reasonable upper bound
      end
    end
  end
end