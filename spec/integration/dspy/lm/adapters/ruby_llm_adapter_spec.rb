# frozen_string_literal: true

require 'spec_helper'
require 'dspy/ruby_llm'

RSpec.describe DSPy::RubyLLM::LM::Adapters::RubyLLMAdapter do
  include RubyLLMTestHelpers


  describe '#initialize' do
    it 'stores model from parent class' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key')
      expect(adapter.model).to eq('gpt-4o')
    end

    it 'detects provider eagerly' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key')
      expect(adapter.provider).to eq('openai')
    end

    it 'defaults structured_outputs to true' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key')
      expect(adapter.instance_variable_get(:@structured_outputs_enabled)).to be true
    end

    it 'accepts structured_outputs: true' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key', structured_outputs: true)
      expect(adapter.instance_variable_get(:@structured_outputs_enabled)).to be true
    end

    it 'accepts structured_outputs: false' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key', structured_outputs: false)
      expect(adapter.instance_variable_get(:@structured_outputs_enabled)).to be false
    end

    it 'allows explicit provider override' do
      adapter = described_class.new(model: 'custom-model', api_key: 'test-key', provider: 'anthropic')
      expect(adapter.provider).to eq('anthropic')
    end
  end

  describe '#chat' do
    let(:adapter) { described_class.new(model: 'gpt-4o', api_key: 'test-key') }
    let(:messages) do
      [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]
    end

    it 'makes successful API call and returns normalized response' do
      expect(mock_chat).to receive(:with_instructions).with('You are helpful').and_return(mock_chat)
      expect(mock_chat).to receive(:ask).with('Hello').and_return(mock_message)

      result = adapter.chat(messages: messages)

      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Hello back!')
      expect(result.usage).to be_a(DSPy::LM::Usage)
      expect(result.usage.input_tokens).to eq(10)
      expect(result.usage.output_tokens).to eq(5)
      expect(result.usage.total_tokens).to eq(15)
      expect(result.metadata).to be_a(DSPy::LM::ResponseMetadata)
      expect(result.metadata.provider).to eq('ruby_llm')
      expect(result.metadata.model).to eq('gpt-4o')
    end

    it 'handles streaming with block' do
      chunks_received = []

      allow(mock_chat).to receive(:ask) do |content, &block|
        block.call(double(content: 'Hello ')) if block
        block.call(double(content: 'back!')) if block
        mock_message
      end

      result = adapter.chat(messages: messages) { |chunk| chunks_received << chunk }

      expect(chunks_received).to eq(['Hello ', 'back!'])
      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Hello back!')
    end

    it 'handles API errors gracefully' do
      allow(mock_chat).to receive(:ask)
        .and_raise(RubyLLM::Error.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /RubyLLM error/)
    end

    it 'converts UnauthorizedError to MissingAPIKeyError' do
      allow(mock_chat).to receive(:ask)
        .and_raise(RubyLLM::UnauthorizedError.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::MissingAPIKeyError)
    end

    it 'converts RateLimitError to AdapterError' do
      allow(mock_chat).to receive(:ask)
        .and_raise(RubyLLM::RateLimitError.new(nil))

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Rate limit exceeded/)
    end
  end

  describe '#prepare_chat_instance' do
    let(:adapter) { described_class.new(model: 'gpt-4o', api_key: 'test-key') }

    it 'applies system instructions' do
      messages = [
        { role: 'system', content: 'Be helpful' },
        { role: 'user', content: 'Hello' }
      ]

      expect(mock_chat).to receive(:with_instructions).with('Be helpful').and_return(mock_chat)

      adapter.send(:prepare_chat_instance, mock_chat, messages, nil)
    end

    it 'applies schema when signature provided and structured outputs enabled' do
      messages = [{ role: 'user', content: 'Hello' }]
      signature = double('signature', json_schema: { type: 'object', properties: {} })

      expect(mock_chat).to receive(:with_schema).and_return(mock_chat)

      adapter.send(:prepare_chat_instance, mock_chat, messages, signature)
    end
  end

  describe '#prepare_message_content' do
    let(:adapter) { described_class.new(model: 'gpt-4o', api_key: 'test-key') }

    it 'extracts content from last user message' do
      messages = [
        { role: 'user', content: 'First' },
        { role: 'assistant', content: 'Response' },
        { role: 'user', content: 'Second' }
      ]

      content, attachments = adapter.send(:prepare_message_content, messages)

      expect(content).to eq('Second')
      expect(attachments).to be_empty
    end

    it 'returns nil content when no user message' do
      messages = [{ role: 'system', content: 'System only' }]

      content, attachments = adapter.send(:prepare_message_content, messages)

      expect(content).to be_nil
      expect(attachments).to be_empty
    end
  end

  describe 'multi-turn conversations' do
    it 'builds conversation history using add_message before final ask' do
      messages = [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'First question' },
        { role: 'assistant', content: 'First answer' },
        { role: 'user', content: 'Second question' }
      ]

      # Expect system message to be set via with_instructions
      expect(mock_chat).to receive(:with_instructions).with('You are helpful').and_return(mock_chat)

      # Expect history messages to be added via add_message
      expect(mock_chat).to receive(:add_message).with(role: :user, content: 'First question').ordered
      expect(mock_chat).to receive(:add_message).with(role: :assistant, content: 'First answer').ordered

      # Expect final user message to be sent via ask
      expect(mock_chat).to receive(:ask).with('Second question').and_return(mock_message)

      result = adapter.chat(messages: messages)

      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Hello back!')
    end

    it 'handles single-turn conversations without add_message calls' do
      messages = [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Only question' }
      ]

      expect(mock_chat).to receive(:with_instructions).with('You are helpful').and_return(mock_chat)

      # Should NOT call add_message for single-turn
      expect(mock_chat).not_to receive(:add_message)

      # Should only call ask with the user message
      expect(mock_chat).to receive(:ask).with('Only question').and_return(mock_message)

      result = adapter.chat(messages: messages)

      expect(result).to be_a(DSPy::LM::Response)
    end
  end

  describe 'provider configuration' do
    it 'configures openai provider' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key')
      expect(adapter.provider).to eq('openai')
    end

    it 'requires explicit provider for unknown models' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      expect {
        described_class.new(model: 'unknown-model', api_key: 'test-key')
      }.to raise_error(DSPy::LM::ConfigurationError, /not found in RubyLLM registry/)
    end

    it 'accepts explicit provider for custom models' do
      mock_models = double('models')
      allow(RubyLLM).to receive(:models).and_return(mock_models)
      allow(mock_models).to receive(:find).and_raise(RubyLLM::ModelNotFoundError.new(nil))

      adapter = described_class.new(model: 'llama3.2', api_key: nil, provider: 'ollama')
      expect(adapter.provider).to eq('ollama')
    end
  end

  describe 'global config support' do
    it 'uses global config when no api_key provided' do
      allow(RubyLLM).to receive(:chat).and_return(mock_chat)

      adapter = described_class.new(model: 'gpt-4o')

      expect(adapter.send(:should_use_global_config?, nil, {})).to be true
    end

    it 'creates scoped context when api_key provided' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key')

      expect(adapter.send(:should_use_global_config?, 'test-key', {})).to be false
    end

    it 'creates scoped context when base_url provided' do
      adapter = described_class.new(model: 'gpt-4o', api_key: 'test-key', base_url: 'http://custom')

      expect(adapter.send(:should_use_global_config?, 'test-key', { base_url: 'http://custom' })).to be false
    end
  end

  describe 'JSON schema normalization' do
    let(:adapter) { described_class.new(model: 'gpt-4o', api_key: 'test-key') }

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

    it 'does not mutate the original schema' do
      original = {
        type: 'object',
        properties: { name: { type: 'string' } }
      }

      adapter.send(:normalize_schema, original)

      expect(original.key?(:additionalProperties)).to be false
    end
  end
end
