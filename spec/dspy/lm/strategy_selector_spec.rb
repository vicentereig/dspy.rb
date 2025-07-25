# frozen_string_literal: true

require 'spec_helper'
require 'dspy'
require 'dspy/signature'
require 'dspy/lm/strategy_selector'

class TestSignature < DSPy::Signature
  description "Test question answering signature"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

RSpec.describe DSPy::LM::StrategySelector do
  let(:signature_class) { TestSignature }
  
  describe '#select' do
    context 'with OpenAI adapter' do
      let(:openai_adapter) do
        adapter = DSPy::LM::OpenAIAdapter.new(model: "gpt-4o", api_key: "test-key", structured_outputs: true)
        allow(adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(true)
        adapter
      end
      
      before do
        allow(DSPy::LM::Adapters::OpenAI::SchemaConverter).to receive(:supports_structured_outputs?).and_return(true)
      end
      
      it 'selects OpenAI structured output strategy when available' do
        selector = described_class.new(openai_adapter, signature_class)
        strategy = selector.select
        
        expect(strategy).to be_a(DSPy::LM::Strategies::OpenAIStructuredOutputStrategy)
        expect(strategy.name).to eq('openai_structured_output')
      end
      
      context 'when structured outputs are disabled' do
        let(:openai_adapter) do
          adapter = DSPy::LM::OpenAIAdapter.new(model: "gpt-4o", api_key: "test-key", structured_outputs: false)
          allow(adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(false)
          adapter
        end
        
        it 'falls back to enhanced prompting strategy' do
          selector = described_class.new(openai_adapter, signature_class)
          strategy = selector.select
          
          expect(strategy).to be_a(DSPy::LM::Strategies::EnhancedPromptingStrategy)
          expect(strategy.name).to eq('enhanced_prompting')
        end
      end
    end
    
    context 'with Anthropic adapter' do
      let(:anthropic_adapter) do
        DSPy::LM::AnthropicAdapter.new(model: "claude-3", api_key: "test-key")
      end
      
      it 'selects Anthropic tool use strategy for Claude 3' do
        selector = described_class.new(anthropic_adapter, signature_class)
        strategy = selector.select
        
        expect(strategy).to be_a(DSPy::LM::Strategies::AnthropicToolUseStrategy)
        expect(strategy.name).to eq('anthropic_tool_use')
      end
    end
    
    context 'with unknown adapter' do
      # Create a minimal adapter that inherits from base Adapter
      class TestUnknownAdapter < DSPy::LM::Adapter
        def chat(messages:, signature: nil, &block)
          # Stub implementation
        end
      end
      
      let(:unknown_adapter) do
        TestUnknownAdapter.new(model: "unknown", api_key: "test-key")
      end
      
      it 'falls back to enhanced prompting strategy' do
        selector = described_class.new(unknown_adapter, signature_class)
        strategy = selector.select
        
        expect(strategy).to be_a(DSPy::LM::Strategies::EnhancedPromptingStrategy)
        expect(strategy.name).to eq('enhanced_prompting')
      end
    end
    
    context 'with manual strategy override' do
      let(:adapter) { DSPy::LM::OpenAIAdapter.new(model: "gpt-4o", api_key: "test-key") }
      
      context 'with Compatible strategy' do
        before do
          allow(DSPy.config.structured_outputs).to receive(:strategy).and_return(DSPy::Strategy::Compatible)
        end
        
        it 'uses enhanced prompting strategy' do
          selector = described_class.new(adapter, signature_class)
          strategy = selector.select
          
          expect(strategy).to be_a(DSPy::LM::Strategies::EnhancedPromptingStrategy)
        end
      end
      
      context 'with Strict strategy' do
        let(:openai_adapter) do
          adapter = DSPy::LM::OpenAIAdapter.new(model: "gpt-4o", api_key: "test-key", structured_outputs: true)
          allow(adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(true)
          adapter
        end
        
        before do
          allow(DSPy.config.structured_outputs).to receive(:strategy).and_return(DSPy::Strategy::Strict)
          allow(DSPy::LM::Adapters::OpenAI::SchemaConverter).to receive(:supports_structured_outputs?).and_return(true)
        end
        
        it 'uses provider-optimized strategy when available' do
          selector = described_class.new(openai_adapter, signature_class)
          strategy = selector.select
          
          expect(strategy).to be_a(DSPy::LM::Strategies::OpenAIStructuredOutputStrategy)
        end
        
        context 'when provider-optimized strategy not available' do
          before do
            allow(DSPy.logger).to receive(:warn)
          end
          
          it 'falls back to compatible strategy' do
            selector = described_class.new(adapter, signature_class)
            strategy = selector.select
            
            expect(strategy).to be_a(DSPy::LM::Strategies::EnhancedPromptingStrategy)
          end
        end
      end
    end
  end
  
  describe '#available_strategies' do
    let(:adapter) { DSPy::LM::OpenAIAdapter.new(model: "gpt-4o", api_key: "test-key") }
    let(:selector) { described_class.new(adapter, signature_class) }
    
    it 'returns all available strategies' do
      strategies = selector.available_strategies
      
      expect(strategies).to all(be_a(DSPy::LM::Strategies::BaseStrategy))
      expect(strategies.map(&:name)).to include('enhanced_prompting')
    end
  end
  
  describe '#strategy_available?' do
    let(:adapter) { DSPy::LM::OpenAIAdapter.new(model: "gpt-4o", api_key: "test-key") }
    let(:selector) { described_class.new(adapter, signature_class) }
    
    it 'returns true for available strategies' do
      expect(selector.strategy_available?('enhanced_prompting')).to be true
    end
    
    it 'returns false for unavailable strategies' do
      expect(selector.strategy_available?('nonexistent_strategy')).to be false
    end
  end
end