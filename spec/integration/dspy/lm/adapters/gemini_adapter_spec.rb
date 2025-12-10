# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Gemini::LM::Adapters::GeminiAdapter do
  let(:adapter) { described_class.new(model: 'gemini-2.5-flash', api_key: 'test-key') }
  let(:mock_client) { double('Gemini Client') }

  before do
    # Mock single streaming client
    allow(Gemini).to receive(:new).with(
      credentials: {
        service: 'generative-language-api',
        api_key: anything,
        version: 'v1beta'
      },
      options: hash_including(server_sent_events: true)
    ).and_return(mock_client)
  end

  describe '#initialize' do
    it 'creates single streaming Gemini client' do
      expect(Gemini).to receive(:new).with(
        credentials: {
          service: 'generative-language-api',
          api_key: 'test-key',
          version: 'v1beta'
        },
        options: { 
          model: 'gemini-2.5-flash',
          server_sent_events: true 
        }
      ).and_return(mock_client)
      
      described_class.new(model: 'gemini-2.5-flash', api_key: 'test-key')
    end

    it 'stores model' do
      adapter = described_class.new(model: 'gemini-2.5-flash', api_key: 'test-key')
      expect(adapter.model).to eq('gemini-2.5-flash')
    end

    it 'validates API key is present' do
      expect {
        described_class.new(model: 'gemini-2.5-flash', api_key: nil)
      }.to raise_error(DSPy::LM::MissingAPIKeyError, /GEMINI_API_KEY/)
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
      {
        'candidates' => [{
          'content' => {
            'role' => 'model',
            'parts' => [{ 'text' => 'Hello back!' }]
          },
          'finishReason' => 'STOP',
          'safetyRatings' => []
        }],
        'usageMetadata' => {
          'promptTokenCount' => 10,
          'candidatesTokenCount' => 5,
          'totalTokenCount' => 15
        }
      }
    end

    it 'makes successful API call and returns normalized response' do
      expected_gemini_request = {
        contents: [
          { role: 'user', parts: [{ text: 'You are helpful' }] },
          { role: 'user', parts: [{ text: 'Hello' }] }
        ]
      }
      
      # Mock non-streaming response (since tests run with VCR)
      mock_response = {
        'candidates' => [{
          'content' => {
            'role' => 'model',
            'parts' => [{ 'text' => 'Hello back!' }]
          },
          'finishReason' => 'STOP',
          'safetyRatings' => []
        }],
        'usageMetadata' => {
          'promptTokenCount' => 10,
          'candidatesTokenCount' => 5,
          'totalTokenCount' => 15
        }
      }
      
      expect(mock_client).to receive(:stream_generate_content)
        .with(expected_gemini_request)
        .and_yield({
          'candidates' => [{
            'content' => {
              'role' => 'model',
              'parts' => [{ 'text' => 'Hello back!' }]
            }
          }]
        })
        .and_yield({
          'candidates' => [{
            'finishReason' => 'STOP',
            'safetyRatings' => []
          }],
          'usageMetadata' => {
            'promptTokenCount' => 10,
            'candidatesTokenCount' => 5,
            'totalTokenCount' => 15
          }
        })

      result = adapter.chat(messages: messages)

      expect(result).to be_a(DSPy::LM::Response)
      expect(result.content).to eq('Hello back!')
      expect(result.usage).to be_a(DSPy::LM::Usage)
      expect(result.usage.input_tokens).to eq(10)
      expect(result.usage.output_tokens).to eq(5)
      expect(result.usage.total_tokens).to eq(15)
      expect(result.metadata).to be_a(DSPy::LM::GeminiResponseMetadata)
      expect(result.metadata.provider).to eq('gemini')
      expect(result.metadata.model).to eq('gemini-2.5-flash')
      expect(result.metadata.finish_reason).to eq('STOP')
      expect(result.metadata.streaming).to be false
    end
    
    it 'passes extra parameters to Gemini API' do
      expected_gemini_request = {
        contents: [
          { role: 'user', parts: [{ text: 'You are helpful' }] },
          { role: 'user', parts: [{ text: 'Hello' }] }
        ],
        temperature: 0.7,
        max_output_tokens: 100
      }
      
      expect(mock_client).to receive(:stream_generate_content)
        .with(expected_gemini_request)
        .and_yield({ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => 'response' }] } }] })

      adapter.chat(
        messages: messages, 
        temperature: 0.7, 
        max_output_tokens: 100
      )
    end

    it 'handles streaming with block' do
      block_called = false
      test_block = proc { |chunk| block_called = true }

      streaming_chunk = {
        'candidates' => [{
          'content' => {
            'parts' => [{ 'text' => 'Hello' }]
          }
        }]
      }

      expect(mock_client).to receive(:stream_generate_content)
        .and_yield(streaming_chunk)

      result = adapter.chat(messages: messages, &test_block)
      
      expect(block_called).to be true
      expect(result.metadata).to be_a(DSPy::LM::GeminiResponseMetadata)
      expect(result.metadata.provider).to eq('gemini')
      expect(result.metadata.streaming).to be true
    end
    
    it 'handles empty response gracefully' do
      empty_response = {
        'candidates' => [{ 'content' => { 'parts' => [] } }],
        'usageMetadata' => { 'totalTokenCount' => 5 }
      }
      
      expect(mock_client).to receive(:stream_generate_content)
        .and_yield(empty_response)

      result = adapter.chat(messages: messages)
      
      expect(result.content).to eq('')
    end
    
    it 'handles response without candidates' do
      no_candidates_response = {
        'candidates' => [],
        'usageMetadata' => { 'totalTokenCount' => 5 }
      }
      
      expect(mock_client).to receive(:stream_generate_content)
        .and_yield(no_candidates_response)

      result = adapter.chat(messages: messages)
      
      expect(result.content).to eq('')
    end
    
    it 'handles response without usage metadata' do
      no_usage_response = {
        'candidates' => [{ 'content' => { 'parts' => [{ 'text' => 'Hello!' }] } }]
      }
      
      expect(mock_client).to receive(:stream_generate_content)
        .and_yield(no_usage_response)

      result = adapter.chat(messages: messages)
      
      expect(result.content).to eq('Hello!')
      expect(result.usage).to be_nil
    end

    it 'handles API errors gracefully' do
      allow(mock_client).to receive(:stream_generate_content)
        .and_raise(StandardError, 'API Error')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, 'Gemini adapter error: API Error')
    end

    it 'handles authentication errors specifically' do
      allow(mock_client).to receive(:stream_generate_content)
        .and_raise(StandardError, 'API_KEY invalid')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Gemini authentication failed/)
    end

    it 'handles rate limit errors specifically' do
      allow(mock_client).to receive(:stream_generate_content)
        .and_raise(StandardError, 'RATE_LIMIT exceeded')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /Gemini rate limit exceeded/)
    end

    it 'handles safety filter errors specifically' do
      allow(mock_client).to receive(:stream_generate_content)
        .and_raise(StandardError, 'Content blocked by SAFETY filters')

      expect {
        adapter.chat(messages: messages)
      }.to raise_error(DSPy::LM::AdapterError, /blocked by safety filters/)
    end
  end

  describe '#convert_messages_to_gemini_format' do
    it 'converts system messages to user role' do
      messages = [
        { role: 'system', content: 'You are helpful' },
        { role: 'user', content: 'Hello' }
      ]

      result = adapter.send(:convert_messages_to_gemini_format, messages)

      expect(result).to eq([
        { role: 'user', parts: [{ text: 'You are helpful' }] },
        { role: 'user', parts: [{ text: 'Hello' }] }
      ])
    end

    it 'converts assistant role to model' do
      messages = [
        { role: 'user', content: 'Hello' },
        { role: 'assistant', content: 'Hi there!' }
      ]

      result = adapter.send(:convert_messages_to_gemini_format, messages)

      expect(result).to eq([
        { role: 'user', parts: [{ text: 'Hello' }] },
        { role: 'model', parts: [{ text: 'Hi there!' }] }
      ])
    end

    it 'handles multimodal content with images' do
      mock_image = instance_double(DSPy::Image)
      allow(mock_image).to receive(:to_gemini_format).and_return({
        inline_data: {
          mime_type: 'image/jpeg',
          data: 'base64data'
        }
      })

      messages = [
        {
          role: 'user',
          content: [
            { type: 'text', text: 'What is in this image?' },
            { type: 'image', image: mock_image }
          ]
        }
      ]

      result = adapter.send(:convert_messages_to_gemini_format, messages)

      expect(result).to eq([
        {
          role: 'user',
          parts: [
            { text: 'What is in this image?' },
            {
              inline_data: {
                mime_type: 'image/jpeg',
                data: 'base64data'
              }
            }
          ]
        }
      ])
    end
  end

  describe '#extract_text_from_parts' do
    it 'extracts text from parts array' do
      parts = [
        { 'text' => 'Hello ' },
        { 'text' => 'world!' }
      ]

      result = adapter.send(:extract_text_from_parts, parts)
      expect(result).to eq('Hello world!')
    end

    it 'handles empty parts array' do
      result = adapter.send(:extract_text_from_parts, [])
      expect(result).to eq('')
    end

    it 'handles nil parts' do
      result = adapter.send(:extract_text_from_parts, nil)
      expect(result).to eq('')
    end

    it 'ignores non-text parts' do
      parts = [
        { 'text' => 'Hello' },
        { 'other' => 'ignored' },
        { 'text' => ' world!' }
      ]

      result = adapter.send(:extract_text_from_parts, parts)
      expect(result).to eq('Hello world!')
    end
  end

  describe '#handle_gemini_error' do
    it 'handles authentication errors' do
      error = StandardError.new('Invalid API_KEY provided')
      
      expect {
        adapter.send(:handle_gemini_error, error)
      }.to raise_error(DSPy::LM::AdapterError, /Gemini authentication failed/)
    end
    
    it 'handles status 400 errors as authentication errors' do
      error = StandardError.new('the server responded with status 400')
      
      expect {
        adapter.send(:handle_gemini_error, error)
      }.to raise_error(DSPy::LM::AdapterError, /Gemini authentication failed/)
    end

    it 'handles rate limit errors' do
      error = StandardError.new('RATE_LIMIT exceeded for requests')
      
      expect {
        adapter.send(:handle_gemini_error, error)
      }.to raise_error(DSPy::LM::AdapterError, /Gemini rate limit exceeded/)
    end

    it 'handles quota errors' do
      error = StandardError.new('Quota exceeded')
      
      expect {
        adapter.send(:handle_gemini_error, error)
      }.to raise_error(DSPy::LM::AdapterError, /rate limit exceeded/)
    end

    it 'handles safety filter errors' do
      error = StandardError.new('Content blocked by SAFETY filters')
      
      expect {
        adapter.send(:handle_gemini_error, error)
      }.to raise_error(DSPy::LM::AdapterError, /blocked by safety filters/)
    end

    it 'handles image processing errors' do
      error = StandardError.new('Invalid image format provided')
      
      expect {
        adapter.send(:handle_gemini_error, error)
      }.to raise_error(DSPy::LM::AdapterError, /Gemini image processing failed/)
    end

    it 'handles generic errors' do
      error = StandardError.new('Unknown error occurred')
      
      expect {
        adapter.send(:handle_gemini_error, error)
      }.to raise_error(DSPy::LM::AdapterError, 'Gemini adapter error: Unknown error occurred')
    end
  end

  describe 'vision support validation' do
    let(:vision_adapter) { described_class.new(model: 'gemini-1.5-pro', api_key: 'test-key') }
    let(:non_vision_adapter) { described_class.new(model: 'gemini-text-only', api_key: 'test-key') }

    it 'validates vision support for vision-capable models' do
      expect(DSPy::LM::VisionModels).to receive(:validate_vision_support!)
        .with('gemini', 'gemini-1.5-pro')

      messages = [
        {
          role: 'user',
          content: [
            { type: 'text', text: 'What is this?' },
            { type: 'image', image: instance_double(DSPy::Image, 
                validate_for_provider!: true,
                to_gemini_format: { inline_data: { mime_type: 'image/png', data: 'test' } }
              ) }
          ]
        }
      ]

      expect(mock_client).to receive(:stream_generate_content)
        .and_yield({
          'candidates' => [{ 'content' => { 'parts' => [{ 'text' => 'response' }] } }],
          'usageMetadata' => { 'totalTokenCount' => 10 }
        })

      vision_adapter.chat(messages: messages)
    end

    it 'raises error for non-vision models with image content' do
      allow(DSPy::LM::VisionModels).to receive(:validate_vision_support!)
        .with('gemini', 'gemini-text-only')
        .and_raise(ArgumentError, 'Model does not support vision')

      messages = [
        {
          role: 'user',
          content: [
            { type: 'image', image: instance_double(DSPy::Image) }
          ]
        }
      ]

      expect {
        non_vision_adapter.chat(messages: messages)
      }.to raise_error(ArgumentError, 'Model does not support vision')
    end
  end

  describe '#normalize_messages' do
    it 'normalizes messages correctly' do
      messages = [
        { role: 'system', content: 'System prompt' },
        { role: 'user', content: 'User message' }
      ]

      normalized = adapter.send(:normalize_messages, messages)
      
      expect(normalized).to eq(messages)
    end

    it 'handles empty messages array' do
      normalized = adapter.send(:normalize_messages, [])
      expect(normalized).to eq([])
    end

    it 'preserves multimodal message structure' do
      messages = [
        {
          role: 'user',
          content: [
            { type: 'text', text: 'What is this?' },
            { type: 'image', image: instance_double(DSPy::Image) }
          ]
        }
      ]

      normalized = adapter.send(:normalize_messages, messages)
      expect(normalized).to eq(messages)
    end
  end
end
