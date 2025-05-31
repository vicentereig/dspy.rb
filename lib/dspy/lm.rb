# frozen_string_literal: true
require 'ruby_llm'

module DSPy
  class LM
    attr_reader :model_id, :api_key, :model, :provider

    def initialize(model_id, api_key: nil)
      @model_id = model_id
      @api_key = api_key
      # Configure RubyLLM with the API key if provided
      if model_id.start_with?('openai/')
        RubyLLM.configure do |config|
          config.openai_api_key = api_key
        end
        @provider = :openai
        @model = model_id.split('/').last
      elsif model_id.start_with?('anthropic/')
        RubyLLM.configure do |config|
          config.anthropic_api_key = api_key
        end
        @provider = :anthropic
        @model = model_id.split('/').last
      else
        raise ArgumentError, "Unsupported model provider: #{model_id}"
      end
    end

    def chat(inference_module, input_values, &block)
      signature_class = inference_module.signature_class
      chat = RubyLLM.chat(model: model)
      system_prompt = inference_module.system_signature
      user_prompt = inference_module.user_signature(input_values)
      chat.add_message role: :system, content: system_prompt
      chat.ask(user_prompt, &block)

      parse_response(chat.messages.last, input_values, signature_class)
    end

    private
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

        # Handle different signature types
        if signature_class < DSPy::SorbetSignature
          # For Sorbet signatures, just return the parsed JSON
          # The SorbetPredict will handle validation
          json_payload
        else
          # Original dry-schema based handling
          output = signature_class.output_schema.call(json_payload)

          result_schema = Dry::Schema.JSON(parent: [signature_class.input_schema, signature_class.output_schema])
          result = output.to_h.merge(input_values)
          # create an instance with input and output schema
          poro_result = result_schema.call(result)

          poro_result.to_h
        end
      rescue JSON::ParserError
        raise "Failed to parse LLM response as JSON: #{content}"
      end
    end
  end
end
