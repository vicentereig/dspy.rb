# frozen_string_literal: true

# Load adapter infrastructure
require_relative 'lm/errors'
require_relative 'lm/response'
require_relative 'lm/adapter'
require_relative 'lm/adapter_factory'

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
      
      # Call adapter with messages
      response = adapter.chat(messages: messages, &block)
      
      # Parse and return response
      parse_response(response, input_values, signature_class)
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
