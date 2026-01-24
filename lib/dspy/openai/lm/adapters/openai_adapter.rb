# frozen_string_literal: true

require 'openai'
require_relative '../schema_converter'
require 'dspy/lm/vision_models'
require 'dspy/lm/adapter'

require 'dspy/openai/guardrails'
DSPy::OpenAI::Guardrails.ensure_openai_installed!

module DSPy
  module OpenAI
    module LM
      module Adapters
        class OpenAIAdapter < DSPy::LM::Adapter
          def initialize(model:, api_key:, structured_outputs: false)
            super(model: model, api_key: api_key)
            validate_api_key!(api_key, 'openai')
            @client = ::OpenAI::Client.new(api_key: api_key)
            @structured_outputs_enabled = structured_outputs
          end

          def chat(messages:, signature: nil, response_format: nil, &block)
            normalized_messages = normalize_messages(messages)

            # Validate vision support if images are present
            if contains_images?(normalized_messages)
              DSPy::LM::VisionModels.validate_vision_support!('openai', model)
              # Convert messages to OpenAI format with proper image handling
              normalized_messages = format_multimodal_messages(normalized_messages, 'openai')
            end

            # Handle O1 model restrictions - convert system messages to user messages
            if o1_model?(model)
              normalized_messages = handle_o1_messages(normalized_messages)
            end

            request_params = default_request_params.merge(
              messages: normalized_messages
            )

            # Add temperature based on model capabilities  
            unless o1_model?(model)
              temperature = case model
                            when /^gpt-5/, /^gpt-4o/
                              1.0 # GPT-5 and GPT-4o models only support default temperature of 1.0
                            else
                              0.0 # Near-deterministic for other models (0.0 no longer universally supported)
                            end
              request_params[:temperature] = temperature
            end

            # Add response format if provided by strategy
            if response_format
              request_params[:response_format] = response_format
            elsif @structured_outputs_enabled && signature && supports_structured_outputs?
              # Legacy behavior for backward compatibility
              response_format = DSPy::OpenAI::LM::SchemaConverter.to_openai_format(signature)
              request_params[:response_format] = response_format
            end

            # Add streaming if block provided
            if block_given?
              request_params[:stream] = proc do |chunk, _bytesize|
                block.call(chunk) if chunk.dig("choices", 0, "delta", "content")
              end
            end

            begin
              response = @client.chat.completions.create(**request_params)

              if response.respond_to?(:error) && response.error
                raise DSPy::LM::AdapterError, "OpenAI API error: #{response.error}"
              end

              choice = response.choices.first
              message = choice.message
              content = message.content
              usage = response.usage

              # Handle structured output refusals
              if message.respond_to?(:refusal) && message.refusal
                raise DSPy::LM::AdapterError, "OpenAI refused to generate output: #{message.refusal}"
              end

              # Convert usage data to typed struct
              usage_struct = DSPy::LM::UsageFactory.create('openai', usage)

              # Create typed metadata
              metadata = DSPy::LM::ResponseMetadataFactory.create('openai', {
                model: model,
                response_id: response.id,
                created: response.created,
                structured_output: @structured_outputs_enabled && signature && supports_structured_outputs?,
                system_fingerprint: response.system_fingerprint,
                finish_reason: choice.finish_reason
              })

              DSPy::LM::Response.new(
                content: content,
                usage: usage_struct,
                metadata: metadata
              )
            rescue => e
              # Check for specific error types and messages
              error_msg = e.message.to_s

              # Try to parse error body if it looks like JSON
              error_body = if error_msg.start_with?('{')
                             JSON.parse(error_msg) rescue nil
                           elsif e.respond_to?(:response) && e.response
                             e.response[:body] rescue nil
                           end

              # Check for specific image-related errors
              if error_msg.include?('image_parse_error') || error_msg.include?('unsupported image')
                raise DSPy::LM::AdapterError, "Image processing failed: #{error_msg}. Ensure your image is a valid PNG, JPEG, GIF, or WebP format and under 5MB."
              elsif error_msg.include?('rate') && error_msg.include?('limit')
                raise DSPy::LM::AdapterError, "OpenAI rate limit exceeded: #{error_msg}. Please wait and try again."
              elsif error_msg.include?('authentication') || error_msg.include?('API key') || error_msg.include?('Unauthorized')
                raise DSPy::LM::AdapterError, "OpenAI authentication failed: #{error_msg}. Check your API key."
              elsif error_body && error_body.dig('error', 'message')
                raise DSPy::LM::AdapterError, "OpenAI API error: #{error_body.dig('error', 'message')}"
              else
                # Generic error handling
                raise DSPy::LM::AdapterError, "OpenAI adapter error: #{e.message}"
              end
            end
          end

          protected

          # Allow subclasses to override request params (add headers, etc)
          def default_request_params
            {
              model: model
            }
          end

          private

          def supports_structured_outputs?
            DSPy::OpenAI::LM::SchemaConverter.supports_structured_outputs?(model)
          end

          # Check if model is an O1 reasoning model (includes O1, O3, O4 series)
          def o1_model?(model_name)
            model_name.match?(/^o[134](-.*)?$/)
          end

          # Handle O1 model message restrictions
          def handle_o1_messages(messages)
            messages.map do |msg|
              # Convert system messages to user messages for O1 models
              if msg[:role] == 'system'
                {
                  role: 'user',
                  content: "Instructions: #{msg[:content]}"
                }
              else
                msg
              end
            end
          end
        end
      end
    end
  end
end
