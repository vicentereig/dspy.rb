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
          attr_reader :provider

          def initialize(model:, api_key: nil, **options)
            @api_key = api_key
            @options = options
            @structured_outputs_enabled = options.fetch(:structured_outputs, true)
            @provider_override = options[:provider] # Optional provider override

            # Detect provider eagerly (matches OpenAI/Anthropic/Gemini adapters)
            @provider = detect_provider(model)

            # Determine if we should use global RubyLLM config or create scoped context
            @use_global_config = should_use_global_config?(api_key, options)

            super(model: model, api_key: api_key)

            # Only validate API key if not using global config
            unless @use_global_config
              validate_api_key_for_provider!(api_key)
            end
          end

          # Returns the context - either scoped or global
          def context
            @context ||= @use_global_config ? nil : create_context(@api_key)
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
            raise DSPy::LM::MissingAPIKeyError.new(provider)
          rescue ::RubyLLM::RateLimitError => e
            raise DSPy::LM::AdapterError, "Rate limit exceeded for #{provider}: #{e.message}"
          rescue ::RubyLLM::ModelNotFoundError => e
            raise DSPy::LM::AdapterError, "Model not found: #{e.message}. Check available models with RubyLLM.models.all"
          rescue ::RubyLLM::BadRequestError => e
            raise DSPy::LM::AdapterError, "Invalid request to #{provider}: #{e.message}"
          rescue ::RubyLLM::ConfigurationError => e
            raise DSPy::LM::ConfigurationError, "RubyLLM configuration error: #{e.message}"
          rescue ::RubyLLM::Error => e
            raise DSPy::LM::AdapterError, "RubyLLM error (#{provider}): #{e.message}"
          end

          private

          # Detect provider from model info or use override
          # Called eagerly at initialization to match other adapters' behavior
          def detect_provider(model_id)
            return @provider_override.to_s if @provider_override

            # Try to find model in RubyLLM registry to get provider
            begin
              model_info = ::RubyLLM.models.find(model_id)
              model_info.provider.to_s
            rescue ::RubyLLM::ModelNotFoundError
              # If model not in registry, try to infer from model name patterns
              infer_provider_from_model_name(model_id)
            end
          end

          # Infer provider from common model name patterns
          def infer_provider_from_model_name(model_name)
            case model_name.downcase
            when /^gpt/, /^o[134]/, /^davinci/, /^text-/
              'openai'
            when /^claude/
              'anthropic'
            when /^gemini/, /^palm/
              'gemini'
            when /^llama/, /^mistral/, /^mixtral/, /^codellama/
              'ollama' # Default local models to ollama
            when /^deepseek/
              'deepseek'
            else
              'openai' # Default fallback
            end
          end

          # Check if we should use RubyLLM's global configuration
          def should_use_global_config?(api_key, options)
            # Use global config when:
            # - No api_key provided
            # - No provider-specific options that require scoped context
            return false if api_key
            return false if options[:base_url]
            return false if options[:secret_key]  # Bedrock
            return false if options[:region]      # Bedrock
            return false if options[:location]    # VertexAI
            return false if options[:timeout]
            return false if options[:max_retries]

            true
          end

          # Validate API key for providers that require it
          def validate_api_key_for_provider!(api_key)
            # Ollama and some local providers don't require API keys
            return if provider_allows_no_api_key?

            validate_api_key!(api_key, provider)
          end

          def provider_allows_no_api_key?
            %w[ollama gpustack].include?(provider)
          end

          def create_context(api_key)
            ::RubyLLM.context do |config|
              configure_provider(config, api_key)
              configure_connection(config)
            end
          end

          def configure_provider(config, api_key)
            detected = provider

            case detected
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
              # For unknown providers, try openai-compatible configuration
              config.openai_api_key = api_key
              config.openai_api_base = @options[:base_url] if @options[:base_url]
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
            chat_options = { model: model }

            # If provider is explicitly overridden, pass it to RubyLLM
            if @provider_override
              chat_options[:provider] = @provider_override.to_sym
              chat_options[:assume_model_exists] = true
            end

            # Use global RubyLLM config or scoped context
            if @use_global_config
              ::RubyLLM.chat(**chat_options)
            else
              context.chat(**chat_options)
            end
          end

          def standard_response(chat_instance, messages, signature)
            chat_instance = prepare_chat_instance(chat_instance, messages, signature)
            content, attachments = prepare_message_content(messages)
            return build_empty_response unless content

            response = send_message(chat_instance, content, attachments)
            map_response(response)
          end

          def stream_response(chat_instance, messages, signature, &block)
            chat_instance = prepare_chat_instance(chat_instance, messages, signature)
            content, attachments = prepare_message_content(messages)
            return build_empty_response unless content

            response = send_message(chat_instance, content, attachments, &block)
            map_response(response)
          end

          # Common setup: apply system instructions and optional schema
          def prepare_chat_instance(chat_instance, messages, signature)
            system_message = messages.find { |m| m[:role] == 'system' }
            chat_instance = chat_instance.with_instructions(system_message[:content]) if system_message

            if signature && @structured_outputs_enabled
              schema = build_json_schema(signature)
              chat_instance = chat_instance.with_schema(schema) if schema
            end

            chat_instance
          end

          # Extract content from last user message
          # Note: RubyLLM's Chat API is designed for conversational flows where
          # history is built via multiple ask() calls. For DSPy's single-shot
          # predictions, we extract only the last user message. Multi-turn
          # conversation history is managed at DSPy's agent level (ReAct, etc.).
          def prepare_message_content(messages)
            last_user_message = messages.reverse.find { |m| m[:role] == 'user' }
            return [nil, []] unless last_user_message

            extract_content_and_attachments(last_user_message)
          end

          # Send message with optional streaming block
          def send_message(chat_instance, content, attachments, &block)
            if block_given?
              if attachments.any?
                chat_instance.ask(content, with: attachments) do |chunk|
                  block.call(chunk.content) if chunk.content
                end
              else
                chat_instance.ask(content) do |chunk|
                  block.call(chunk.content) if chunk.content
                end
              end
            else
              if attachments.any?
                chat_instance.ask(content, with: attachments)
              else
                chat_instance.ask(content)
              end
            end
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
              model: response.model_id || model,
              provider: provider
            })
          end

          def build_empty_response
            DSPy::LM::Response.new(
              content: '',
              usage: DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0),
              metadata: DSPy::LM::ResponseMetadataFactory.create('ruby_llm', {
                model: model,
                provider: provider
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
            DSPy::LM::VisionModels.validate_vision_support!(provider, model)
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
                      image.validate_for_provider!(provider)
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
