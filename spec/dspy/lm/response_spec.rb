# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::Response do
  describe '.new' do
    it 'creates a response with content' do
      response = described_class.new(
        content: 'Hello, world!',
        metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test-model')
      )
      
      expect(response.content).to eq('Hello, world!')
      expect(response.usage).to be_nil
      expect(response.metadata).to be_a(DSPy::LM::ResponseMetadata)
    end
    
    it 'creates a response with usage' do
      usage = DSPy::LM::Usage.new(
        input_tokens: 10,
        output_tokens: 20,
        total_tokens: 30
      )
      
      response = described_class.new(
        content: 'Hello',
        usage: usage,
        metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test-model')
      )
      
      expect(response.usage).to eq(usage)
    end
    
    it 'accepts hash metadata for backward compatibility' do
      response = described_class.new(
        content: 'Hello',
        metadata: { provider: 'test', model: 'test-model' }
      )
      
      expect(response.metadata).to eq({ provider: 'test', model: 'test-model' })
    end
  end
  
  describe '#to_s' do
    it 'returns the content' do
      response = described_class.new(
        content: 'Test content',
        metadata: DSPy::LM::ResponseMetadata.new(provider: 'test', model: 'test-model')
      )
      
      expect(response.to_s).to eq('Test content')
    end
  end
  
  describe '#to_h' do
    context 'with typed metadata' do
      it 'converts to hash format' do
        usage = DSPy::LM::Usage.new(
          input_tokens: 10,
          output_tokens: 20,
          total_tokens: 30
        )
        
        metadata = DSPy::LM::ResponseMetadata.new(
          provider: 'openai',
          model: 'gpt-4',
          response_id: 'resp-123',
          created: 1234567890
        )
        
        response = described_class.new(
          content: 'Test',
          usage: usage,
          metadata: metadata
        )
        
        expect(response.to_h).to eq({
          content: 'Test',
          usage: {
            input_tokens: 10,
            output_tokens: 20,
            total_tokens: 30
          },
          metadata: {
            provider: 'openai',
            model: 'gpt-4',
            response_id: 'resp-123',
            created: 1234567890
          }
        })
      end
    end
    
    context 'with hash metadata' do
      it 'preserves hash format' do
        response = described_class.new(
          content: 'Test',
          metadata: { provider: 'test', custom_field: 'value' }
        )
        
        expect(response.to_h).to eq({
          content: 'Test',
          metadata: { provider: 'test', custom_field: 'value' }
        })
      end
    end
  end
end

RSpec.describe DSPy::LM::ResponseMetadata do
  describe '.new' do
    it 'creates metadata with required fields' do
      metadata = described_class.new(
        provider: 'openai',
        model: 'gpt-4'
      )
      
      expect(metadata.provider).to eq('openai')
      expect(metadata.model).to eq('gpt-4')
      expect(metadata.response_id).to be_nil
      expect(metadata.created).to be_nil
      expect(metadata.structured_output).to be_nil
    end
    
    it 'creates metadata with all fields' do
      metadata = described_class.new(
        provider: 'openai',
        model: 'gpt-4',
        response_id: 'resp-123',
        created: 1234567890,
        structured_output: true
      )
      
      expect(metadata.response_id).to eq('resp-123')
      expect(metadata.created).to eq(1234567890)
      expect(metadata.structured_output).to be true
    end
  end
  
  describe '#to_h' do
    it 'includes only non-nil fields' do
      metadata = described_class.new(
        provider: 'openai',
        model: 'gpt-4',
        response_id: 'resp-123'
      )
      
      expect(metadata.to_h).to eq({
        provider: 'openai',
        model: 'gpt-4',
        response_id: 'resp-123'
      })
    end
    
    it 'includes false values for structured_output' do
      metadata = described_class.new(
        provider: 'openai',
        model: 'gpt-4',
        structured_output: false
      )
      
      expect(metadata.to_h).to include(structured_output: false)
    end
  end
end

RSpec.describe DSPy::LM::OpenAIResponseMetadata do
  describe '.new' do
    it 'inherits base fields and adds OpenAI-specific fields' do
      metadata = described_class.new(
        provider: 'openai',
        model: 'gpt-4',
        system_fingerprint: 'fp_123',
        finish_reason: 'stop'
      )
      
      expect(metadata.provider).to eq('openai')
      expect(metadata.model).to eq('gpt-4')
      expect(metadata.system_fingerprint).to eq('fp_123')
      expect(metadata.finish_reason).to eq('stop')
    end
  end
  
  describe '#to_h' do
    it 'includes OpenAI-specific fields' do
      metadata = described_class.new(
        provider: 'openai',
        model: 'gpt-4',
        response_id: 'resp-123',
        system_fingerprint: 'fp_123',
        finish_reason: 'stop'
      )
      
      expect(metadata.to_h).to eq({
        provider: 'openai',
        model: 'gpt-4',
        response_id: 'resp-123',
        system_fingerprint: 'fp_123',
        finish_reason: 'stop'
      })
    end
  end
end

RSpec.describe DSPy::LM::AnthropicResponseMetadata do
  describe '.new' do
    it 'inherits base fields and adds Anthropic-specific fields' do
      metadata = described_class.new(
        provider: 'anthropic',
        model: 'claude-3',
        stop_reason: 'stop_sequence',
        stop_sequence: '\n\n'
      )
      
      expect(metadata.provider).to eq('anthropic')
      expect(metadata.model).to eq('claude-3')
      expect(metadata.stop_reason).to eq('stop_sequence')
      expect(metadata.stop_sequence).to eq('\n\n')
    end
  end
  
  describe '#to_h' do
    it 'includes Anthropic-specific fields' do
      metadata = described_class.new(
        provider: 'anthropic',
        model: 'claude-3',
        response_id: 'resp-123',
        stop_reason: 'stop_sequence',
        stop_sequence: '\n\n'
      )
      
      expect(metadata.to_h).to eq({
        provider: 'anthropic',
        model: 'claude-3',
        response_id: 'resp-123',
        stop_reason: 'stop_sequence',
        stop_sequence: '\n\n'
      })
    end
  end
end

RSpec.describe DSPy::LM::ResponseMetadataFactory do
  describe '.create' do
    context 'for OpenAI provider' do
      it 'creates OpenAIResponseMetadata' do
        metadata = described_class.create('openai', {
          model: 'gpt-4',
          response_id: 'resp-123',
          system_fingerprint: 'fp_123',
          finish_reason: 'stop'
        })
        
        expect(metadata).to be_a(DSPy::LM::OpenAIResponseMetadata)
        expect(metadata.system_fingerprint).to eq('fp_123')
        expect(metadata.finish_reason).to eq('stop')
      end
    end
    
    context 'for Anthropic provider' do
      it 'creates AnthropicResponseMetadata' do
        metadata = described_class.create('anthropic', {
          model: 'claude-3',
          response_id: 'resp-123',
          stop_reason: 'stop_sequence',
          stop_sequence: '\n\n'
        })
        
        expect(metadata).to be_a(DSPy::LM::AnthropicResponseMetadata)
        expect(metadata.stop_reason).to eq('stop_sequence')
        expect(metadata.stop_sequence).to eq('\n\n')
      end
    end
    
    context 'for unknown provider' do
      it 'creates base ResponseMetadata' do
        metadata = described_class.create('unknown', {
          model: 'custom-model',
          response_id: 'resp-123'
        })
        
        expect(metadata).to be_a(DSPy::LM::ResponseMetadata)
        expect(metadata.class).to eq(DSPy::LM::ResponseMetadata)
      end
    end
    
    context 'with missing model' do
      it 'raises an error' do
        expect {
          described_class.create('openai', {})
        }.to raise_error(TypeError, /Can't set .* to nil/)
      end
    end
    
    context 'with error during creation' do
      it 'raises an error when model is missing' do
        # Test that nil metadata raises an error due to missing model
        expect {
          described_class.create('openai', nil)
        }.to raise_error(TypeError, /Can't set .* to nil/)
      end
    end
  end
end