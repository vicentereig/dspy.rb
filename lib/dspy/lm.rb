# frozen_string_literal: true

require 'sorbet-runtime'
require 'async'
require 'securerandom'

# Load adapter infrastructure
require_relative 'lm/errors'
require_relative 'lm/response'
require_relative 'lm/adapter'
require_relative 'lm/adapter_factory'

# Load instrumentation

# Load strategy system
require_relative 'lm/chat_strategy'
require_relative 'lm/json_strategy'

# Load message builder and message types
require_relative 'lm/message'
require_relative 'lm/message_builder'
require_relative 'structured_outputs_prompt'
require_relative 'schema/sorbet_toon_adapter'

module DSPy
  class LM
    extend T::Sig
    attr_reader :model_id, :api_key, :model, :provider, :adapter, :schema_format, :data_format

    def initialize(model_id, api_key: nil, schema_format: :json, data_format: :json, **options)
      @model_id = model_id
      @api_key = api_key
      @schema_format = schema_format
      @data_format = data_format

      # Parse provider and model from model_id
      @provider, @model = parse_model_id(model_id)

      # Create appropriate adapter with options
      @adapter = AdapterFactory.create(model_id, api_key: api_key, **options)
    end

    def chat(inference_module, input_values, &block)
      # Capture the current DSPy context before entering Sync block
      parent_context = DSPy::Context.current
      
      Sync do
        # Isolate fiber context while preserving trace/module ancestry
        Fiber[:dspy_context] = DSPy::Context.fork_context(parent_context)
        
        signature_class = inference_module.signature_class
        
        # Build messages from inference module
        messages = build_messages(inference_module, input_values)
        
        # Execute with instrumentation
        response = instrument_lm_request(messages, signature_class.name) do
          chat_with_strategy(messages, signature_class, &block)
        end

        # Parse response (no longer needs separate instrumentation)
        parsed_result = parse_response(response, input_values, signature_class)
        
        parsed_result
      end
    end

    def raw_chat(messages = nil, &block)
      # Support both array format and builder DSL
      if block_given? && messages.nil?
        # DSL mode - block is for building messages
        builder = MessageBuilder.new
        yield builder
        messages = builder.messages
        streaming_block = nil
      else
        # Array mode - block is for streaming
        messages ||= []
        streaming_block = block
      end
      
      # Normalize and validate messages
      messages = normalize_messages(messages)
      
      # Execute with instrumentation
      execute_raw_chat(messages, &streaming_block)
    end

    private

    def chat_with_strategy(messages, signature_class, &block)
      # Choose strategy based on whether we need JSON extraction
      strategy = if signature_class
        JSONStrategy.new(adapter, signature_class)
      else
        ChatStrategy.new(adapter)
      end

      # Execute with the selected strategy (no retry, no fallback)
      execute_chat_with_strategy(messages, signature_class, strategy, &block)
    end

    def execute_chat_with_strategy(messages, signature_class, strategy, &block)
      # Convert messages to hash format for strategy and adapter
      hash_messages = messages_to_hash_array(messages)
      
      # Prepare request with strategy-specific modifications
      request_params = {}
      strategy.prepare_request(hash_messages.dup, request_params)
      
      # Make the request
      response = if request_params.any?
        # Pass additional parameters if strategy added them
        adapter.chat(messages: hash_messages, signature: signature_class, **request_params, &block)
      else
        adapter.chat(messages: hash_messages, signature: signature_class, &block)
      end
      
      # Let strategy handle JSON extraction if needed
      if signature_class
        extracted_json = strategy.extract_json(response)
        if extracted_json && extracted_json != response.content
          # Create a new response with extracted JSON
          response = Response.new(
            content: extracted_json,
            usage: response.usage,
            metadata: response.metadata
          )
        end
      end
      
      response
    end

    def parse_model_id(model_id)
      unless model_id.include?('/')
        raise ArgumentError, "model_id must include provider (e.g., 'openai/gpt-4', 'anthropic/claude-3'). Legacy format without provider is no longer supported."
      end
      
      provider, model = model_id.split('/', 2)
      [provider, model]
    end

    def build_messages(inference_module, input_values)
      messages = []

      # Determine if structured outputs will be used and wrap prompt if so
      base_prompt = inference_module.prompt
      prompt = if will_use_structured_outputs?(inference_module.signature_class, data_format: base_prompt.data_format)
        StructuredOutputsPrompt.new(**base_prompt.to_h)
      else
        base_prompt
      end

      # Add system message
      system_prompt = prompt.render_system_prompt
      if system_prompt
        messages << Message.new(
          role: Message::Role::System,
          content: system_prompt
        )
      end

      # Add user message
      user_prompt = prompt.render_user_prompt(input_values)
      messages << Message.new(
        role: Message::Role::User,
        content: user_prompt
      )

      messages
    end

    def will_use_structured_outputs?(signature_class, data_format: nil)
      return false unless signature_class
      return false if data_format == :toon

      adapter_class_name = adapter.class.name

      if adapter_class_name.include?('OpenAIAdapter') || adapter_class_name.include?('OllamaAdapter')
        begin
          require "dspy/openai"
        rescue LoadError
          msg = <<~MSG
            Install the openai gem to enable support for this adapter.
            Add `gem 'dspy-openai'` to your Gemfile and run `bundle install`.
          MSG
          raise DSPy::LM::MissingAdapterError, msg
        end

        adapter.instance_variable_get(:@structured_outputs_enabled) &&
          DSPy::OpenAI::LM::SchemaConverter.supports_structured_outputs?(adapter.model)
      elsif adapter_class_name.include?('GeminiAdapter')
        begin
          require "dspy/gemini"
        rescue LoadError
          msg = <<~MSG
            Install the gem to enable Gemini support.
            Add `gem 'dspy-gemini'` to your Gemfile and run `bundle install`.
          MSG
          raise DSPy::LM::MissingAdapterError, msg
        end

        adapter.instance_variable_get(:@structured_outputs_enabled) &&
          DSPy::Gemini::LM::SchemaConverter.supports_structured_outputs?(adapter.model)
      elsif adapter_class_name.include?('AnthropicAdapter')
        begin
          require "dspy/anthropic"
        rescue LoadError
          msg = <<~MSG
            Install the gem to enable Claude support.
            Add `gem 'dspy-anthropic'` to your Gemfile and run `bundle install`.
          MSG
          raise DSPy::LM::MissingAdapterError, msg
        end

        structured_outputs_enabled = adapter.instance_variable_get(:@structured_outputs_enabled)
        structured_outputs_enabled.nil? ? true : structured_outputs_enabled
      else
        false
      end
    end

    def parse_response(response, input_values, signature_class)
      if data_format == :toon
        payload = DSPy::Schema::SorbetToonAdapter.parse_output(signature_class, response.content.to_s)
        return normalize_output_payload(payload)
      end

      content = response.content

      begin
        JSON.parse(content)
      rescue JSON::ParserError => e
        error_details = {
          original_content: response.content,
          provider: provider,
          model: model
        }

        DSPy.logger.debug("JSON parsing failed: #{error_details}")
        raise "Failed to parse LLM response as JSON: #{e.message}. Original content length: #{response.content&.length || 0} chars"
      end
    end

    def normalize_output_payload(payload)
      case payload
      when T::Struct
        payload.class.props.each_with_object({}) do |(name, _), memo|
          memo[name.to_s] = normalize_output_payload(payload.send(name))
        end
      when Hash
        payload.each_with_object({}) do |(key, value), memo|
          memo[key.to_s] = normalize_output_payload(value)
        end
      when Array
        payload.map { |item| normalize_output_payload(item) }
      when Set
        payload.map { |item| normalize_output_payload(item) }
      else
        payload
      end
    end

    # Common instrumentation method for LM requests
    def instrument_lm_request(messages, signature_class_name, &execution_block)
      # Prepare input for tracing - convert messages to JSON for input tracking
      input_messages = messages.map do |m|
        if m.is_a?(Message)
          { role: m.role, content: m.content }
        else
          m
        end
      end
      input_json = input_messages.to_json
      
      # Wrap LLM call in span tracking
      response = DSPy::Context.with_span(
        operation: 'llm.generate',
        **DSPy::ObservationType::Generation.langfuse_attributes,
        'langfuse.observation.input' => input_json,
        'gen_ai.system' => provider,
        'gen_ai.request.model' => model,
        'gen_ai.prompt' => input_json,
        'dspy.signature' => signature_class_name
      ) do |span|
        result = execution_block.call

        # Add output and usage data directly to span
        if span && result
          # Add completion output
          if result.content
            span.set_attribute('langfuse.observation.output', result.content)
            span.set_attribute('gen_ai.completion', result.content)
          end
          
          # Add response model if available
          if result.respond_to?(:metadata) && result.metadata&.model
            span.set_attribute('gen_ai.response.model', result.metadata.model)
          end
          
          # Add token usage
          if result.respond_to?(:usage) && result.usage
            usage = result.usage
            span.set_attribute('gen_ai.usage.prompt_tokens', usage.input_tokens) if usage.input_tokens
            span.set_attribute('gen_ai.usage.completion_tokens', usage.output_tokens) if usage.output_tokens
            span.set_attribute('gen_ai.usage.total_tokens', usage.total_tokens) if usage.total_tokens
          end
        end

        emit_token_usage(result, signature_class_name)

        result
      end
      
      response
    end

    # Common method to emit token usage events
    def emit_token_usage(response, signature_class_name)
      token_usage = extract_token_usage(response)
      
      if token_usage.any?
        event_attributes = token_usage.merge({
          'gen_ai.system' => provider,
          'gen_ai.request.model' => model,
          'dspy.signature' => signature_class_name
        })
        
        # Add timing and request correlation if available
        context = DSPy::Context.current
        request_id = context[:request_id]
        start_time = context[:request_start_time]
        
        if request_id
          event_attributes['request_id'] = request_id
        end
        
        if start_time
          duration = Time.now - start_time
          event_attributes['duration'] = duration
        end
        
        DSPy.event('lm.tokens', event_attributes)
      end
      
      token_usage
    end

    private

    # Extract token usage from API responses
    sig { params(response: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def extract_token_usage(response)
      return {} unless response&.usage
      
      # Handle Usage struct objects
      if response.usage.respond_to?(:input_tokens)
        return {
          input_tokens: response.usage.input_tokens,
          output_tokens: response.usage.output_tokens,
          total_tokens: response.usage.total_tokens
        }.compact
      end
      
      # Handle hash-based usage (for VCR compatibility)
      usage = response.usage
      return {} unless usage.is_a?(Hash)
      
      case provider.to_s.downcase
      when 'openai'
        {
          input_tokens: usage[:prompt_tokens] || usage['prompt_tokens'],
          output_tokens: usage[:completion_tokens] || usage['completion_tokens'], 
          total_tokens: usage[:total_tokens] || usage['total_tokens']
        }.compact
      when 'anthropic'
        {
          input_tokens: usage[:input_tokens] || usage['input_tokens'],
          output_tokens: usage[:output_tokens] || usage['output_tokens'],
          total_tokens: (usage[:input_tokens] || usage['input_tokens'] || 0) +
                       (usage[:output_tokens] || usage['output_tokens'] || 0)
        }.compact
      else
        {}
      end
    end

    def execute_raw_chat(messages, &streaming_block)
      # Generate unique request ID for tracking
      request_id = SecureRandom.hex(8)
      start_time = Time.now

      DSPy::Context.with_request(request_id, start_time) do
        response = instrument_lm_request(messages, 'RawPrompt') do
          # Convert messages to hash format for adapter
          hash_messages = messages_to_hash_array(messages)
          # Direct adapter call, no strategies or JSON parsing
          adapter.chat(messages: hash_messages, signature: nil, &streaming_block)
        end

        # Return raw response content, not parsed JSON
        response.content
      end
    end
    
    # Convert messages to normalized Message objects
    def normalize_messages(messages)
      # Validate array format first
      unless messages.is_a?(Array)
        raise ArgumentError, "messages must be an array"
      end
      
      return messages if messages.all? { |m| m.is_a?(Message) }
      
      # Convert hash messages to Message objects
      normalized = []
      messages.each_with_index do |msg, index|
        if msg.is_a?(Message)
          normalized << msg
        elsif msg.is_a?(Hash) || msg.respond_to?(:to_h)
          data = msg.is_a?(Hash) ? msg : msg.to_h
          unless data.is_a?(Hash)
            raise ArgumentError, "Message at index #{index} must be a Message object or hash with :role and :content"
          end

          normalized_hash = data.transform_keys(&:to_sym)
          unless normalized_hash.key?(:role) && normalized_hash.key?(:content)
            raise ArgumentError, "Message at index #{index} must have :role and :content"
          end

          role = normalized_hash[:role].to_s
          valid_roles = %w[system user assistant]
          unless valid_roles.include?(role)
            raise ArgumentError, "Invalid role at index #{index}: #{normalized_hash[:role]}. Must be one of: #{valid_roles.join(', ')}"
          end

          message = MessageFactory.create(normalized_hash)
          if message.nil?
            raise ArgumentError, "Failed to create Message from hash at index #{index}"
          end

          normalized << message
        else
          raise ArgumentError, "Message at index #{index} must be a Message object or hash with :role and :content"
        end
      end
      
      normalized
    end
    
    # Convert Message objects to hash array for adapters
    def messages_to_hash_array(messages)
      messages.map do |msg|
        if msg.is_a?(Message)
          msg.to_h
        else
          msg
        end
      end
    end
  end
end
