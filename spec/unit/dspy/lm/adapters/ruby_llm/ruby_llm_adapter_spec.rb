# frozen_string_literal: true

require 'spec_helper'
require 'dspy/ruby_llm'

RSpec.describe DSPy::RubyLLM::LM::Adapters::RubyLLMAdapter do
  include RubyLLMTestHelpers

  let(:api_key) { 'test-api-key' }

  describe '#initialize' do
    it 'accepts RubyLLM model ID directly' do
      adapter = described_class.new(model: 'gpt-4o', api_key: api_key)

      expect(adapter.model).to eq('gpt-4o')
    end

    it 'detects provider eagerly from RubyLLM model registry' do
      adapter = described_class.new(model: 'gpt-4o', api_key: api_key)

      expect(adapter.provider).to eq('openai')
    end

    it 'allows explicit provider override' do
      adapter = described_class.new(model: 'custom-model', api_key: api_key, provider: 'anthropic')

      expect(adapter.provider).to eq('anthropic')
    end

    it 'infers provider from model name patterns when not in registry' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      adapter = described_class.new(model: 'claude-sonnet-4', api_key: api_key)
      expect(adapter.provider).to eq('anthropic')

      adapter = described_class.new(model: 'gemini-1.5-pro', api_key: api_key)
      expect(adapter.provider).to eq('gemini')

      adapter = described_class.new(model: 'deepseek-chat', api_key: api_key)
      expect(adapter.provider).to eq('deepseek')
    end

    it 'raises error for unknown model names instead of silently defaulting' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      expect {
        described_class.new(model: 'unknown-model-xyz', api_key: api_key)
      }.to raise_error(DSPy::LM::ConfigurationError, /Cannot infer provider for model 'unknown-model-xyz'/)
    end

    it 'does not require API key for ollama' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      expect {
        described_class.new(model: 'llama3.2', api_key: nil)
      }.not_to raise_error
    end

    it 'requires API key for cloud providers when not using global config' do
      # When api_key is explicitly nil but there are options that require scoped context
      expect {
        described_class.new(model: 'gpt-4o', api_key: nil, base_url: 'http://custom')
      }.to raise_error(DSPy::LM::MissingAPIKeyError)
    end

    context 'with global RubyLLM configuration' do
      it 'uses global config when no api_key or options provided' do
        # Mock RubyLLM.chat to be called directly
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)

        adapter = described_class.new(model: 'gpt-4o')

        expect(adapter.send(:should_use_global_config?, nil, {})).to be true
      end

      it 'creates scoped context when api_key provided' do
        adapter = described_class.new(model: 'gpt-4o', api_key: api_key)

        expect(adapter.send(:should_use_global_config?, api_key, {})).to be false
        expect(adapter.context).not_to be_nil
      end

      it 'creates scoped context when base_url provided' do
        adapter = described_class.new(model: 'gpt-4o', api_key: api_key, base_url: 'http://custom')

        expect(adapter.send(:should_use_global_config?, api_key, { base_url: 'http://custom' })).to be false
      end

      it 'validates base_url scheme' do
        expect {
          described_class.new(model: 'gpt-4o', api_key: api_key, base_url: 'ftp://evil.com')
        }.to raise_error(DSPy::LM::ConfigurationError, /must use http or https scheme/)
      end

      it 'validates base_url format' do
        # URI with invalid characters triggers InvalidURIError
        expect {
          described_class.new(model: 'gpt-4o', api_key: api_key, base_url: 'http://[invalid')
        }.to raise_error(DSPy::LM::ConfigurationError, /Invalid base_url format/)
      end

      it 'rejects base_url without scheme' do
        expect {
          described_class.new(model: 'gpt-4o', api_key: api_key, base_url: 'not-a-valid-url')
        }.to raise_error(DSPy::LM::ConfigurationError, /must use http or https scheme/)
      end

      it 'accepts valid http base_url' do
        expect {
          described_class.new(model: 'gpt-4o', api_key: api_key, base_url: 'http://localhost:11434')
        }.not_to raise_error
      end

      it 'accepts valid https base_url' do
        expect {
          described_class.new(model: 'gpt-4o', api_key: api_key, base_url: 'https://api.openai.com')
        }.not_to raise_error
      end

      it 'uses global config and calls RubyLLM.chat directly' do
        # Setup: mock for global RubyLLM.chat
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)

        adapter = described_class.new(model: 'gpt-4o')
        messages = [{ role: 'user', content: 'Hello!' }]

        expect(RubyLLM).to receive(:chat).with(model: 'gpt-4o').and_return(mock_chat)

        adapter.chat(messages: messages)
      end
    end
  end

  describe '#chat' do
    let(:adapter) { described_class.new(model: 'gpt-4o', api_key: api_key) }

    context 'with basic messages' do
      let(:messages) do
        [
          { role: 'system', content: 'You are a helpful assistant.' },
          { role: 'user', content: 'Hello!' }
        ]
      end

      it 'returns a DSPy::LM::Response' do
        response = adapter.chat(messages: messages)

        expect(response).to be_a(DSPy::LM::Response)
        expect(response.content).to eq('Hello World')
      end

      it 'includes usage information' do
        response = adapter.chat(messages: messages)

        expect(response.usage.input_tokens).to eq(10)
        expect(response.usage.output_tokens).to eq(5)
        expect(response.usage.total_tokens).to eq(15)
      end

      it 'includes metadata with provider and model' do
        response = adapter.chat(messages: messages)

        expect(response.metadata.provider).to eq('ruby_llm')
        expect(response.metadata.model).to eq('gpt-4o')
      end

      it 'applies system instructions via with_instructions' do
        expect(mock_chat).to receive(:with_instructions).with('You are a helpful assistant.').and_return(mock_chat)
        adapter.chat(messages: messages)
      end

      it 'sends user message via ask' do
        expect(mock_chat).to receive(:ask).with('Hello!').and_return(mock_message)
        adapter.chat(messages: messages)
      end
    end

    context 'with streaming' do
      let(:messages) { [{ role: 'user', content: 'Hello!' }] }

      it 'yields chunks to the block' do
        chunks_received = []

        allow(mock_chat).to receive(:ask) do |content, &block|
          block.call(double(content: 'Hello ')) if block
          block.call(double(content: 'World')) if block
          mock_message
        end

        adapter.chat(messages: messages) { |chunk| chunks_received << chunk }

        expect(chunks_received).to eq(['Hello ', 'World'])
      end

      it 'still returns the complete response' do
        allow(mock_chat).to receive(:ask) do |content, &block|
          block.call(double(content: 'chunk')) if block
          mock_message
        end

        response = adapter.chat(messages: messages) { |_| }

        expect(response).to be_a(DSPy::LM::Response)
        expect(response.content).to eq('Hello World')
      end
    end

    context 'with empty messages' do
      let(:messages) { [{ role: 'system', content: 'System prompt' }] }

      it 'returns empty response when no user message' do
        response = adapter.chat(messages: messages)

        expect(response.content).to eq('')
      end
    end
  end

  describe 'error handling' do
    let(:adapter) { described_class.new(model: 'gpt-4o', api_key: api_key) }
    let(:messages) { [{ role: 'user', content: 'Hello!' }] }

    it 'converts UnauthorizedError to MissingAPIKeyError' do
      allow(mock_chat).to receive(:ask).and_raise(RubyLLM::UnauthorizedError.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::MissingAPIKeyError)
    end

    it 'converts RateLimitError to AdapterError' do
      allow(mock_chat).to receive(:ask).and_raise(RubyLLM::RateLimitError.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Rate limit exceeded/)
    end

    it 'converts ModelNotFoundError to AdapterError' do
      allow(mock_chat).to receive(:ask).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Model not found/)
    end

    it 'converts BadRequestError to AdapterError' do
      allow(mock_chat).to receive(:ask).and_raise(RubyLLM::BadRequestError.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Invalid request/)
    end

    it 'converts generic RubyLLM::Error to AdapterError' do
      allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /RubyLLM error/)
    end
  end

  describe 'provider configuration' do
    it 'configures bedrock with additional options' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      adapter = described_class.new(
        model: 'anthropic.claude-3',
        api_key: 'access-key',
        provider: 'bedrock',
        secret_key: 'secret-key',
        region: 'us-east-1'
      )

      expect(adapter.provider).to eq('bedrock')
    end

    it 'configures ollama with custom base_url' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      adapter = described_class.new(
        model: 'llama3',
        api_key: nil,
        provider: 'ollama',
        base_url: 'http://custom:11434'
      )

      expect(adapter.provider).to eq('ollama')
    end

    it 'configures vertexai with location' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      adapter = described_class.new(
        model: 'gemini-pro',
        api_key: 'project-id',
        provider: 'vertexai',
        location: 'europe-west1'
      )

      expect(adapter.provider).to eq('vertexai')
    end
  end

  describe 'JSON schema normalization' do
    let(:adapter) { described_class.new(model: 'gpt-4o', api_key: api_key) }

    it 'adds additionalProperties: false to object schemas' do
      schema = {
        type: 'object',
        properties: {
          name: { type: 'string' }
        }
      }

      normalized = adapter.send(:normalize_schema, schema)

      expect(normalized[:additionalProperties]).to eq(false)
    end

    it 'handles nested object schemas' do
      schema = {
        type: 'object',
        properties: {
          user: {
            type: 'object',
            properties: {
              name: { type: 'string' }
            }
          }
        }
      }

      normalized = adapter.send(:normalize_schema, schema)

      expect(normalized[:additionalProperties]).to eq(false)
      expect(normalized[:properties][:user][:additionalProperties]).to eq(false)
    end

    it 'handles array items with object schemas' do
      schema = {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'integer' }
          }
        }
      }

      normalized = adapter.send(:normalize_schema, schema)

      expect(normalized[:items][:additionalProperties]).to eq(false)
    end

    it 'does not mutate the original schema' do
      original = {
        type: 'object',
        properties: { name: { type: 'string' } }
      }
      frozen_copy = original.dup.freeze

      adapter.send(:normalize_schema, original)

      # Original should not have additionalProperties added
      expect(original.key?(:additionalProperties)).to be false
    end

    it 'caches normalized schemas to avoid repeated deep copies' do
      schema = {
        type: 'object',
        properties: {
          name: { type: 'string' },
          age: { type: 'integer' }
        }
      }

      # Normalize the schema twice with the same input
      first_result = adapter.send(:normalize_schema, schema)
      second_result = adapter.send(:normalize_schema, schema)

      # Should return the exact same frozen object (not just equal, but identical)
      expect(first_result.object_id).to eq(second_result.object_id)
      expect(first_result).to be_frozen
    end

    it 'returns different cached results for different schemas' do
      schema1 = {
        type: 'object',
        properties: { name: { type: 'string' } }
      }

      schema2 = {
        type: 'object',
        properties: { email: { type: 'string' } }
      }

      result1 = adapter.send(:normalize_schema, schema1)
      result2 = adapter.send(:normalize_schema, schema2)

      # Different schemas should produce different cached objects
      expect(result1.object_id).not_to eq(result2.object_id)
      expect(result1[:properties]).to have_key(:name)
      expect(result2[:properties]).to have_key(:email)
    end
  end
end
