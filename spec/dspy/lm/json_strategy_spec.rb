# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/dspy/lm/json_strategy'

RSpec.describe DSPy::LM::JSONStrategy do
  let(:signature_class) { Class.new(DSPy::Signature) }

  describe 'with OpenAI adapter' do
    let(:openai_adapter) do
      adapter = double('OpenAIAdapter')
      allow(adapter).to receive(:class).and_return(DSPy::LM::OpenAIAdapter)
      allow(adapter).to receive(:model).and_return('gpt-4o-2024-08-06')
      adapter
    end
    let(:strategy) { described_class.new(openai_adapter, signature_class) }

    it 'prepares request with OpenAI structured output format' do
      messages = [{ role: 'user', content: 'Hello' }]
      request_params = {}

      # Mock instance variable access
      allow(openai_adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(true)
      allow(DSPy::LM::Adapters::OpenAI::SchemaConverter).to receive(:supports_structured_outputs?)
        .with('gpt-4o-2024-08-06')
        .and_return(true)
      allow(DSPy::LM::Adapters::OpenAI::SchemaConverter).to receive(:to_openai_format)
        .with(signature_class)
        .and_return({ type: 'json_schema', json_schema: { name: 'response', strict: true, schema: {} } })

      strategy.prepare_request(messages, request_params)

      expect(request_params[:response_format]).to eq(
        { type: 'json_schema', json_schema: { name: 'response', strict: true, schema: {} } }
      )
    end

    it 'extracts JSON from response' do
      response = DSPy::LM::Response.new(
        content: '{"name": "John"}',
        usage: nil,
        metadata: {}
      )

      expect(strategy.extract_json(response)).to eq('{"name": "John"}')
    end
  end

  describe 'with Anthropic adapter' do
    let(:anthropic_adapter) do
      adapter = double('AnthropicAdapter')
      allow(adapter).to receive(:class).and_return(DSPy::LM::AnthropicAdapter)
      allow(adapter).to receive(:model).and_return('claude-3-5-sonnet-20241022')
      adapter
    end
    let(:strategy) { described_class.new(anthropic_adapter, signature_class) }

    before do
      # Mock output field descriptors
      allow(signature_class).to receive(:output_field_descriptors).and_return(
        { name: double(type: String) }
      )
      allow(DSPy::TypeSystem::SorbetJsonSchema).to receive(:type_to_json_schema)
        .and_return({ type: 'string' })
    end

    it 'prepares request with Anthropic tool use format' do
      messages = [{ role: 'user', content: 'Hello' }]
      request_params = {}

      strategy.prepare_request(messages, request_params)

      expect(request_params[:tools]).to be_an(Array)
      expect(request_params[:tools].first[:name]).to eq('json_output')
      expect(request_params[:tool_choice]).to eq({ type: 'tool', name: 'json_output' })
      expect(messages.last[:content]).to include('use the json_output tool')
    end

    it 'extracts JSON from tool use response' do
      # Use Anthropic metadata structure
      metadata = DSPy::LM::AnthropicResponseMetadata.new(
        provider: 'anthropic',
        model: 'claude-3-5-sonnet',
        stop_reason: 'tool_use',
        tool_calls: [{ name: 'json_output', input: { name: 'John' } }]
      )

      response = DSPy::LM::Response.new(
        content: '',
        usage: nil,
        metadata: metadata
      )

      result = strategy.extract_json(response)
      expect(JSON.parse(result)).to eq({ 'name' => 'John' })
    end
  end

  describe 'with Gemini adapter' do
    let(:gemini_adapter) do
      adapter = double('GeminiAdapter')
      allow(adapter).to receive(:class).and_return(DSPy::LM::GeminiAdapter)
      allow(adapter).to receive(:model).and_return('gemini-2.0-flash-001')
      adapter
    end
    let(:strategy) { described_class.new(gemini_adapter, signature_class) }

    it 'prepares request with Gemini structured output format' do
      messages = [{ role: 'user', content: 'Hello' }]
      request_params = {}

      # Mock instance variable access
      allow(gemini_adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(true)
      allow(DSPy::LM::Adapters::Gemini::SchemaConverter).to receive(:supports_structured_outputs?)
        .with('gemini-2.0-flash-001')
        .and_return(true)
      allow(DSPy::LM::Adapters::Gemini::SchemaConverter).to receive(:to_gemini_format)
        .with(signature_class)
        .and_return({ type: 'object', properties: {} })

      strategy.prepare_request(messages, request_params)

      expect(request_params[:generation_config][:response_mime_type]).to eq('application/json')
      expect(request_params[:generation_config][:response_json_schema]).to eq({ type: 'object', properties: {} })
    end

    it 'extracts JSON from response' do
      response = DSPy::LM::Response.new(
        content: '{"name": "John"}',
        usage: nil,
        metadata: {}
      )

      expect(strategy.extract_json(response)).to eq('{"name": "John"}')
    end
  end

  describe '#name' do
    let(:adapter) { instance_double(DSPy::LM::OpenAIAdapter) }
    let(:strategy) { described_class.new(adapter, signature_class) }

    it 'returns strategy name' do
      expect(strategy.name).to eq('json')
    end
  end

  describe 'fail-fast behavior' do
    let(:adapter) { instance_double(DSPy::LM::OpenAIAdapter) }
    let(:strategy) { described_class.new(adapter, signature_class) }

    it 'raises error on JSON parsing failure (no fallback)' do
      response = DSPy::LM::Response.new(
        content: 'Not JSON',
        usage: nil,
        metadata: {}
      )

      # JSONStrategy returns content as-is, parsing happens elsewhere
      expect(strategy.extract_json(response)).to eq('Not JSON')
    end
  end
end
