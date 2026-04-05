# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/dspy/lm/json_strategy'

RSpec.describe DSPy::LM::JSONStrategy do
  let(:signature_class) { Class.new(DSPy::Signature) }

  describe 'with OpenAI adapter' do
    let(:openai_adapter) do
      adapter = double('OpenAIAdapter')
      allow(adapter).to receive(:class).and_return(DSPy::OpenAI::LM::Adapters::OpenAIAdapter)
      allow(adapter).to receive(:model).and_return('gpt-4o-2024-08-06')
      adapter
    end
    let(:strategy) { described_class.new(openai_adapter, signature_class) }

    it 'prepares request with OpenAI structured output format' do
      messages = [{ role: 'user', content: 'Hello' }]
      request_params = {}

      # Mock instance variable access
      allow(openai_adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(true)
      allow(DSPy::OpenAI::LM::SchemaConverter).to receive(:supports_structured_outputs?)
        .with('gpt-4o-2024-08-06')
        .and_return(true)
      allow(DSPy::OpenAI::LM::SchemaConverter).to receive(:to_openai_format)
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

    it 'sanitizes raw control characters inside quoted string values' do
      response = DSPy::LM::Response.new(
        content: "{\"reasoning\":\"line1\nline2\tindent\rreturn\",\"answer\":\"ok\"}",
        usage: nil,
        metadata: {}
      )

      result = strategy.extract_json(response)

      expect(JSON.parse(result)).to eq(
        'reasoning' => "line1\nline2\tindent\rreturn",
        'answer' => 'ok'
      )
    end

    it 'sanitizes raw control characters inside fenced JSON blocks' do
      response = DSPy::LM::Response.new(
        content: "```json\n{\"reasoning\":\"line1\nline2\",\"answer\":\"ok\"}\n```",
        usage: nil,
        metadata: {}
      )

      result = strategy.extract_json(response)

      expect(JSON.parse(result)).to eq(
        'reasoning' => "line1\nline2",
        'answer' => 'ok'
      )
    end

    it 'does not double-escape already escaped JSON sequences' do
      response = DSPy::LM::Response.new(
        content: '{"reasoning":"line1\\nline2\\tindent\\rreturn","answer":"ok"}',
        usage: nil,
        metadata: {}
      )

      result = strategy.extract_json(response)

      expect(result).to eq('{"reasoning":"line1\\nline2\\tindent\\rreturn","answer":"ok"}')
      expect(JSON.parse(result)).to eq(
        'reasoning' => "line1\nline2\tindent\rreturn",
        'answer' => 'ok'
      )
    end

    it 'does not repair malformed JSON outside quoted strings' do
      response = DSPy::LM::Response.new(
        content: '{"reasoning":"ok", oops}',
        usage: nil,
        metadata: {}
      )

      result = strategy.extract_json(response)

      expect(result).to eq('{"reasoning":"ok", oops}')
      expect { JSON.parse(result) }.to raise_error(JSON::ParserError)
    end
  end

  describe 'with Anthropic adapter' do
    let(:anthropic_adapter) do
      adapter = double('AnthropicAdapter')
      allow(adapter).to receive(:class).and_return(DSPy::Anthropic::LM::Adapters::AnthropicAdapter)
      allow(adapter).to receive(:model).and_return('claude-3-5-sonnet-20241022')
      adapter
    end
    let(:strategy) { described_class.new(anthropic_adapter, signature_class) }

    before do
      # Mock output field descriptors
      allow(signature_class).to receive(:output_field_descriptors).and_return(
        { name: double(type: String, has_default: false) }
      )
      allow(DSPy::TypeSystem::SorbetJsonSchema).to receive(:type_to_json_schema)
        .and_return({ type: 'string' })
    end

    it 'prepares request with Anthropic beta structured output format' do
      messages = [{ role: 'user', content: 'Hello' }]
      request_params = {}

      strategy.prepare_request(messages, request_params)

      expect(request_params[:output_format]).to be_a(Anthropic::Models::Beta::BetaJSONOutputFormat)
      expect(request_params[:output_format].type.to_s).to eq("json_schema")
      expect(request_params[:betas]).to eq(["structured-outputs-2025-11-13"])
    end

    it 'extracts JSON from beta structured output content' do
      response = DSPy::LM::Response.new(
        content: '{"name":"John"}',
        usage: nil,
        metadata: DSPy::LM::AnthropicResponseMetadata.new(
          provider: 'anthropic',
          model: 'claude-3-5-sonnet',
          stop_reason: 'end_turn'
        )
      )

      result = strategy.extract_json(response)
      expect(JSON.parse(result)).to eq({ 'name' => 'John' })
    end

    context 'with structured_outputs: true (default)' do
      before do
        allow(anthropic_adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(true)
      end

      it 'uses beta structured outputs' do
        messages = [{ role: 'user', content: 'Hello' }]
        request_params = {}

        strategy.prepare_request(messages, request_params)

        expect(request_params[:output_format]).to be_a(Anthropic::Models::Beta::BetaJSONOutputFormat)
        expect(request_params[:betas]).to eq(["structured-outputs-2025-11-13"])
      end
    end

    context 'with structured_outputs: false' do
      before do
        allow(anthropic_adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(false)
      end

      it 'skips beta structured outputs' do
        messages = [{ role: 'user', content: 'Hello' }]
        request_params = {}

        strategy.prepare_request(messages, request_params)

        expect(request_params[:output_format]).to be_nil
        expect(request_params[:betas]).to be_nil
      end

      it 'uses enhanced prompting extraction' do
        response = DSPy::LM::Response.new(
          content: '```json\n{"name": "Jane"}\n```',
          usage: nil,
          metadata: DSPy::LM::AnthropicResponseMetadata.new(
            provider: 'anthropic',
            model: 'claude-3-5-sonnet',
            stop_reason: 'end_turn'
          )
        )

        result = strategy.extract_json(response)
        expect(result).to eq('{"name": "Jane"}')
      end
    end

    it 'repairs trailing comma before closing brace in Anthropic JSON content' do
      response = DSPy::LM::Response.new(
        content: '{"answer":"ok",}',
        usage: nil,
        metadata: {}
      )

      result = strategy.extract_json(response)
      expect(result).to eq('{"answer":"ok"}')
      expect { JSON.parse(result) }.not_to raise_error
    end

    it 'leaves valid Anthropic JSON content unchanged' do
      response = DSPy::LM::Response.new(
        content: '{"answer":"ok"}',
        usage: nil,
        metadata: {}
      )

      result = strategy.extract_json(response)
      expect(result).to eq('{"answer":"ok"}')
    end
  end

  describe 'with Gemini adapter' do
    let(:gemini_adapter) do
      adapter = double('GeminiAdapter')
      allow(adapter).to receive(:class).and_return(DSPy::Gemini::LM::Adapters::GeminiAdapter)
      allow(adapter).to receive(:model).and_return('gemini-2.0-flash-001')
      adapter
    end
    let(:strategy) { described_class.new(gemini_adapter, signature_class) }

    it 'prepares request with Gemini structured output format' do
      messages = [{ role: 'user', content: 'Hello' }]
      request_params = {}

      # Mock instance variable access
      allow(gemini_adapter).to receive(:instance_variable_get).with(:@structured_outputs_enabled).and_return(true)
      allow(DSPy::Gemini::LM::SchemaConverter).to receive(:supports_structured_outputs?)
        .with('gemini-2.0-flash-001')
        .and_return(true)
      allow(DSPy::Gemini::LM::SchemaConverter).to receive(:to_gemini_format)
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
    let(:adapter) { instance_double(DSPy::OpenAI::LM::Adapters::OpenAIAdapter) }
    let(:strategy) { described_class.new(adapter, signature_class) }

    it 'returns strategy name' do
      expect(strategy.name).to eq('json')
    end
  end

  describe 'fail-fast behavior' do
    let(:adapter) { instance_double(DSPy::OpenAI::LM::Adapters::OpenAIAdapter) }
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
