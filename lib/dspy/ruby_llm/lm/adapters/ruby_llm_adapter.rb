# frozen_string_literal: true

require 'ruby_llm'
require 'dspy/lm/adapter'
require 'dspy/lm/vision_models'

require 'dspy/ruby_llm/guardrails'
DSPy::RubyLLM::Guardrails.ensure_ruby_llm_installed!

module DSPy
  module RubyLLM
    module LM
      module Adapters
        class RubyLLMAdapter < DSPy::LM::Adapter
          # Mapping of DSPy provider names to RubyLLM configuration keys
          PROVIDER_CONFIG_MAP = {
            'openai' => :openai_api_key,
            'anthropic' => :anthropic_api_key,
            'gemini' => :gemini_api_key,
            'bedrock' => :bedrock_api_key,
            'ollama' => :ollama_api_base,
            'openrouter' => :openrouter_api_key,
            'deepseek' => :deepseek_api_key,
            'mistral' => :mistral_api_key,
            'perplexity' => :perplexity_api_key,
            'vertexai' => :vertexai_project_id,
            'gpustack' => :gpustack_api_key
          }.freeze

          attr_reader :provider, :ruby_llm_model, :context

          def initialize(model:, api_key:, **options)
            @provider, @ruby_llm_model = parse_model(model)
            @options = options
            @structured_outputs_enabled = options.fetch(:structured_outputs, true)

            super(model: model, api_key: api_key)
            @context = create_context(api_key)
          end

          def chat(messages:, signature: nil, &block)
            normalized_messages = normalize_messages(messages)

            # Validate vision support if images are present
            if contains_images?(normalized_messages)
              validate_vision_support!
              normalized_messages = format_multimodal_messages(normalized_messages)
            end

            chat_instance = create_chat_instance

            if block_given?
              stream_response(chat_instance, normalized_messages, signature, &block)
            else
              standard_response(chat_instance, normalized_messages, signature)
            end
          rescue ::RubyLLM::UnauthorizedError => e
            raise DSPy::LM::MissingAPIKeyError.new(@provider)
          rescue ::RubyLLM::RateLimitError => e
            raise DSPy::LM::AdapterError, "Rate limit exceeded for #{@provider}: #{e.message}"
          rescue ::RubyLLM::ModelNotFoundError => e
            raise DSPy::LM::AdapterError, "Model not found: #{e.message}. Check available models with RubyLLM.models.all"
          rescue ::RubyLLM::BadRequestError => e
            raise DSPy::LM::AdapterError, "Invalid request to #{@provider}: #{e.message}"
          rescue ::RubyLLM::ConfigurationError => e
            raise DSPy::LM::ConfigurationError, "RubyLLM configuration error: #{e.message}"
          rescue ::RubyLLM::Error => e
            raise DSPy::LM::AdapterError, "RubyLLM error (#{@provider}): #{e.message}"
          end

          private

          def parse_model(model)
            parts = model.split(':', 2)
            unless parts.length == 2
              raise DSPy::LM::ConfigurationError,
                    "Invalid model format '#{model}'. Expected 'provider:model' (e.g., 'openai:gpt-4o', 'anthropic:claude-sonnet-4')"
            end
            parts
          end

          def create_context(api_key)
            ::RubyLLM.context do |config|
              configure_provider(config, api_key)
              configure_connection(config)
            end
          end

          def configure_provider(config, api_key)
            case @provider
            when 'openai'
              config.openai_api_key = api_key
              config.openai_api_base = @options[:base_url] if @options[:base_url]
            when 'anthropic'
              config.anthropic_api_key = api_key
            when 'gemini'
              config.gemini_api_key = api_key
            when 'bedrock'
              configure_bedrock(config, api_key)
            when 'ollama'
              config.ollama_api_base = @options[:base_url] || 'http://localhost:11434'
            when 'openrouter'
              config.openrouter_api_key = api_key
            when 'deepseek'
              config.deepseek_api_key = api_key
            when 'mistral'
              config.mistral_api_key = api_key
            when 'perplexity'
              config.perplexity_api_key = api_key
            when 'vertexai'
              config.vertexai_project_id = api_key
              config.vertexai_location = @options[:location] || 'us-central1'
            when 'gpustack'
              config.gpustack_api_key = api_key
              config.gpustack_api_base = @options[:base_url] if @options[:base_url]
            else
              raise DSPy::LM::ConfigurationError,
                    "Unknown provider '#{@provider}'. Supported: #{PROVIDER_CONFIG_MAP.keys.join(', ')}"
            end
          end

          def configure_bedrock(config, api_key)
            config.bedrock_api_key = api_key
            config.bedrock_secret_key = @options[:secret_key] || ENV['AWS_SECRET_ACCESS_KEY']
            config.bedrock_region = @options[:region] || ENV['AWS_REGION']
            config.bedrock_session_token = @options[:session_token] || ENV['AWS_SESSION_TOKEN']
          end

          def configure_connection(config)
            config.request_timeout = @options[:timeout] if @options[:timeout]
            config.max_retries = @options[:max_retries] if @options[:max_retries]
          end

          def create_chat_instance
            @context.chat(model: @ruby_llm_model)
          end

          def standard_response(chat_instance, messages, signature)
            # Apply system instructions if present
            system_message = messages.find { |m| m[:role] == 'system' }
            chat_instance = chat_instance.with_instructions(system_message[:content]) if system_message

            # Apply structured output schema if signature provided
            if signature && @structured_outputs_enabled
              schema = build_json_schema(signature)
              chat_instance = chat_instance.with_schema(schema) if schema
            end

            # Build conversation history (excluding system messages)
            user_messages = messages.reject { |m| m[:role] == 'system' }

            # Get the last user message to send via ask
            last_user_message = user_messages.reverse.find { |m| m[:role] == 'user' }
            return build_empty_response unless last_user_message

            # Handle multimodal content
            content, attachments = extract_content_and_attachments(last_user_message)

            response = if attachments.any?
                         chat_instance.ask(content, with: attachments)
                       else
                         chat_instance.ask(content)
                       end

            map_response(response)
          end

          def stream_response(chat_instance, messages, signature, &block)
            # Apply system instructions if present
            system_message = messages.find { |m| m[:role] == 'system' }
            chat_instance = chat_instance.with_instructions(system_message[:content]) if system_message

            # Get the last user message
            last_user_message = messages.reverse.find { |m| m[:role] == 'user' }
            return build_empty_response unless last_user_message

            content, attachments = extract_content_and_attachments(last_user_message)

            response = if attachments.any?
                         chat_instance.ask(content, with: attachments) do |chunk|
                           block.call(chunk.content) if chunk.content
                         end
                       else
                         chat_instance.ask(content) do |chunk|
                           block.call(chunk.content) if chunk.content
                         end
                       end

            map_response(response)
          end

          def extract_content_and_attachments(message)
            content = message[:content]
            attachments = []

            if content.is_a?(Array)
              text_parts = []
              content.each do |item|
                case item[:type]
                when 'text'
                  text_parts << item[:text]
                when 'image'
                  # Extract image URL or path
                  image = item[:image]
                  if image.respond_to?(:url)
                    attachments << image.url
                  elsif image.respond_to?(:path)
                    attachments << image.path
                  elsif item[:image_url]
                    attachments << item[:image_url][:url]
                  end
                end
              end
              content = text_parts.join("\n")
            end

            [content.to_s, attachments]
          end

          def map_response(ruby_llm_response)
            DSPy::LM::Response.new(
              content: ruby_llm_response.content.to_s,
              usage: build_usage(ruby_llm_response),
              metadata: build_metadata(ruby_llm_response)
            )
          end

          def build_usage(response)
            input_tokens = response.input_tokens || 0
            output_tokens = response.output_tokens || 0

            DSPy::LM::Usage.new(
              input_tokens: input_tokens,
              output_tokens: output_tokens,
              total_tokens: input_tokens + output_tokens
            )
          end

          def build_metadata(response)
            DSPy::LM::ResponseMetadataFactory.create('ruby_llm', {
              model: response.model_id || @ruby_llm_model,
              provider: @provider
            })
          end

          def build_empty_response
            DSPy::LM::Response.new(
              content: '',
              usage: DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0),
              metadata: DSPy::LM::ResponseMetadataFactory.create('ruby_llm', {
                model: @ruby_llm_model,
                provider: @provider
              })
            )
          end

          def build_json_schema(signature)
            return nil unless signature.respond_to?(:json_schema)

            schema = signature.json_schema
            normalize_schema(schema)
          end

          def normalize_schema(schema)
            return schema unless schema.is_a?(Hash)

            # Deep dup to avoid mutating original
            schema = deep_dup(schema)

            # Add additionalProperties: false for OpenAI compatibility
            add_additional_properties_false(schema)

            schema
          end

          def add_additional_properties_false(schema)
            return unless schema.is_a?(Hash)

            if schema[:type] == 'object' || schema['type'] == 'object'
              schema[:additionalProperties] = false
              schema['additionalProperties'] = false
            end

            # Recursively process nested schemas
            schema.each_value { |v| add_additional_properties_false(v) if v.is_a?(Hash) }

            # Handle arrays with items
            if schema[:items]
              add_additional_properties_false(schema[:items])
            elsif schema['items']
              add_additional_properties_false(schema['items'])
            end
          end

          def deep_dup(obj)
            case obj
            when Hash
              obj.transform_values { |v| deep_dup(v) }
            when Array
              obj.map { |v| deep_dup(v) }
            else
              obj
            end
          end

          def validate_vision_support!
            # RubyLLM handles vision validation internally, but we can add
            # additional DSPy-specific validation here if needed
            DSPy::LM::VisionModels.validate_vision_support!(@provider, @ruby_llm_model)
          rescue DSPy::LM::IncompatibleImageFeatureError
            # If DSPy doesn't know about the model, let RubyLLM handle it
            # RubyLLM has its own model registry with capability detection
          end

          def format_multimodal_messages(messages)
            messages.map do |msg|
              if msg[:content].is_a?(Array)
                formatted_content = msg[:content].map do |item|
                  case item[:type]
                  when 'text'
                    { type: 'text', text: item[:text] }
                  when 'image'
                    # Validate and format image for provider
                    image = item[:image]
                    if image.respond_to?(:validate_for_provider!)
                      image.validate_for_provider!(@provider)
                    end
                    item
                  else
                    item
                  end
                end

                { role: msg[:role], content: formatted_content }
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
