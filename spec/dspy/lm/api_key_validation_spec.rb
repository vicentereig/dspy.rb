# frozen_string_literal: true

require 'spec_helper'
require 'dspy'

RSpec.describe 'API key validation' do
  describe 'DSPy::LM initialization' do
    context 'with OpenAI' do
      it 'raises error when API key is nil' do
        expect {
          DSPy::LM.new('openai/gpt-4o-mini', api_key: nil)
        }.to raise_error(DSPy::LM::MissingAPIKeyError, /API key is required.*OPENAI_API_KEY/)
      end
      
      it 'raises error when API key is empty string' do
        expect {
          DSPy::LM.new('openai/gpt-4o-mini', api_key: '')
        }.to raise_error(DSPy::LM::MissingAPIKeyError, /API key is required.*OPENAI_API_KEY/)
      end
      
      it 'raises error when API key is whitespace only' do
        expect {
          DSPy::LM.new('openai/gpt-4o-mini', api_key: '   ')
        }.to raise_error(DSPy::LM::MissingAPIKeyError, /API key is required.*OPENAI_API_KEY/)
      end
      
      it 'succeeds with valid API key' do
        lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'sk-test123')
        expect(lm).to be_a(DSPy::LM)
        expect(lm.provider).to eq('openai')
      end
    end
    
    context 'with Anthropic' do
      it 'raises error when API key is nil' do
        expect {
          DSPy::LM.new('anthropic/claude-3-haiku', api_key: nil)
        }.to raise_error(DSPy::LM::MissingAPIKeyError, /API key is required.*ANTHROPIC_API_KEY/)
      end
      
      it 'raises error when API key is empty string' do
        expect {
          DSPy::LM.new('anthropic/claude-3-haiku', api_key: '')
        }.to raise_error(DSPy::LM::MissingAPIKeyError, /API key is required.*ANTHROPIC_API_KEY/)
      end
      
      it 'raises error when API key is whitespace only' do
        expect {
          DSPy::LM.new('anthropic/claude-3-haiku', api_key: '   ')
        }.to raise_error(DSPy::LM::MissingAPIKeyError, /API key is required.*ANTHROPIC_API_KEY/)
      end
      
      it 'succeeds with valid API key' do
        lm = DSPy::LM.new('anthropic/claude-3-haiku', api_key: 'sk-ant-test123')
        expect(lm).to be_a(DSPy::LM)
        expect(lm.provider).to eq('anthropic')
      end
    end
  end
  
  describe 'Error message quality' do
    it 'provides helpful error message for OpenAI' do
      error = nil
      begin
        DSPy::LM.new('openai/gpt-4o-mini', api_key: nil)
      rescue => e
        error = e
      end
      
      expect(error).to be_a(DSPy::LM::MissingAPIKeyError)
      expect(error.message).to include('API key is required')
      expect(error.message).to include('api_key parameter')
      expect(error.message).to include('OPENAI_API_KEY environment variable')
    end
    
    it 'provides helpful error message for Anthropic' do
      error = nil
      begin
        DSPy::LM.new('anthropic/claude-3-haiku', api_key: nil)
      rescue => e
        error = e
      end
      
      expect(error).to be_a(DSPy::LM::MissingAPIKeyError)
      expect(error.message).to include('API key is required')
      expect(error.message).to include('api_key parameter')
      expect(error.message).to include('ANTHROPIC_API_KEY environment variable')
    end
  end
end