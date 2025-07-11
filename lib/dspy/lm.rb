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
      
      # Calculate input size for monitoring
      input_text = messages.map { |m| m[:content] }.join(' ')
      input_size = input_text.length
      
      # Use smart consolidation: emit LM events only when not in nested context
      response = nil
      token_usage = {}
      
      if should_emit_lm_events?
        # Emit all LM events when not in nested context
        response = Instrumentation.instrument('dspy.lm.request', {
          gen_ai_operation_name: 'chat',
          gen_ai_system: provider,
          gen_ai_request_model: model,
          signature_class: signature_class.name,
          provider: provider,
          adapter_class: adapter.class.name,
          input_size: input_size
        }) do
          chat_with_strategy(messages, signature_class, &block)
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
      else
        # Consolidated mode: execute without nested instrumentation
        response = chat_with_strategy(messages, signature_class, &block)
        token_usage = Instrumentation::TokenTracker.extract_token_usage(response, provider)
        parsed_result = parse_response(response, input_values, signature_class)
      end
      
      parsed_result
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
      if signature_class && response.content
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
  end
end
