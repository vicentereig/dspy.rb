# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::LM::AnthropicAdapter do
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
      expect(result.usage).to be_a(DSPy::LM::Usage)
      expect(result.usage.total_tokens).to eq(30)
      expect(result.metadata[:provider]).to eq('anthropic')
      expect(result.metadata[:model]).to eq('claude-3-sonnet')
      expect(result.metadata[:response_id]).to eq('msg-123')
      expect(result.metadata[:role]).to eq('assistant')
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
      
      expect(result.metadata[:streaming]).to be_truthy
    end

    it 'handles API errors gracefully' do
      allow(mock_messages).to receive(:create)
        .and_raise(StandardError, 'API Error')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Anthropic adapter error: API Error/)
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
