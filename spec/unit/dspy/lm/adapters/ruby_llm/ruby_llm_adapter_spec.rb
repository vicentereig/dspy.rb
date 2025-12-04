# frozen_string_literal: true

require 'spec_helper'

# Mock RubyLLM for unit tests
module RubyLLM
  class Error < StandardError; end
  class UnauthorizedError < Error; end
  class RateLimitError < Error; end
  class ModelNotFoundError < Error; end
  class BadRequestError < Error; end
  class ConfigurationError < Error; end

  class Chunk
    attr_reader :content, :tool_calls

    def initialize(content: nil, tool_calls: nil)
      @content = content
      @tool_calls = tool_calls
    end
  end

  class Message
    attr_reader :content, :model_id, :input_tokens, :output_tokens

    def initialize(content:, model_id: nil, input_tokens: nil, output_tokens: nil)
      @content = content
      @model_id = model_id
      @input_tokens = input_tokens
      @output_tokens = output_tokens
    end
  end

  class Chat
    attr_reader :model

    def initialize(model:)
      @model = model
      @instructions = nil
      @schema = nil
    end

    def with_instructions(instructions)
      @instructions = instructions
      self
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def ask(content, with: nil, &block)
      if block_given?
        # Simulate streaming
        yield Chunk.new(content: "Hello ")
        yield Chunk.new(content: "World")
      end

      Message.new(
        content: "Hello World",
        model_id: @model,
        input_tokens: 10,
        output_tokens: 5
      )
    end
  end

  class Context
    def initialize
      @config = OpenStruct.new
      yield @config if block_given?
    end

    def chat(model:)
      Chat.new(model: model)
    end
  end

  def self.context(&block)
    Context.new(&block)
  end
end

RSpec.describe DSPy::RubyLLM::LM::Adapters::RubyLLMAdapter do
  let(:api_key) { 'test-api-key' }

  describe '#initialize' do
    it 'parses provider:model format correctly' do
      adapter = described_class.new(model: 'openai:gpt-4o', api_key: api_key)

      expect(adapter.provider).to eq('openai')
      expect(adapter.ruby_llm_model).to eq('gpt-4o')
    end

    it 'raises error for invalid model format' do
      expect {
        described_class.new(model: 'gpt-4o', api_key: api_key)
      }.to raise_error(DSPy::LM::ConfigurationError, /Invalid model format/)
    end

    it 'accepts various provider names' do
      %w[openai anthropic gemini bedrock ollama openrouter deepseek mistral perplexity].each do |provider|
        adapter = described_class.new(model: "#{provider}:model-name", api_key: api_key)
        expect(adapter.provider).to eq(provider)
      end
    end

    it 'raises error for unknown provider' do
      expect {
        described_class.new(model: 'unknown:model', api_key: api_key)
      }.to raise_error(DSPy::LM::ConfigurationError, /Unknown provider/)
    end
  end

  describe '#chat' do
    let(:adapter) { described_class.new(model: 'openai:gpt-4o', api_key: api_key) }

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
    end

    context 'with streaming' do
      let(:messages) { [{ role: 'user', content: 'Hello!' }] }

      it 'yields chunks to the block' do
        chunks = []
        adapter.chat(messages: messages) { |chunk| chunks << chunk }

        expect(chunks).to eq(['Hello ', 'World'])
      end

      it 'still returns the complete response' do
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
    let(:adapter) { described_class.new(model: 'openai:gpt-4o', api_key: api_key) }
    let(:messages) { [{ role: 'user', content: 'Hello!' }] }

    it 'converts UnauthorizedError to MissingAPIKeyError' do
      allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_raise(RubyLLM::UnauthorizedError, 'Invalid key')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::MissingAPIKeyError)
    end

    it 'converts RateLimitError to AdapterError' do
      allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_raise(RubyLLM::RateLimitError, 'Rate limited')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Rate limit exceeded/)
    end

    it 'converts ModelNotFoundError to AdapterError' do
      allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_raise(RubyLLM::ModelNotFoundError, 'Model not found')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Model not found/)
    end

    it 'converts BadRequestError to AdapterError' do
      allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_raise(RubyLLM::BadRequestError, 'Bad request')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Invalid request/)
    end

    it 'converts generic RubyLLM::Error to AdapterError' do
      allow_any_instance_of(RubyLLM::Chat).to receive(:ask).and_raise(RubyLLM::Error, 'Generic error')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /RubyLLM error/)
    end
  end

  describe 'provider configuration' do
    it 'configures bedrock with additional options' do
      adapter = described_class.new(
        model: 'bedrock:anthropic.claude-3',
        api_key: 'access-key',
        secret_key: 'secret-key',
        region: 'us-east-1'
      )

      expect(adapter.provider).to eq('bedrock')
    end

    it 'configures ollama with custom base_url' do
      adapter = described_class.new(
        model: 'ollama:llama3',
        api_key: nil,
        base_url: 'http://custom:11434'
      )

      expect(adapter.provider).to eq('ollama')
    end

    it 'configures vertexai with location' do
      adapter = described_class.new(
        model: 'vertexai:gemini-pro',
        api_key: 'project-id',
        location: 'europe-west1'
      )

      expect(adapter.provider).to eq('vertexai')
    end
  end

  describe 'JSON schema normalization' do
    let(:adapter) { described_class.new(model: 'openai:gpt-4o', api_key: api_key) }

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
      original_dup = original.dup

      adapter.send(:normalize_schema, original)

      expect(original).to eq(original_dup)
    end
  end
end
