# frozen_string_literal: true

require 'spec_helper'
require 'dspy'
require 'dspy/signature'
require 'dspy/module'
require 'dspy/predict'

class StrategyTestSignature < DSPy::Signature
  description "Test signature for strategy selection"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
    const :confidence, Float
  end
end

class StrategyTestModule < DSPy::Module
  def initialize(signature_class = StrategyTestSignature)
    super()
    @predict = DSPy::Predict.new(signature_class)
  end
  
  def forward(question)
    @predict.call(question: question)
  end
end

RSpec.describe "Strategy Selection Integration" do
  let(:api_key) { ENV['OPENAI_API_KEY'] || 'test-key' }
  let(:module_instance) { StrategyTestModule.new }
  
  describe "with OpenAI structured outputs" do
    context "when enabled" do
      let(:lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: api_key, structured_outputs: true) }
      
      before do
        # Set both global and instance LM to ensure it's available
        DSPy.configure { |c| c.lm = lm }
        module_instance.configure { |config| config.lm = lm }
        allow(DSPy.logger).to receive(:debug).and_call_original
      end
      
      it "selects OpenAI structured output strategy", vcr: { cassette_name: "strategy_selection_openai_structured" } do
        result = module_instance.forward("What is 2+2?")
        
        expect(DSPy.logger).to have_received(:debug).with(/Selected JSON extraction strategy: openai_structured_output/)
        expect(result.answer).to be_a(String)
        expect(result.confidence).to be_a(Float)
      end
    end
    
    context "when disabled" do
      let(:lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: api_key, structured_outputs: false) }
      
      before do
        # Set both global and instance LM to ensure it's available
        DSPy.configure { |c| c.lm = lm }
        module_instance.configure { |config| config.lm = lm }
        allow(DSPy.logger).to receive(:debug).and_call_original
      end
      
      it "falls back to enhanced prompting strategy", vcr: { cassette_name: "strategy_selection_enhanced_prompting" } do
        result = module_instance.forward("What is 2+2?")
        
        expect(DSPy.logger).to have_received(:debug).with(/Selected JSON extraction strategy: enhanced_prompting/)
        expect(result.answer).to be_a(String)
        expect(result.confidence).to be_a(Float)
      end
    end
  end
  
  describe "with Anthropic" do
    let(:api_key) { ENV['ANTHROPIC_API_KEY'] || 'test-key' }
    let(:lm) { DSPy::LM.new('anthropic/claude-3-haiku-20240307', api_key: api_key) }
    
    before do
      # Set both global and instance LM to ensure it's available
      DSPy.configure { |c| c.lm = lm }
      module_instance.configure { |config| config.lm = lm }
      allow(DSPy.logger).to receive(:debug).and_call_original
    end
    
    it "selects Anthropic extraction strategy", vcr: { cassette_name: "strategy_selection_anthropic" } do
      result = module_instance.forward("What is 2+2?")
      
      expect(DSPy.logger).to have_received(:debug).with(/Selected JSON extraction strategy: anthropic_extraction/)
      expect(result.answer).to be_a(String)
      expect(result.confidence).to be_a(Float)
    end
  end
  
  describe "manual strategy override" do
    let(:lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: api_key, structured_outputs: true) }
    
    before do
      # Set both global and instance LM to ensure it's available
      DSPy.configure do |c| 
        c.lm = lm
        # Ensure logger is set to debug level
        c.logger = Dry.Logger(:dspy, level: :debug)
      end
      # Override strategy to use enhanced prompting even for OpenAI with structured outputs
      allow(DSPy.config.structured_outputs).to receive(:strategy).and_return(DSPy::Strategy::Compatible)
      module_instance.configure { |config| config.lm = lm }
      allow(DSPy.logger).to receive(:debug).and_call_original
    end
    
    after do
      # Reset the override
      allow(DSPy.config.structured_outputs).to receive(:strategy).and_return(nil)
    end
    
    it "respects manual strategy selection", vcr: { cassette_name: "strategy_selection_manual_override" } do
      # Verify the strategy was overridden by checking the actual strategy used
      strategy_selector = DSPy::LM::StrategySelector.new(lm.adapter, StrategyTestSignature)
      strategy = strategy_selector.select
      expect(strategy.name).to eq('enhanced_prompting')
      expect(strategy).to be_a(DSPy::LM::Strategies::EnhancedPromptingStrategy)
      
      # Verify the module works correctly with the overridden strategy
      result = module_instance.forward("What is 2+2?")
      expect(result.answer).to be_a(String)
      expect(result.confidence).to be_a(Float)
    end
  end
end