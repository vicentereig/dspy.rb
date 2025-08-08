# frozen_string_literal: true

require 'sorbet-runtime'

# Load adapter infrastructure
require_relative 'lm/errors'
require_relative 'lm/response'
require_relative 'lm/adapter'
require_relative 'lm/adapter_factory'

# Load instrumentation

# Load adapters
require_relative 'lm/adapters/openai_adapter'
require_relative 'lm/adapters/anthropic_adapter'
require_relative 'lm/adapters/ollama_adapter'

# Load strategy system
require_relative 'lm/strategy_selector'
require_relative 'lm/retry_handler'

# Load message builder and message types
require_relative 'lm/message'
require_relative 'lm/message_builder'

module DSPy
  class LM
    extend T::Sig
    attr_reader :model_id, :api_key, :model, :provider, :adapter

    def initialize(model_id, api_key: nil, **options)
      @model_id = model_id
      @api_key = api_key
      
      # Parse provider and model from model_id
      @provider, @model = parse_model_id(model_id)
      
      # Create appropriate adapter with options
      @adapter = AdapterFactory.create(model_id, api_key: api_key, **options)
    end

    def chat(inference_module, input_values, &block)
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
      # Select the best strategy for JSON extraction
      strategy_selector = StrategySelector.new(adapter, signature_class)
      initial_strategy = strategy_selector.select
      
      if DSPy.config.structured_outputs.retry_enabled && signature_class
        # Use retry handler for JSON responses
        retry_handler = RetryHandler.new(adapter, signature_class)
        
        retry_handler.with_retry(initial_strategy) do |strategy|
          execute_chat_with_strategy(messages, signature_class, strategy, &block)
        end
      else
        # No retry logic, just execute once
        execute_chat_with_strategy(messages, signature_class, initial_strategy, &block)
      end
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

    # Determines if LM-level events should be emitted using smart consolidation
    def should_emit_lm_events?
      # Emit LM events only if we're not in a nested context (smart consolidation)
      !is_nested_context?
    end

    # Determines if we're in a nested context where higher-level events are being emitted
    def is_nested_context?
      caller_locations = caller_locations(1, 30)
      return false if caller_locations.nil?
      
      # Look for higher-level DSPy modules in the call stack
      # We consider ChainOfThought and ReAct as higher-level modules
      higher_level_modules = caller_locations.select do |loc|
        loc.path.include?('chain_of_thought') || 
        loc.path.include?('re_act') ||
        loc.path.include?('react')
      end
      
      # If we have higher-level modules in the call stack, we're in a nested context
      higher_level_modules.any?
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
      
      # Add system message
      system_prompt = inference_module.system_signature
      if system_prompt
        messages << Message.new(
          role: Message::Role::System,
          content: system_prompt
        )
      end
      
      # Add user message
      user_prompt = inference_module.user_signature(input_values)
      messages << Message.new(
        role: Message::Role::User,
        content: user_prompt
      )
      
      messages
    end

    def parse_response(response, input_values, signature_class)
      # Try to parse the response as JSON
      content = response.content

      begin
        json_payload = JSON.parse(content)

        # For Sorbet signatures, just return the parsed JSON
        # The Predict will handle validation
        json_payload
      rescue JSON::ParserError => e
        # Enhanced error message with debugging information
        error_details = {
          original_content: response.content,
          provider: provider,
          model: model
        }
        
        DSPy.logger.debug("JSON parsing failed: #{error_details}")
        raise "Failed to parse LLM response as JSON: #{e.message}. Original content length: #{response.content&.length || 0} chars"
      end
    end

    # Common instrumentation method for LM requests
    def instrument_lm_request(messages, signature_class_name, &execution_block)
      # Handle both Message objects and hash format
      input_text = messages.map do |m|
        if m.is_a?(Message)
          m.content
        else
          m[:content]
        end
      end.join(' ')
      input_size = input_text.length
      
      # Wrap LLM call in span tracking
      response = DSPy::Context.with_span(
        operation: 'llm.generate',
        'gen_ai.system' => provider,
        'gen_ai.request.model' => model,
        'dspy.signature' => signature_class_name
      ) do
        result = execution_block.call
        
        # Add usage data if available
        if result.respond_to?(:usage) && result.usage
          usage = result.usage
          DSPy.log('span.attributes',
            span_id: DSPy::Context.current[:span_stack].last,
            'gen_ai.response.model' => result.respond_to?(:model) ? result.model : nil,
            'gen_ai.usage.prompt_tokens' => usage.respond_to?(:input_tokens) ? usage.input_tokens : nil,
            'gen_ai.usage.completion_tokens' => usage.respond_to?(:output_tokens) ? usage.output_tokens : nil,
            'gen_ai.usage.total_tokens' => usage.respond_to?(:total_tokens) ? usage.total_tokens : nil
          )
        end
        
        result
      end
      
      response
    end

    # Common method to emit token usage events
    def emit_token_usage(response, signature_class_name)
      token_usage = extract_token_usage(response)
      
      if token_usage.any?
        DSPy.log('lm.tokens', **token_usage.merge({
          'gen_ai.system' => provider,
          'gen_ai.request.model' => model,
          'dspy.signature' => signature_class_name
        }))
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

    public

    def validate_messages!(messages)
      unless messages.is_a?(Array)
        raise ArgumentError, "messages must be an array"
      end
      
      messages.each_with_index do |message, index|
        # Accept both Message objects and hash format for backward compatibility
        if message.is_a?(Message)
          # Already validated by type system
          next
        elsif message.is_a?(Hash) && message.key?(:role) && message.key?(:content)
          # Legacy hash format - validate role
          valid_roles = %w[system user assistant]
          unless valid_roles.include?(message[:role])
            raise ArgumentError, "Invalid role at index #{index}: #{message[:role]}. Must be one of: #{valid_roles.join(', ')}"
          end
        else
          raise ArgumentError, "Message at index #{index} must be a Message object or hash with :role and :content"
        end
      end
    end

    def execute_raw_chat(messages, &streaming_block)
      response = instrument_lm_request(messages, 'RawPrompt') do
        # Convert messages to hash format for adapter
        hash_messages = messages_to_hash_array(messages)
        # Direct adapter call, no strategies or JSON parsing
        adapter.chat(messages: hash_messages, signature: nil, &streaming_block)
      end
      
      # Return raw response content, not parsed JSON
      response.content
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
        elsif msg.is_a?(Hash)
          # Validate hash has required fields
          unless msg.key?(:role) && msg.key?(:content)
            raise ArgumentError, "Message at index #{index} must have :role and :content"
          end
          
          # Validate role
          valid_roles = %w[system user assistant]
          unless valid_roles.include?(msg[:role])
            raise ArgumentError, "Invalid role at index #{index}: #{msg[:role]}. Must be one of: #{valid_roles.join(', ')}"
          end
          
          # Create Message object
          message = MessageFactory.create(msg)
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
