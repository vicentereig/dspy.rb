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

# Load strategy system
require_relative 'lm/strategy_selector'
require_relative 'lm/retry_handler'

# Load message builder
require_relative 'lm/message_builder'

module DSPy
  class LM
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
      
      # Instrument response parsing
      if should_emit_lm_events?
        parsed_result = Instrumentation.instrument('dspy.lm.response.parsed', {
          signature_class: signature_class.name,
          provider: provider,
          response_length: response.content&.length || 0
        }) do
          parse_response(response, input_values, signature_class)
        end
      else
        parsed_result = parse_response(response, input_values, signature_class)
      end
      
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
      
      # Validate messages format
      validate_messages!(messages)
      
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
      # Prepare request with strategy-specific modifications
      request_params = {}
      strategy.prepare_request(messages.dup, request_params)
      
      # Make the request
      response = if request_params.any?
        # Pass additional parameters if strategy added them
        adapter.chat(messages: messages, signature: signature_class, **request_params, &block)
      else
        adapter.chat(messages: messages, signature: signature_class, &block)
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
      messages << { role: 'system', content: system_prompt } if system_prompt
      
      # Add user message
      user_prompt = inference_module.user_signature(input_values)
      messages << { role: 'user', content: user_prompt }
      
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
      input_text = messages.map { |m| m[:content] }.join(' ')
      input_size = input_text.length
      
      response = nil
      
      if should_emit_lm_events?
        # Emit dspy.lm.request event
        response = Instrumentation.instrument('dspy.lm.request', {
          gen_ai_operation_name: 'chat',
          gen_ai_system: provider,
          gen_ai_request_model: model,
          signature_class: signature_class_name,
          provider: provider,
          adapter_class: adapter.class.name,
          input_size: input_size
        }, &execution_block)
        
        # Extract and emit token usage
        emit_token_usage(response, signature_class_name)
      else
        # Consolidated mode: execute without instrumentation
        response = execution_block.call
      end
      
      response
    end

    # Common method to emit token usage events
    def emit_token_usage(response, signature_class_name)
      token_usage = Instrumentation::TokenTracker.extract_token_usage(response, provider)
      
      if token_usage.any?
        Instrumentation.emit('dspy.lm.tokens', token_usage.merge({
          gen_ai_system: provider,
          gen_ai_request_model: model,
          signature_class: signature_class_name
        }))
      end
      
      token_usage
    end

    def validate_messages!(messages)
      unless messages.is_a?(Array)
        raise ArgumentError, "messages must be an array"
      end
      
      valid_roles = %w[system user assistant]
      
      messages.each do |message|
        unless message.is_a?(Hash) && message.key?(:role) && message.key?(:content)
          raise ArgumentError, "Each message must have :role and :content"
        end
        
        unless valid_roles.include?(message[:role])
          raise ArgumentError, "Invalid role: #{message[:role]}. Must be one of: #{valid_roles.join(', ')}"
        end
      end
    end

    def execute_raw_chat(messages, &streaming_block)
      response = instrument_lm_request(messages, 'RawPrompt') do
        # Direct adapter call, no strategies or JSON parsing
        adapter.chat(messages: messages, signature: nil, &streaming_block)
      end
      
      # Return raw response content, not parsed JSON
      response.content
    end
  end
end
