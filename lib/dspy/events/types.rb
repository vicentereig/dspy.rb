# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Events
    # Base event structure using Sorbet T::Struct
    class Event < T::Struct
      const :name, String
      const :timestamp, Time
      const :attributes, T::Hash[T.any(String, Symbol), T.untyped], default: {}
      
      def initialize(name:, timestamp: Time.now, attributes: {})
        super(name: name, timestamp: timestamp, attributes: attributes)
      end
      
      def to_attributes
        result = attributes.dup
        result[:timestamp] = timestamp
        result
      end
    end

    # Token usage structure for LLM events
    class TokenUsage < T::Struct
      const :prompt_tokens, Integer
      const :completion_tokens, Integer
      
      def total_tokens
        prompt_tokens + completion_tokens
      end
    end

    # LLM operation events with semantic conventions
    class LLMEvent < T::Struct
      VALID_PROVIDERS = T.let(
        ['openai', 'anthropic', 'google', 'azure', 'ollama', 'together', 'groq', 'cohere'].freeze,
        T::Array[String]
      )
      
      # Common event fields
      const :name, String
      const :timestamp, Time
      
      # LLM-specific fields
      const :provider, String
      const :model, String
      const :usage, T.nilable(TokenUsage), default: nil
      const :duration_ms, T.nilable(Numeric), default: nil
      const :temperature, T.nilable(Float), default: nil
      const :max_tokens, T.nilable(Integer), default: nil
      const :stream, T.nilable(T::Boolean), default: nil
      
      def initialize(name:, provider:, model:, timestamp: Time.now, usage: nil, duration_ms: nil, temperature: nil, max_tokens: nil, stream: nil)
        unless VALID_PROVIDERS.include?(provider.downcase)
          raise ArgumentError, "Invalid provider '#{provider}'. Must be one of: #{VALID_PROVIDERS.join(', ')}"
        end
        super(
          name: name, 
          timestamp: timestamp,
          provider: provider.downcase, 
          model: model,
          usage: usage,
          duration_ms: duration_ms,
          temperature: temperature,
          max_tokens: max_tokens,
          stream: stream
        )
      end
      
      def to_otel_attributes
        attrs = {
          'gen_ai.system' => provider,
          'gen_ai.request.model' => model
        }
        
        if usage
          attrs['gen_ai.usage.prompt_tokens'] = usage.prompt_tokens
          attrs['gen_ai.usage.completion_tokens'] = usage.completion_tokens
          attrs['gen_ai.usage.total_tokens'] = usage.total_tokens
        end
        
        attrs['gen_ai.request.temperature'] = temperature if temperature
        attrs['gen_ai.request.max_tokens'] = max_tokens if max_tokens
        attrs['gen_ai.request.stream'] = stream if stream
        attrs['duration_ms'] = duration_ms if duration_ms
        
        attrs
      end
      
      def to_attributes
        result = to_otel_attributes.dup
        result[:timestamp] = timestamp
        result[:provider] = provider
        result[:model] = model
        result[:duration_ms] = duration_ms if duration_ms
        result
      end
    end

    # DSPy module execution events
    class ModuleEvent < T::Struct
      # Common event fields
      const :name, String
      const :timestamp, Time
      
      # Module-specific fields
      const :module_name, String
      const :signature_name, T.nilable(String), default: nil
      const :input_fields, T.nilable(T::Array[String]), default: nil
      const :output_fields, T.nilable(T::Array[String]), default: nil
      const :duration_ms, T.nilable(Numeric), default: nil
      const :success, T.nilable(T::Boolean), default: nil
      
      def initialize(name:, module_name:, timestamp: Time.now, signature_name: nil, input_fields: nil, output_fields: nil, duration_ms: nil, success: nil)
        super(
          name: name,
          timestamp: timestamp,
          module_name: module_name,
          signature_name: signature_name,
          input_fields: input_fields,
          output_fields: output_fields,
          duration_ms: duration_ms,
          success: success
        )
      end
      
      def to_attributes
        result = { timestamp: timestamp }
        result[:module_name] = module_name
        result[:signature_name] = signature_name if signature_name
        result[:input_fields] = input_fields if input_fields
        result[:output_fields] = output_fields if output_fields
        result[:duration_ms] = duration_ms if duration_ms
        result[:success] = success if success
        result
      end
    end

    # Optimization and training events
    class OptimizationEvent < T::Struct
      # Common event fields
      const :name, String
      const :timestamp, Time
      
      # Optimization-specific fields
      const :optimizer_name, String
      const :trial_number, T.nilable(Integer), default: nil
      const :score, T.nilable(Float), default: nil
      const :best_score, T.nilable(Float), default: nil
      const :parameters, T.nilable(T::Hash[T.any(String, Symbol), T.untyped]), default: nil
      const :duration_ms, T.nilable(Numeric), default: nil
      
      def initialize(name:, optimizer_name:, timestamp: Time.now, trial_number: nil, score: nil, best_score: nil, parameters: nil, duration_ms: nil)
        super(
          name: name,
          timestamp: timestamp,
          optimizer_name: optimizer_name,
          trial_number: trial_number,
          score: score,
          best_score: best_score,
          parameters: parameters,
          duration_ms: duration_ms
        )
      end
      
      def to_attributes
        result = { timestamp: timestamp }
        result[:optimizer_name] = optimizer_name
        result[:trial_number] = trial_number if trial_number
        result[:score] = score if score
        result[:best_score] = best_score if best_score
        result[:parameters] = parameters if parameters
        result[:duration_ms] = duration_ms if duration_ms
        result
      end
    end

    # Evaluation events
    class EvaluationEvent < T::Struct
      # Common event fields
      const :name, String
      const :timestamp, Time
      
      # Evaluation-specific fields
      const :evaluator_name, String
      const :metric_name, T.nilable(String), default: nil
      const :score, T.nilable(Float), default: nil
      const :total_examples, T.nilable(Integer), default: nil
      const :passed_examples, T.nilable(Integer), default: nil
      const :duration_ms, T.nilable(Numeric), default: nil
      
      def initialize(name:, evaluator_name:, timestamp: Time.now, metric_name: nil, score: nil, total_examples: nil, passed_examples: nil, duration_ms: nil)
        super(
          name: name,
          timestamp: timestamp,
          evaluator_name: evaluator_name,
          metric_name: metric_name,
          score: score,
          total_examples: total_examples,
          passed_examples: passed_examples,
          duration_ms: duration_ms
        )
      end
      
      def to_attributes
        result = { timestamp: timestamp }
        result[:evaluator_name] = evaluator_name
        result[:metric_name] = metric_name if metric_name
        result[:score] = score if score
        result[:total_examples] = total_examples if total_examples
        result[:passed_examples] = passed_examples if passed_examples
        result[:duration_ms] = duration_ms if duration_ms
        result
      end
    end
  end
end