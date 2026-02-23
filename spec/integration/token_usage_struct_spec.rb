# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Token usage with T::Struct' do
  let(:openai_lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY']) }

  describe 'Usage struct creation' do
    it 'creates OpenAI usage struct from hash' do
      usage_data = {
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 },
        completion_tokens_details: { reasoning_tokens: 0, audio_tokens: 0 }
      }
      
      usage = DSPy::LM::UsageFactory.create('openai', usage_data)
      
      expect(usage).to be_a(DSPy::LM::OpenAIUsage)
      expect(usage.input_tokens).to eq(100)
      expect(usage.output_tokens).to eq(50)
      expect(usage.total_tokens).to eq(150)
      expect(usage.prompt_tokens_details).to eq({ cached_tokens: 0, audio_tokens: 0 })
    end

    it 'handles OpenAI gem response objects' do
      # Simulate OpenAI gem response object
      mock_details = double('details', to_h: { 'cached_tokens' => 0, 'audio_tokens' => 0 })
      usage_data = {
        'prompt_tokens' => 100,
        'completion_tokens' => 50,
        'total_tokens' => 150,
        'prompt_tokens_details' => mock_details,
        'completion_tokens_details' => mock_details
      }
      
      usage = DSPy::LM::UsageFactory.create('openai', usage_data)
      
      expect(usage).to be_a(DSPy::LM::OpenAIUsage)
      expect(usage.input_tokens).to eq(100)
      expect(usage.output_tokens).to eq(50)
      expect(usage.total_tokens).to eq(150)
      expect(usage.prompt_tokens_details).to eq({ cached_tokens: 0, audio_tokens: 0 })
    end

    it 'creates Anthropic usage struct from hash' do
      usage_data = {
        input_tokens: 80,
        output_tokens: 40,
        total_tokens: 120
      }

      usage = DSPy::LM::UsageFactory.create('anthropic', usage_data)

      expect(usage).to be_a(DSPy::LM::AnthropicUsage)
      expect(usage.input_tokens).to eq(80)
      expect(usage.output_tokens).to eq(40)
      expect(usage.total_tokens).to eq(120)
      expect(usage.cache_creation_input_tokens).to be_nil
      expect(usage.cache_read_input_tokens).to be_nil
    end

    it 'creates Anthropic usage with cache fields' do
      usage_data = {
        input_tokens: 80,
        output_tokens: 40,
        total_tokens: 120,
        cache_creation_input_tokens: 500,
        cache_read_input_tokens: 200
      }

      usage = DSPy::LM::UsageFactory.create('anthropic', usage_data)

      expect(usage).to be_a(DSPy::LM::AnthropicUsage)
      expect(usage.input_tokens).to eq(80)
      expect(usage.output_tokens).to eq(40)
      expect(usage.total_tokens).to eq(120)
      expect(usage.cache_creation_input_tokens).to eq(500)
      expect(usage.cache_read_input_tokens).to eq(200)
    end

    it 'creates Anthropic usage with zero cache fields' do
      usage_data = {
        input_tokens: 80,
        output_tokens: 40,
        total_tokens: 120,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0
      }

      usage = DSPy::LM::UsageFactory.create('anthropic', usage_data)

      expect(usage).to be_a(DSPy::LM::AnthropicUsage)
      expect(usage.cache_creation_input_tokens).to eq(0)
      expect(usage.cache_read_input_tokens).to eq(0)
    end
  end

  describe 'Token tracking with structs' do
    it 'extracts tokens from Usage struct' do
      usage = DSPy::LM::Usage.new(
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      )
      
      response = DSPy::LM::Response.new(
        content: '{"answer": "test"}',
        usage: usage,
        metadata: { provider: 'openai' }
      )
      
      # Token extraction is now internal to LM, test through actual LM usage
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test-key')
      tokens = lm.send(:extract_token_usage, response)
      
      expect(tokens).to eq({
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      })
    end

    it 'extracts tokens from OpenAIUsage struct' do
      usage = DSPy::LM::OpenAIUsage.new(
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        prompt_tokens_details: { cached_tokens: 0 }
      )

      response = DSPy::LM::Response.new(
        content: '{"answer": "test"}',
        usage: usage,
        metadata: { provider: 'openai' }
      )

      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test-key')
      tokens = lm.send(:extract_token_usage, response)

      expect(tokens).to eq({
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      })
    end

    it 'extracts cache fields from AnthropicUsage struct' do
      usage = DSPy::LM::AnthropicUsage.new(
        input_tokens: 80,
        output_tokens: 40,
        total_tokens: 120,
        cache_creation_input_tokens: 500,
        cache_read_input_tokens: 200
      )

      response = DSPy::LM::Response.new(
        content: '{"answer": "test"}',
        usage: usage,
        metadata: { provider: 'anthropic' }
      )

      lm = DSPy::LM.new('anthropic/claude-sonnet-4-5-20250514', api_key: 'test-key')
      tokens = lm.send(:extract_token_usage, response)

      expect(tokens).to eq({
        input_tokens: 80,
        output_tokens: 40,
        total_tokens: 120,
        cache_creation_input_tokens: 500,
        cache_read_input_tokens: 200
      })
    end

    it 'omits nil cache fields from AnthropicUsage extraction' do
      usage = DSPy::LM::AnthropicUsage.new(
        input_tokens: 80,
        output_tokens: 40,
        total_tokens: 120
      )

      response = DSPy::LM::Response.new(
        content: '{"answer": "test"}',
        usage: usage,
        metadata: { provider: 'anthropic' }
      )

      lm = DSPy::LM.new('anthropic/claude-sonnet-4-5-20250514', api_key: 'test-key')
      tokens = lm.send(:extract_token_usage, response)

      expect(tokens).to eq({
        input_tokens: 80,
        output_tokens: 40,
        total_tokens: 120
      })
    end
  end
end