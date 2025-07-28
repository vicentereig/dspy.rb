# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Instrumentation
    # Type-safe event payload structures for DSPy instrumentation
    # Each event is a complete T::Struct (no inheritance due to T::Struct limitations)
    
    # LM Request event payload
    class LMRequestEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # LM-specific fields
      const :gen_ai_operation_name, String
      const :gen_ai_system, String
      const :gen_ai_request_model, String
      const :signature_class, T.nilable(String), default: nil
      const :provider, String
      const :adapter_class, String
      const :input_size, Integer
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          gen_ai_operation_name: gen_ai_operation_name,
          gen_ai_system: gen_ai_system,
          gen_ai_request_model: gen_ai_request_model,
          provider: provider,
          adapter_class: adapter_class,
          input_size: input_size
        }
        hash[:signature_class] = signature_class if signature_class
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # Token usage event payload
    class LMTokensEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :status, String
      
      # Token-specific fields
      const :input_tokens, Integer
      const :output_tokens, Integer
      const :total_tokens, Integer
      const :gen_ai_system, String
      const :gen_ai_request_model, String
      const :signature_class, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          status: status,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: total_tokens,
          gen_ai_system: gen_ai_system,
          gen_ai_request_model: gen_ai_request_model
        }
        hash[:signature_class] = signature_class if signature_class
        hash
      end
    end
    
    # LM Response parsed event payload
    class LMResponseParsedEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # Response parsing fields
      const :signature_class, String
      const :provider, String
      const :success, T::Boolean
      const :response_length, Integer
      const :parse_type, T.nilable(String), default: nil
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          signature_class: signature_class,
          provider: provider,
          success: success,
          response_length: response_length
        }
        hash[:parse_type] = parse_type if parse_type
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # Predict event payload
    class PredictEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # Predict-specific fields
      const :signature_class, String
      const :module_name, String
      const :model, String
      const :provider, String
      const :input_fields, T::Array[String]
      const :input_size, T.nilable(Integer), default: nil
      const :output_size, T.nilable(Integer), default: nil
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          signature_class: signature_class,
          module_name: module_name,
          model: model,
          provider: provider,
          input_fields: input_fields
        }
        hash[:input_size] = input_size if input_size
        hash[:output_size] = output_size if output_size
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # Chain of Thought event payload
    class ChainOfThoughtEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # CoT-specific fields
      const :signature_class, String
      const :module_name, String
      const :model, String
      const :provider, String
      const :reasoning_length, T.nilable(Integer), default: nil
      const :answer_length, T.nilable(Integer), default: nil
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          signature_class: signature_class,
          module_name: module_name,
          model: model,
          provider: provider
        }
        hash[:reasoning_length] = reasoning_length if reasoning_length
        hash[:answer_length] = answer_length if answer_length
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # ReAct iteration event payload
    class ReactIterationEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # ReAct-specific fields
      const :iteration, Integer
      const :max_iterations, Integer
      const :history_length, Integer
      const :tools_used_so_far, T::Array[String]
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          iteration: iteration,
          max_iterations: max_iterations,
          history_length: history_length,
          tools_used_so_far: tools_used_so_far
        }
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # ReAct tool call event payload
    class ReactToolCallEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # Tool call fields
      const :iteration, Integer
      const :tool_name, String
      const :tool_input, T.untyped
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          iteration: iteration,
          tool_name: tool_name,
          tool_input: tool_input
        }
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # ReAct iteration complete event (emit, not instrument)
    class ReactIterationCompleteEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :status, String
      
      # Iteration complete fields
      const :iteration, Integer
      const :thought, String
      const :action, String
      const :action_input, T.untyped
      const :observation, String
      const :tools_used, T::Array[String]
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          timestamp: timestamp,
          status: status,
          iteration: iteration,
          thought: thought,
          action: action,
          action_input: action_input,
          observation: observation,
          tools_used: tools_used
        }
      end
    end
    
    # ReAct max iterations event (emit, not instrument)
    class ReactMaxIterationsEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :status, String
      
      # Max iterations fields
      const :iteration_count, Integer
      const :max_iterations, Integer
      const :tools_used, T::Array[String]
      const :final_history_length, Integer
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          timestamp: timestamp,
          status: status,
          iteration_count: iteration_count,
          max_iterations: max_iterations,
          tools_used: tools_used,
          final_history_length: final_history_length
        }
      end
    end
    
    # CodeAct iteration event payload
    class CodeActIterationEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # CodeAct-specific fields
      const :iteration, Integer
      const :max_iterations, Integer
      const :history_length, Integer
      const :code_blocks_executed, Integer
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          iteration: iteration,
          max_iterations: max_iterations,
          history_length: history_length,
          code_blocks_executed: code_blocks_executed
        }
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # CodeAct code execution event payload
    class CodeActCodeExecutionEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :duration_ms, Float
      const :cpu_time_ms, Float
      const :status, String
      
      # Code execution fields
      const :iteration, Integer
      const :code_type, String
      const :code_length, Integer
      const :execution_success, T::Boolean
      
      # Error fields (optional)
      const :error_type, T.nilable(String), default: nil
      const :error_message, T.nilable(String), default: nil
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = {
          timestamp: timestamp,
          duration_ms: duration_ms,
          cpu_time_ms: cpu_time_ms,
          status: status,
          iteration: iteration,
          code_type: code_type,
          code_length: code_length,
          execution_success: execution_success
        }
        hash[:error_type] = error_type if error_type
        hash[:error_message] = error_message if error_message
        hash
      end
    end
    
    # Chain of thought reasoning complete event (emit, not instrument)
    class ChainOfThoughtReasoningCompleteEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :status, String
      
      # Reasoning complete fields
      const :signature_class, String
      const :module_name, String
      const :reasoning_length, Integer
      const :answer_present, T::Boolean
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          timestamp: timestamp,
          status: status,
          signature_class: signature_class,
          module_name: module_name,
          reasoning_length: reasoning_length,
          answer_present: answer_present
        }
      end
    end
    
    # Validation error event (emit, not instrument)
    class PredictValidationErrorEvent < T::Struct
      extend T::Sig
      
      # Common fields
      const :timestamp, String
      const :status, String
      
      # Validation error fields
      const :signature_class, String
      const :module_name, String
      const :field_name, String
      const :error_message, String
      const :retry_count, Integer
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          timestamp: timestamp,
          status: status,
          signature_class: signature_class,
          module_name: module_name,
          field_name: field_name,
          error_message: error_message,
          retry_count: retry_count
        }
      end
    end
  end
end