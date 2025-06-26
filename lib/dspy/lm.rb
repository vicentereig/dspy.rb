# frozen_string_literal: true

# Load adapter infrastructure
require_relative 'lm/errors'
require_relative 'lm/response'
require_relative 'lm/adapter'
require_relative 'lm/adapter_factory'

# Load instrumentation
require_relative 'instrumentation'
require_relative 'instrumentation/token_tracker'

# Load adapters
require_relative 'lm/adapters/openai_adapter'
require_relative 'lm/adapters/anthropic_adapter'
require_relative 'lm/adapters/ruby_llm_adapter'

module DSPy
  class LM
    attr_reader :model_id, :api_key, :model, :provider, :adapter

    def initialize(model_id, api_key: nil)
      @model_id = model_id
      @api_key = api_key
      
      # Parse provider and model from model_id
      @provider, @model = parse_model_id(model_id)
      
      # Create appropriate adapter
      @adapter = AdapterFactory.create(model_id, api_key: api_key)
    end

    def chat(inference_module, input_values, &block)
      signature_class = inference_module.signature_class
      
      # Build messages from inference module
      messages = build_messages(inference_module, input_values)
      
      # Calculate input size for monitoring
      input_text = messages.map { |m| m[:content] }.join(' ')
      input_size = input_text.length
      
      # Instrument LM request
      response = Instrumentation.instrument('dspy.lm.request', {
        gen_ai_operation_name: 'chat',
        gen_ai_system: provider,
        gen_ai_request_model: model,
        signature_class: signature_class.name,
        provider: provider,
        adapter_class: adapter.class.name,
        input_size: input_size
      }) do
        adapter.chat(messages: messages, &block)
      end
      
      # Extract actual token usage from response (more accurate than estimation)
      token_usage = Instrumentation::TokenTracker.extract_token_usage(response, provider)
      
      # Emit token usage event if available
      if token_usage.any?
        Instrumentation.emit('dspy.lm.tokens', token_usage.merge({
          gen_ai_system: provider,
          gen_ai_request_model: model,
          signature_class: signature_class.name
        }))
      end
      
      # Instrument response parsing
      parsed_result = Instrumentation.instrument('dspy.lm.response.parsed', {
        signature_class: signature_class.name,
        provider: provider,
        response_length: response.content&.length || 0
      }) do
        parse_response(response, input_values, signature_class)
      end
      
      parsed_result
    end

    private

    def parse_model_id(model_id)
      if model_id.include?('/')
        provider, model = model_id.split('/', 2)
        [provider, model]
      else
        # Legacy format: assume ruby_llm for backward compatibility
        ['ruby_llm', model_id]
      end
    end

    def build_messages(inference_module, input_values)
      messages = []
      
      # Add system message
      system_prompt = inference_module.system_signature
      messages << { role: 'system', content: system_prompt } if system_prompt
      
      # Add user message
      user_prompt = inference_module.user_signature(input_values)
      messages << { role: 'user', content: user_prompt }
      
      messages
    end

    def parse_response(response, input_values, signature_class)
      # Try to parse the response as JSON
      content = response.content

      # Extract JSON if it's in a code block
      if content.include?('```json')
        content = content.split('```json').last.split('```').first.strip
      elsif content.include?('```')
        content = content.split('```').last.split('```').first.strip
      end

      begin
        json_payload = JSON.parse(content)

        # For Sorbet signatures, just return the parsed JSON
        # The Predict will handle validation
        json_payload
      rescue JSON::ParserError
        raise "Failed to parse LLM response as JSON: #{content}"
      end
    end
  end
end
