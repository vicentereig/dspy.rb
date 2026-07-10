# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Anthropic::LM::Adapters::AnthropicAdapter do
  let(:adapter) { described_class.new(model: 'claude-3-sonnet', api_key: 'test-key') }
  let(:mock_client) { instance_double(Anthropic::Client) }
  let(:mock_messages) { double('Anthropic::Messages') }

  before do
    allow(Anthropic::Client).to receive(:new).with(api_key: 'test-key').and_return(mock_client)
    allow(mock_client).to receive(:messages).and_return(mock_messages)
  end

  describe '#initialize' do
    it 'creates Anthropic client with api_key' do
      expect(Anthropic::Client).to receive(:new).with(api_key: 'test-key')
      
      described_class.new(model: 'claude-3-sonnet', api_key: 'test-key')
    end

    it 'stores model' do
      adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key')
      expect(adapter.model).to eq('claude-3-sonnet')
    end

    it 'defaults structured_outputs to true' do
      adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key')
      expect(adapter.instance_variable_get(:@structured_outputs_enabled)).to be true
    end

    it 'accepts structured_outputs: true' do
      adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', structured_outputs: true)
      expect(adapter.instance_variable_get(:@structured_outputs_enabled)).to be true
    end

    it 'accepts structured_outputs: false' do
      adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', structured_outputs: false)
      expect(adapter.instance_variable_get(:@structured_outputs_enabled)).to be false
    end

    it 'defaults max_tokens to 4096' do
      adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key')
      expect(adapter.instance_variable_get(:@max_tokens)).to eq(4096)
    end

    it 'accepts a custom max_tokens' do
      adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', max_tokens: 16_384)
      expect(adapter.instance_variable_get(:@max_tokens)).to eq(16_384)
    end

    describe 'reasoning: validation against model capabilities' do
      it 'raises ConfigurationError for .budget on a model that only supports adaptive thinking' do
        expect {
          described_class.new(model: 'claude-sonnet-5', api_key: 'test-key', reasoning: DSPy::Reasoning.budget(2000))
        }.to raise_error(DSPy::LM::ConfigurationError, /does not support manual thinking budgets/)
      end

      it 'raises ConfigurationError for a budget below the documented 1024 minimum' do
        expect {
          described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', reasoning: DSPy::Reasoning.budget(512))
        }.to raise_error(DSPy::LM::ConfigurationError, />= 1024/)
      end

      it 'raises ConfigurationError when budget_tokens >= max_tokens' do
        expect {
          described_class.new(
            model: 'claude-3-sonnet', api_key: 'test-key',
            reasoning: DSPy::Reasoning.budget(4096), max_tokens: 4096
          )
        }.to raise_error(DSPy::LM::ConfigurationError, /less than max_tokens/)
      end

      it 'allows .budget within range on a model with manual budget support' do
        expect {
          described_class.new(
            model: 'claude-3-sonnet', api_key: 'test-key',
            reasoning: DSPy::Reasoning.budget(2000), max_tokens: 4096
          )
        }.not_to raise_error
      end

      it 'raises ConfigurationError for .adaptive on a model without adaptive thinking support' do
        expect {
          described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', reasoning: DSPy::Reasoning.adaptive)
        }.to raise_error(DSPy::LM::ConfigurationError, /does not support adaptive thinking/)
      end

      it 'allows .adaptive on a model with adaptive thinking support' do
        expect {
          described_class.new(model: 'claude-opus-4-8', api_key: 'test-key', reasoning: DSPy::Reasoning.adaptive)
        }.not_to raise_error
      end

      it 'raises ConfigurationError for .disabled on a model where thinking is always on' do
        expect {
          described_class.new(model: 'claude-fable-5', api_key: 'test-key', reasoning: DSPy::Reasoning.disabled)
        }.to raise_error(DSPy::LM::ConfigurationError, /always on/)
      end

      it 'allows .disabled on a model that supports disabling thinking' do
        expect {
          described_class.new(model: 'claude-opus-4-8', api_key: 'test-key', reasoning: DSPy::Reasoning.disabled)
        }.not_to raise_error
      end

      it 'raises ConfigurationError for any effort tier on a model with no effort support at all' do
        expect {
          described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', reasoning: DSPy::Reasoning.low)
        }.to raise_error(DSPy::LM::ConfigurationError, /does not support DSPy::Reasoning effort tiers/)
      end

      it 'allows low/medium/high effort on a model with effort support' do
        expect {
          described_class.new(model: 'claude-opus-4-5', api_key: 'test-key', reasoning: DSPy::Reasoning.high)
        }.not_to raise_error
      end

      it 'raises ConfigurationError for .xhigh on a model without xhigh support' do
        expect {
          described_class.new(model: 'claude-opus-4-5', api_key: 'test-key', reasoning: DSPy::Reasoning.xhigh)
        }.to raise_error(DSPy::LM::ConfigurationError, /does not support DSPy::Reasoning.xhigh/)
      end

      it 'allows .xhigh on a model with xhigh support' do
        expect {
          described_class.new(model: 'claude-sonnet-5', api_key: 'test-key', reasoning: DSPy::Reasoning.xhigh)
        }.not_to raise_error
      end

      it 'raises ConfigurationError for .max on a model without max support' do
        expect {
          described_class.new(model: 'claude-opus-4-5', api_key: 'test-key', reasoning: DSPy::Reasoning.max)
        }.to raise_error(DSPy::LM::ConfigurationError, /does not support DSPy::Reasoning.max/)
      end

      it 'allows .max on a model with max support' do
        expect {
          described_class.new(model: 'claude-sonnet-5', api_key: 'test-key', reasoning: DSPy::Reasoning.max)
        }.not_to raise_error
      end
    end
  end

  describe '#chat' do
    let(:messages) do
      [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]
    end

    let(:mock_response) do
      double('Anthropic::Response',
             id: 'msg-123',
             role: 'assistant',
             content: [double('Content', type: 'text', text: 'Hello back!')],
             usage: double('Usage',
                          total_tokens: 30,
                          to_h: { 'total_tokens' => 30 }))
    end

    context 'default request shape' do
      it 'makes successful API call and returns normalized response' do
        expect(mock_messages).to receive(:create).with(
          model: 'claude-3-sonnet',
          messages: [{ role: 'user', content: 'Hello' }],
          system: 'You are helpful',
          max_tokens: 4096,
          temperature: 0.0
        ).and_return(mock_response)

        result = adapter.chat(messages: messages)

        expect(result).to be_a(DSPy::LM::Response)
        expect(result.content).to eq('Hello back!')
        expect(result.usage).to be_a(DSPy::LM::AnthropicUsage)
        expect(result.usage.total_tokens).to eq(30)
        expect(result.metadata).to be_a(DSPy::LM::AnthropicResponseMetadata)
        expect(result.metadata.provider).to eq('anthropic')
        expect(result.metadata.model).to eq('claude-3-sonnet')
        expect(result.metadata.response_id).to eq('msg-123')
      end

      it 'uses the configured max_tokens instead of a hardcoded value' do
        adapter = described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', max_tokens: 8192)

        expect(mock_messages).to receive(:create).with(
          hash_including(max_tokens: 8192)
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end
    end

    context 'structured outputs (non-beta output_config.format)' do
      let(:output_format) do
        double('OutputFormat', type: :json_schema, schema: { type: 'object' })
      end

      it 'sends output_format nested under output_config, not as a top-level/beta param' do
        expect(mock_messages).to receive(:create).with(
          model: 'claude-3-sonnet',
          messages: [{ role: 'user', content: 'Hello' }],
          system: 'You are helpful',
          max_tokens: 4096,
          temperature: 0.0,
          output_config: { format: output_format }
        ).and_return(mock_response)

        result = adapter.chat(messages: messages, output_format: output_format)

        expect(result).to be_a(DSPy::LM::Response)
        expect(result.content).to eq('Hello back!')
      end

      it 'never calls the beta messages endpoint' do
        allow(mock_client).to receive(:messages).and_return(mock_messages)
        expect(mock_client).not_to receive(:beta)
        allow(mock_messages).to receive(:create).and_return(mock_response)

        adapter.chat(messages: messages, output_format: output_format)
      end

      it 'streams via the non-beta client when output_format is present with a block' do
        block_called = false
        test_block = proc { |chunk| block_called = true }

        expect(mock_messages).to receive(:stream).with(
          hash_including(output_config: { format: output_format }, stream: true)
        ).and_yield(
          double('Chunk',
                 delta: double('Delta', text: 'Hello'),
                 respond_to?: ->(method) { method == :delta })
        )

        result = adapter.chat(messages: messages, output_format: output_format, &test_block)

        expect(block_called).to be true
        expect(result).to be_a(DSPy::LM::Response)
      end

      it 'does not apply JSON prefilling when output_format is present' do
        expect(adapter).not_to receive(:prepare_messages_for_json)

        expect(mock_messages).to receive(:create).with(
          hash_including(output_config: { format: output_format })
        ).and_return(mock_response)

        adapter.chat(messages: messages, output_format: output_format)
      end
    end

    context 'reasoning: effort tiers merged into output_config' do
      let(:adapter) { described_class.new(model: 'claude-opus-4-5', api_key: 'test-key', reasoning: DSPy::Reasoning.high) }

      it 'sends output_config.effort even without a structured-output format' do
        expect(mock_messages).to receive(:create).with(
          hash_including(output_config: { effort: :high })
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end

      it 'combines effort and format under a single output_config when both are present' do
        output_format = double('OutputFormat', type: :json_schema, schema: { type: 'object' })

        expect(mock_messages).to receive(:create).with(
          hash_including(output_config: { format: output_format, effort: :high })
        ).and_return(mock_response)

        adapter.chat(messages: messages, output_format: output_format)
      end
    end

    context 'reasoning: effort tiers on an opt-in adaptive model (PR #257 review)' do
      # Opus 4.7/4.8 (and Opus/Sonnet 4.6) ship with adaptive thinking *opt-in*:
      # per Anthropic's docs, requests run without thinking unless
      # `thinking: { type: "adaptive" }` is explicitly set, independent of
      # `output_config.effort`. So DSPy::Reasoning.high/.xhigh/.max must also
      # turn on thinking here, or the "reasoning" name would be misleading.
      let(:adapter) { described_class.new(model: 'claude-opus-4-8', api_key: 'test-key', reasoning: DSPy::Reasoning.high) }

      it 'sends both thinking: {type: :adaptive} and output_config.effort' do
        expect(mock_messages).to receive(:create).with(
          hash_including(
            thinking: { type: :adaptive },
            output_config: { effort: :high }
          )
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end

      it 'does so for every effort tier on an opt-in model, not just .high' do
        [
          [DSPy::Reasoning.low, :low],
          [DSPy::Reasoning.medium, :medium],
          [DSPy::Reasoning.xhigh, :xhigh],
          [DSPy::Reasoning.max, :max]
        ].each do |reasoning, expected_effort|
          adapter = described_class.new(model: 'claude-opus-4-8', api_key: 'test-key', reasoning: reasoning)

          expect(mock_messages).to receive(:create).with(
            hash_including(thinking: { type: :adaptive }, output_config: { effort: expected_effort })
          ).and_return(mock_response)

          adapter.chat(messages: messages)
        end
      end

      it 'omits the implicit default temperature, since thinking becomes active' do
        expect(mock_messages).to receive(:create).with(
          hash_excluding(:temperature)
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end

      it 'does not add a thinking param for effort tiers on a default-on adaptive model (e.g. claude-sonnet-5)' do
        adapter = described_class.new(model: 'claude-sonnet-5', api_key: 'test-key', reasoning: DSPy::Reasoning.high)

        expect(mock_messages).to receive(:create).with(
          hash_excluding(:thinking)
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end

      it 'does not add a thinking param for effort tiers on a model without adaptive thinking at all (e.g. claude-opus-4-5)' do
        adapter = described_class.new(model: 'claude-opus-4-5', api_key: 'test-key', reasoning: DSPy::Reasoning.high)

        expect(mock_messages).to receive(:create).with(
          hash_excluding(:thinking)
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end
    end

    context 'reasoning: manual budget sends a thinking param' do
      let(:adapter) { described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', reasoning: DSPy::Reasoning.budget(2000)) }

      it 'sends thinking: {type: :enabled, budget_tokens: ...}' do
        expect(mock_messages).to receive(:create).with(
          hash_including(thinking: { type: :enabled, budget_tokens: 2000 })
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end

      it 'omits the implicit default temperature because thinking is active' do
        expect(mock_messages).to receive(:create).with(
          hash_excluding(:temperature)
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end
    end

    context 'reasoning: adaptive thinking' do
      let(:adapter) { described_class.new(model: 'claude-opus-4-8', api_key: 'test-key', reasoning: DSPy::Reasoning.adaptive) }

      it 'sends thinking: {type: :adaptive}' do
        expect(mock_messages).to receive(:create).with(
          hash_including(thinking: { type: :adaptive })
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end
    end

    context 'reasoning: disabled thinking' do
      let(:adapter) { described_class.new(model: 'claude-opus-4-8', api_key: 'test-key', reasoning: DSPy::Reasoning.disabled) }

      it 'sends thinking: {type: :disabled}' do
        expect(mock_messages).to receive(:create).with(
          hash_including(thinking: { type: :disabled })
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end
    end

    context 'reasoning: disabled thinking on a model without fixed sampling' do
      let(:adapter) { described_class.new(model: 'claude-opus-4-6', api_key: 'test-key', reasoning: DSPy::Reasoning.disabled) }

      it 'still applies the legacy default temperature since thinking is not actually active' do
        expect(mock_messages).to receive(:create).with(
          hash_including(temperature: 0.0)
        ).and_return(mock_response)

        adapter.chat(messages: messages)
      end
    end

    context 'temperature handling (#256)' do
      it 'defaults to 0.0 when not passed and the model has no restrictions' do
        expect(mock_messages).to receive(:create).with(
          hash_including(temperature: 0.0)
        ).and_return(mock_response)

        described_class.new(model: 'claude-3-sonnet', api_key: 'test-key').chat(messages: messages)
      end

      it 'omits temperature by default on a fixed-sampling model (e.g. claude-sonnet-5)' do
        expect(mock_messages).to receive(:create).with(
          hash_excluding(:temperature)
        ).and_return(mock_response)

        described_class.new(model: 'claude-sonnet-5', api_key: 'test-key').chat(messages: messages)
      end

      it 'sends an explicit temperature even on a fixed-sampling model' do
        expect(mock_messages).to receive(:create).with(
          hash_including(temperature: 0.7)
        ).and_return(mock_response)

        described_class.new(model: 'claude-sonnet-5', api_key: 'test-key', temperature: 0.7).chat(messages: messages)
      end

      it 'omits temperature when explicitly set to nil' do
        expect(mock_messages).to receive(:create).with(
          hash_excluding(:temperature)
        ).and_return(mock_response)

        described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', temperature: nil).chat(messages: messages)
      end

      it 'sends an explicit temperature of 0.0 verbatim (distinct from "not passed")' do
        expect(mock_messages).to receive(:create).with(
          hash_including(temperature: 0.0)
        ).and_return(mock_response)

        described_class.new(model: 'claude-sonnet-5', api_key: 'test-key', temperature: 0.0).chat(messages: messages)
      end

      it 'preserves a per-call temperature: passed to #chat instead of applying the implicit default (PR #257 review)' do
        expect(mock_messages).to receive(:create).with(
          hash_including(temperature: 0.7)
        ).and_return(mock_response)

        described_class.new(model: 'claude-3-sonnet', api_key: 'test-key').chat(messages: messages, temperature: 0.7)
      end

      it 'preserves an explicit per-call temperature: nil, distinct from the constructor default' do
        expect(mock_messages).to receive(:create).with(
          hash_excluding(:temperature)
        ).and_return(mock_response)

        described_class.new(model: 'claude-3-sonnet', api_key: 'test-key').chat(messages: messages, temperature: nil)
      end

      it 'lets a per-call temperature: override an explicit constructor-level temperature' do
        expect(mock_messages).to receive(:create).with(
          hash_including(temperature: 0.9)
        ).and_return(mock_response)

        described_class.new(model: 'claude-3-sonnet', api_key: 'test-key', temperature: 0.2)
          .chat(messages: messages, temperature: 0.9)
      end
    end

    it 'handles streaming with block' do
      block_called = false
      test_block = proc { |chunk| block_called = true }

      allow(mock_messages).to receive(:stream).and_yield(
        double('Chunk', 
               delta: double('Delta', text: 'Hello'),
               respond_to?: ->(method) { method == :delta })
      )

      result = adapter.chat(messages: messages, &test_block)
      
      expect(result.metadata).to be_a(DSPy::LM::AnthropicResponseMetadata)
      expect(result.metadata.provider).to eq('anthropic')
    end

    it 'handles API errors gracefully' do
      allow(mock_messages).to receive(:create)
        .and_raise(StandardError, 'API Error')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, 'Anthropic adapter error: API Error')
    end

    it 'raises ContentFilterError for content filtering errors' do
      allow(mock_messages).to receive(:create)
        .and_raise(StandardError, 'Output blocked by content filtering policy')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::Anthropic::ContentFilterError, /Anthropic content filtered/)
    end

    it 'raises ContentFilterError when response is blocked' do
      allow(mock_messages).to receive(:create)
        .and_raise(StandardError, 'Request blocked due to safety concerns')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::Anthropic::ContentFilterError, /Anthropic content filtered/)
    end
  end

  describe '#extract_system_message' do
    it 'separates system message from user messages' do
      messages = [
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' },
        { role: 'assistant', content: 'Assistant reply' }
      ]

      system_msg, user_msgs = adapter.send(:extract_system_message, messages)

      expect(system_msg).to eq('System prompt')
      expect(user_msgs).to eq([
        { role: 'user', content: 'User message' },
        { role: 'assistant', content: 'Assistant reply' }
      ])
    end

    it 'handles messages without system prompt' do
      messages = [
        { role: 'user', content: 'User message' }
      ]

      system_msg, user_msgs = adapter.send(:extract_system_message, messages)

      expect(system_msg).to be_nil
      expect(user_msgs).to eq(messages)
    end
  end

  describe '#extract_json_from_response' do
    context 'when Claude returns JSON wrapped in ```json blocks' do
      it 'extracts JSON content correctly' do
        response = "Here's the output:\n\n```json\n{\"answer\": \"Paris\", \"reasoning\": \"Paris is the capital\"}\n```"
        
        result = adapter.send(:extract_json_from_response, response)
        
        expect(result).to eq('{"answer": "Paris", "reasoning": "Paris is the capital"}')
      end

      it 'handles multiline JSON' do
        response = "```json\n{\n  \"subtasks\": [\n    \"Research AI ethics\",\n    \"Analyze implications\"\n  ],\n  \"complexity\": \"high\"\n}\n```"
        
        result = adapter.send(:extract_json_from_response, response)
        
        expect(result).to include('"subtasks"')
        expect(result).to include('"Research AI ethics"')
        expect(result).to include('"complexity": "high"')
      end
    end

    context 'when Claude returns JSON with ## Output values header' do
      it 'extracts JSON after the header' do
        response = "Let me analyze this request.\n\n## Output values\n```json\n{\"result\": \"success\"}\n```"
        
        result = adapter.send(:extract_json_from_response, response)
        
        expect(result).to eq('{"result": "success"}')
      end

      it 'handles complex responses with explanations' do
        response = "I'll help you with that task.\n\n## Output values\n```json\n{\"task_types\": [\"analysis\", \"synthesis\"], \"priority\": \"high\"}\n```\n\nThat's my analysis."
        
        result = adapter.send(:extract_json_from_response, response)
        
        expect(result).to eq('{"task_types": ["analysis", "synthesis"], "priority": "high"}')
      end
    end

    context 'when Claude returns JSON in generic code blocks' do
      it 'extracts JSON-like content from generic blocks' do
        response = "Here's the data:\n\n```\n{\"status\": \"complete\", \"count\": 42}\n```"
        
        result = adapter.send(:extract_json_from_response, response)
        
        expect(result).to eq('{"status": "complete", "count": 42}')
      end

      it 'ignores non-JSON code blocks' do
        response = "Here's some code:\n\n```\nfunction test() { return 'hello'; }\n```"
        
        result = adapter.send(:extract_json_from_response, response)
        
        # Should return original content since it doesn't look like JSON
        expect(result).to include("function test()")
      end
    end

    context 'when Claude returns plain JSON' do
      it 'returns the content as-is' do
        response = '{"answer": "42", "question": "What is the meaning of life?"}'
        
        result = adapter.send(:extract_json_from_response, response)
        
        expect(result).to eq('{"answer": "42", "question": "What is the meaning of life?"}')
      end

      it 'handles JSON with whitespace' do
        response = "  \n  {\"clean\": true}  \n  "
        
        result = adapter.send(:extract_json_from_response, response)
        
        expect(result).to eq('{"clean": true}')
      end
    end

    context 'edge cases' do
      it 'handles nil content' do
        result = adapter.send(:extract_json_from_response, nil)
        expect(result).to be_nil
      end

      it 'handles empty content' do
        result = adapter.send(:extract_json_from_response, '')
        expect(result).to eq('')
      end

      it 'handles malformed markdown blocks gracefully' do
        response = "```json\n{\"incomplete\": true"
        
        result = adapter.send(:extract_json_from_response, response)
        
        # Should return original content when extraction fails
        expect(result).to include("```json")
      end
    end
  end

  describe 'model detection methods' do
    context 'with Claude models' do
      let(:claude_adapter) { described_class.new(model: 'claude-3-5-sonnet', api_key: 'test-key') }

      it 'detects Claude models for prefilling support' do
        expect(claude_adapter.send(:supports_prefilling?)).to be true
      end

      it 'detects Claude models that tend to wrap JSON' do
        expect(claude_adapter.send(:tends_to_wrap_json?)).to be true
      end
    end

    context 'with non-Claude models' do
      let(:other_adapter) { described_class.new(model: 'some-other-model', api_key: 'test-key') }

      it 'does not detect non-Claude models for prefilling' do
        expect(other_adapter.send(:supports_prefilling?)).to be false
      end

      it 'does not detect non-Claude models as JSON wrappers' do
        expect(other_adapter.send(:tends_to_wrap_json?)).to be false
      end
    end
  end

  describe '#looks_like_json?' do
    it 'identifies object-like JSON' do
      expect(adapter.send(:looks_like_json?, '{"key": "value"}')).to be true
      expect(adapter.send(:looks_like_json?, '  {"nested": {"object": true}}  ')).to be true
    end

    it 'identifies array-like JSON' do
      expect(adapter.send(:looks_like_json?, '["item1", "item2"]')).to be true
      expect(adapter.send(:looks_like_json?, '[{"id": 1}, {"id": 2}]')).to be true
    end

    it 'rejects non-JSON strings' do
      expect(adapter.send(:looks_like_json?, 'function test() {}')).to be false
      expect(adapter.send(:looks_like_json?, 'plain text')).to be false
      expect(adapter.send(:looks_like_json?, 'SELECT * FROM table')).to be false
    end

    it 'handles edge cases' do
      expect(adapter.send(:looks_like_json?, nil)).to be false
      expect(adapter.send(:looks_like_json?, '')).to be false
      expect(adapter.send(:looks_like_json?, '   ')).to be false
    end
  end
end
