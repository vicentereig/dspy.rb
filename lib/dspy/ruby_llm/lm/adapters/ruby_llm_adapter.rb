# frozen_string_literal: true

require 'uri'
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

          # Options that require a scoped context instead of global RubyLLM config
          SCOPED_OPTIONS = %i[base_url timeout max_retries].freeze

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

            # Validate base_url if provided
            validate_base_url!(@options[:base_url])
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
              normalized_messages = format_multimodal_messages(normalized_messages, provider)
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

          # Detect provider from RubyLLM's model registry or use explicit override
          def detect_provider(model_id)
            return @provider_override.to_s if @provider_override

            model_info = ::RubyLLM.models.find(model_id)
            model_info.provider.to_s
          rescue ::RubyLLM::ModelNotFoundError
            raise DSPy::LM::ConfigurationError,
              "Model '#{model_id}' not found in RubyLLM registry. " \
              "Use provider: option to specify explicitly, or run RubyLLM.models.refresh!"
          end

          # Check if we should use RubyLLM's global configuration
          # Uses global config when no api_key and no provider-specific options provided
          def should_use_global_config?(api_key, options)
            api_key.nil? && (options.keys & SCOPED_OPTIONS).empty?
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

          def validate_base_url!(url)
            return if url.nil?

            uri = URI.parse(url)
            unless %w[http https].include?(uri.scheme)
              raise DSPy::LM::ConfigurationError, "base_url must use http or https scheme"
            end
          rescue URI::InvalidURIError
            raise DSPy::LM::ConfigurationError, "Invalid base_url format: #{url}"
          end

          def create_context(api_key)
            ::RubyLLM.context do |config|
              configure_provider(config, api_key)
              configure_connection(config)
            end
          end

          # Configure RubyLLM using convention: {provider}_api_key and {provider}_api_base
          # For providers with non-standard auth (bedrock, vertexai), configure RubyLLM globally
          def configure_provider(config, api_key)
            key_method = "#{provider}_api_key="
            config.send(key_method, api_key) if api_key && config.respond_to?(key_method)

            base_method = "#{provider}_api_base="
            config.send(base_method, @options[:base_url]) if @options[:base_url] && config.respond_to?(base_method)
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

          # Common setup: apply system instructions, build conversation history, and optional schema
          def prepare_chat_instance(chat_instance, messages, signature)
            # First, handle system messages via with_instructions for proper system prompt handling
            system_message = messages.find { |m| m[:role] == 'system' }
            chat_instance = chat_instance.with_instructions(system_message[:content]) if system_message

            # Build conversation history by adding all non-system messages except the last user message
            # The last user message will be passed to ask() to get the response
            messages_to_add = messages.reject { |m| m[:role] == 'system' }

            # Find the index of the last user message
            last_user_index = messages_to_add.rindex { |m| m[:role] == 'user' }

            if last_user_index && last_user_index > 0
              # Add all messages before the last user message to build history
              messages_to_add[0...last_user_index].each do |msg|
                content, attachments = extract_content_and_attachments(msg)
                next unless content

                # Add message with appropriate role
                if attachments.any?
                  chat_instance.add_message(role: msg[:role].to_sym, content: content, attachments: attachments)
                else
                  chat_instance.add_message(role: msg[:role].to_sym, content: content)
                end
              end
            end

            if signature && @structured_outputs_enabled
              schema = build_json_schema(signature)
              chat_instance = chat_instance.with_schema(schema) if schema
            end

            chat_instance
          end

          # Extract content from last user message
          # RubyLLM's Chat API builds conversation history via add_message() for previous turns,
          # and the last user message is passed to ask() to get the response.
          def prepare_message_content(messages)
            last_user_message = messages.reverse.find { |m| m[:role] == 'user' }
            return [nil, []] unless last_user_message

            extract_content_and_attachments(last_user_message)
          end

          # Send message with optional streaming block
          def send_message(chat_instance, content, attachments, &block)
            kwargs = attachments.any? ? { with: attachments } : {}

            if block_given?
              chat_instance.ask(content, **kwargs) do |chunk|
                block.call(chunk.content) if chunk.content
              end
            else
              chat_instance.ask(content, **kwargs)
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
              underlying_provider: provider
            })
          end

          def build_empty_response
            DSPy::LM::Response.new(
              content: '',
              usage: DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0),
              metadata: DSPy::LM::ResponseMetadataFactory.create('ruby_llm', {
                model: model,
                underlying_provider: provider
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

            @normalized_schema_cache ||= {}
            cache_key = schema.hash

            @normalized_schema_cache[cache_key] ||= begin
              duped = deep_dup(schema)
              add_additional_properties_false(duped)
              duped.freeze
            end
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
        end
      end
    end
  end
end
