# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'event_payloads'

module DSPy
  module Instrumentation
    # Factory for creating typed event payloads from hash data
    module EventPayloadFactory
      extend T::Sig
      extend self
      
      # Create appropriate event struct based on event name
      sig { params(event_name: String, payload: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def create_event(event_name, payload)
        case event_name
        when 'dspy.lm.request'
          create_lm_request_event(payload)
        when 'dspy.lm.tokens'
          create_lm_tokens_event(payload)
        when 'dspy.lm.response.parsed'
          create_lm_response_parsed_event(payload)
        when 'dspy.predict'
          create_predict_event(payload)
        when 'dspy.predict.validation_error'
          create_predict_validation_error_event(payload)
        when 'dspy.chain_of_thought'
          create_chain_of_thought_event(payload)
        when 'dspy.chain_of_thought.reasoning_complete'
          create_chain_of_thought_reasoning_complete_event(payload)
        when 'dspy.react.iteration'
          create_react_iteration_event(payload)
        when 'dspy.react.tool_call'
          create_react_tool_call_event(payload)
        when 'dspy.react.iteration_complete'
          create_react_iteration_complete_event(payload)
        when 'dspy.react.max_iterations'
          create_react_max_iterations_event(payload)
        when 'dspy.codeact.iteration'
          create_codeact_iteration_event(payload)
        when 'dspy.codeact.code_execution'
          create_codeact_code_execution_event(payload)
        else
          # Return original payload for unhandled events
          payload
        end
      end
      
      private
      
      # LM Request Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(LMRequestEvent) }
      def create_lm_request_event(payload)
        # Extract timestamp, handling both timestamp and timestamp_ns keys
        timestamp = extract_timestamp(payload)
        
        LMRequestEvent.new(
          timestamp: timestamp,
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          gen_ai_operation_name: payload[:gen_ai_operation_name] || 'unknown',
          gen_ai_system: payload[:gen_ai_system] || 'unknown',
          gen_ai_request_model: payload[:gen_ai_request_model] || 'unknown',
          signature_class: payload[:signature_class],
          provider: payload[:provider] || 'unknown',
          adapter_class: payload[:adapter_class] || 'unknown',
          input_size: payload[:input_size] || 0,
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
      
      # Helper to extract timestamp from various formats
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(String) }
      def extract_timestamp(payload)
        if payload[:timestamp]
          payload[:timestamp]
        elsif payload[:timestamp_ns]
          # Convert nanoseconds to ISO8601 for storage in struct
          Time.at(payload[:timestamp_ns] / 1_000_000_000.0).iso8601
        else
          Time.now.iso8601
        end
      end
      
      # LM Tokens Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(LMTokensEvent) }
      def create_lm_tokens_event(payload)
        LMTokensEvent.new(
          timestamp: extract_timestamp(payload),
          status: payload[:status] || 'success',
          input_tokens: payload[:input_tokens] || 0,
          output_tokens: payload[:output_tokens] || 0,
          total_tokens: payload[:total_tokens] || 0,
          gen_ai_system: payload[:gen_ai_system] || 'unknown',
          gen_ai_request_model: payload[:gen_ai_request_model] || 'unknown',
          signature_class: payload[:signature_class]
        )
      end
      
      # LM Response Parsed Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(LMResponseParsedEvent) }
      def create_lm_response_parsed_event(payload)
        LMResponseParsedEvent.new(
          timestamp: extract_timestamp(payload),
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          signature_class: payload[:signature_class] || 'unknown',
          provider: payload[:provider] || 'unknown',
          success: payload[:success] || false,
          response_length: payload[:response_length] || 0,
          parse_type: payload[:parse_type],
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
      
      # Predict Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(PredictEvent) }
      def create_predict_event(payload)
        PredictEvent.new(
          timestamp: extract_timestamp(payload),
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          signature_class: payload[:signature_class] || 'unknown',
          module_name: payload[:module_name] || 'unknown',
          model: payload[:model] || 'unknown',
          provider: payload[:provider] || 'unknown',
          input_fields: payload[:input_fields] || [],
          input_size: payload[:input_size],
          output_size: payload[:output_size],
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
      
      # Predict Validation Error Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(PredictValidationErrorEvent) }
      def create_predict_validation_error_event(payload)
        PredictValidationErrorEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          status: payload[:status] || 'error',
          signature_class: payload[:signature_class] || 'unknown',
          module_name: payload[:module_name] || 'unknown',
          field_name: payload[:field_name] || 'unknown',
          error_message: payload[:error_message] || 'unknown error',
          retry_count: payload[:retry_count] || 0
        )
      end
      
      # Chain of Thought Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(ChainOfThoughtEvent) }
      def create_chain_of_thought_event(payload)
        ChainOfThoughtEvent.new(
          timestamp: extract_timestamp(payload),
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          signature_class: payload[:signature_class] || 'unknown',
          module_name: payload[:module_name] || 'unknown',
          model: payload[:model] || 'unknown',
          provider: payload[:provider] || 'unknown',
          reasoning_length: payload[:reasoning_length],
          answer_length: payload[:answer_length],
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
      
      # Chain of Thought Reasoning Complete Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(ChainOfThoughtReasoningCompleteEvent) }
      def create_chain_of_thought_reasoning_complete_event(payload)
        ChainOfThoughtReasoningCompleteEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          status: payload[:status] || 'success',
          signature_class: payload[:signature_class] || 'unknown',
          module_name: payload[:module_name] || 'unknown',
          reasoning_length: payload[:reasoning_length] || 0,
          answer_present: payload[:answer_present] || false
        )
      end
      
      # ReAct Iteration Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(ReactIterationEvent) }
      def create_react_iteration_event(payload)
        ReactIterationEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          iteration: payload[:iteration] || 0,
          max_iterations: payload[:max_iterations] || 5,
          history_length: payload[:history_length] || 0,
          tools_used_so_far: payload[:tools_used_so_far] || [],
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
      
      # ReAct Tool Call Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(ReactToolCallEvent) }
      def create_react_tool_call_event(payload)
        ReactToolCallEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          iteration: payload[:iteration] || 0,
          tool_name: payload[:tool_name] || 'unknown',
          tool_input: payload[:tool_input],
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
      
      # ReAct Iteration Complete Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(ReactIterationCompleteEvent) }
      def create_react_iteration_complete_event(payload)
        ReactIterationCompleteEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          status: payload[:status] || 'success',
          iteration: payload[:iteration] || 0,
          thought: payload[:thought] || '',
          action: payload[:action] || '',
          action_input: payload[:action_input],
          observation: payload[:observation] || '',
          tools_used: payload[:tools_used] || []
        )
      end
      
      # ReAct Max Iterations Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(ReactMaxIterationsEvent) }
      def create_react_max_iterations_event(payload)
        ReactMaxIterationsEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          status: payload[:status] || 'warning',
          iteration_count: payload[:iteration_count] || 0,
          max_iterations: payload[:max_iterations] || 5,
          tools_used: payload[:tools_used] || [],
          final_history_length: payload[:final_history_length] || 0
        )
      end
      
      # CodeAct Iteration Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(CodeActIterationEvent) }
      def create_codeact_iteration_event(payload)
        CodeActIterationEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          iteration: payload[:iteration] || 0,
          max_iterations: payload[:max_iterations] || 5,
          history_length: payload[:history_length] || 0,
          code_blocks_executed: payload[:code_blocks_executed] || 0,
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
      
      # CodeAct Code Execution Event
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(CodeActCodeExecutionEvent) }
      def create_codeact_code_execution_event(payload)
        CodeActCodeExecutionEvent.new(
          timestamp: payload[:timestamp] || Time.now.iso8601,
          duration_ms: payload[:duration_ms] || 0.0,
          cpu_time_ms: payload[:cpu_time_ms] || 0.0,
          status: payload[:status] || 'success',
          iteration: payload[:iteration] || 0,
          code_type: payload[:code_type] || 'unknown',
          code_length: payload[:code_length] || 0,
          execution_success: payload[:execution_success] || false,
          error_type: payload[:error_type],
          error_message: payload[:error_message]
        )
      end
    end
  end
end