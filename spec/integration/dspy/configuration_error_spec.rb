# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy Configuration Error Handling' do
  # Test module that tries to use LM directly
  let(:test_module_class) do
    Class.new(DSPy::Module) do
      def forward_untyped(**input_values)
        # This will trigger the LM check
        if lm.nil?
          raise DSPy::ConfigurationError.missing_lm(self.class.name)
        end
        { response: "test response" }
      end
    end
  end
  
  let(:test_module) { test_module_class.new }
  
  # Define a test signature
  class ConfigTestSignature < DSPy::Signature
    input do
      const :query, String
    end
    
    output do
      const :response, String
    end
  end
  
  before do
    # Clear any global configuration
    DSPy.configure do |config|
      config.lm = nil
    end
  end
  
  after do
    # Restore a default LM to avoid affecting other tests
    DSPy.configure do |config|
      mock_lm = instance_double(DSPy::LM, model: 'gpt-3.5-turbo', schema_format: :json)
      config.lm = T.unsafe(mock_lm)
    end
  end
  
  describe 'when no LM is configured' do
    it 'raises ConfigurationError with helpful message' do
      expect {
        test_module.forward(query: 'test')
      }.to raise_error(DSPy::ConfigurationError) do |error|
        expect(error.message).to include('No language model configured')
        expect(error.message).to include('DSPy.configure')
        expect(error.message).to include('module_instance.configure')
      end
    end
    
    it 'includes the module class name in the error' do
      expect {
        test_module.forward(query: 'test')
      }.to raise_error(DSPy::ConfigurationError) do |error|
        # Anonymous classes show as Class or #<Class:0x...>
        expect(error.message).to match(/No language model configured for/)
      end
    end
  end
  
  describe 'when global LM is configured' do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new('openai/gpt-3.5-turbo', api_key: 'global-key')
      end
    end
    
    it 'does not raise an error' do
      expect {
        test_module.forward(query: 'test')
      }.not_to raise_error
    end
  end
  
  describe 'when instance LM is configured' do
    before do
      test_module.configure do |config|
        config.lm = DSPy::LM.new('openai/gpt-4', api_key: 'instance-key')
      end
    end
    
    it 'does not raise an error even without global LM' do
      expect {
        test_module.forward(query: 'test')
      }.not_to raise_error
    end
  end
  
  describe 'ConfigurationError class' do
    it 'is a subclass of DSPy::Error' do
      expect(DSPy::ConfigurationError).to be < DSPy::Error
    end
    
    it 'provides a helpful factory method for missing LM' do
      error = DSPy::ConfigurationError.missing_lm('MyModule')
      expect(error).to be_a(DSPy::ConfigurationError)
      expect(error.message).to include('MyModule')
      expect(error.message).to include('OPENAI_API_KEY')
      expect(error.message).to include('ANTHROPIC_API_KEY')
    end
  end
  
  describe 'with real DSPy modules' do
    context 'with Predict module' do
      let(:predict_module) { DSPy::Predict.new(ConfigTestSignature) }
      
      it 'raises ConfigurationError when no LM configured' do
        expect {
          predict_module.forward(query: 'test')
        }.to raise_error(DSPy::ConfigurationError)
      end
    end
    
    context 'with ChainOfThought module' do
      let(:cot_module) { DSPy::ChainOfThought.new(ConfigTestSignature) }
      
      it 'raises ConfigurationError when no LM configured' do
        expect {
          cot_module.forward(query: 'test')
        }.to raise_error(DSPy::ConfigurationError)
      end
    end
  end
end