# frozen_string_literal: true

module DSPy
  module Subscribers
    # Logger subscriber that provides detailed logging based on instrumentation events
    # Subscribes to DSPy events and logs relevant information for debugging and monitoring
    class LoggerSubscriber
      extend T::Sig

      sig { params(logger: T.nilable(T.any(Logger, Dry::Logger::Dispatcher))).void }
      def initialize(logger: nil)
        @explicit_logger = T.let(logger, T.nilable(T.any(Logger, Dry::Logger::Dispatcher)))
        setup_event_subscriptions
      end

      private

      # Always use the current configured logger or the explicit one
      sig { returns(T.any(Logger, Dry::Logger::Dispatcher)) }
      def logger
        @explicit_logger || DSPy.config.logger
      end

      sig { void }
      def setup_event_subscriptions
        # Subscribe to DSPy instrumentation events
        DSPy::Instrumentation.subscribe('dspy.lm.request') do |event|
          log_lm_request(event)
        end

        DSPy::Instrumentation.subscribe('dspy.predict') do |event|
          log_prediction(event)
        end

        DSPy::Instrumentation.subscribe('dspy.chain_of_thought') do |event|
          log_chain_of_thought(event)
        end

        DSPy::Instrumentation.subscribe('dspy.react') do |event|
          log_react(event)
        end

        DSPy::Instrumentation.subscribe('dspy.react.iteration_complete') do |event|
          log_react_iteration_complete(event)
        end

        DSPy::Instrumentation.subscribe('dspy.react.tool_call') do |event|
          log_react_tool_call(event)
        end
      end

      # Callback methods for different event types
      sig { params(event: T.untyped).void }
      def on_lm_request(event)
        log_lm_request(event)
      end

      sig { params(event: T.untyped).void }
      def on_predict(event)
        log_prediction(event)
      end

      sig { params(event: T.untyped).void }
      def on_chain_of_thought(event)
        log_chain_of_thought(event)
      end

      sig { params(event: T.untyped).void }
      def on_react(event)
        log_react(event)
      end

      sig { params(event: T.untyped).void }
      def on_react_iteration_complete(event)
        log_react_iteration_complete(event)
      end

      sig { params(event: T.untyped).void }
      def on_react_tool_call(event)
        log_react_tool_call(event)
      end

      # Event logging methods
      sig { params(event: T.untyped).void }
      def log_lm_request(event)
        payload = event.payload
        provider = payload[:provider]
        model = payload[:gen_ai_request_model] || payload[:model]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]
        tokens = payload[:tokens_total]

        log_parts = [
          "event=lm_request",
          "provider=#{provider}",
          "model=#{model}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ]
        log_parts << "tokens=#{tokens}" if tokens
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_prediction(event)
        payload = event.payload
        signature = payload[:signature_class]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]
        input_size = payload[:input_size]

        log_parts = [
          "event=prediction",
          "signature=#{signature}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ]
        log_parts << "input_size=#{input_size}" if input_size
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_chain_of_thought(event)
        payload = event.payload
        signature = payload[:signature_class]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]
        reasoning_steps = payload[:reasoning_steps]
        reasoning_length = payload[:reasoning_length]

        log_parts = [
          "event=chain_of_thought",
          "signature=#{signature}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ]
        log_parts << "reasoning_steps=#{reasoning_steps}" if reasoning_steps
        log_parts << "reasoning_length=#{reasoning_length}" if reasoning_length
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_react(event)
        payload = event.payload
        signature = payload[:signature_class]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]
        iteration_count = payload[:iteration_count]
        tools_used = payload[:tools_used]
        final_answer = payload[:final_answer]

        log_parts = [
          "event=react",
          "signature=#{signature}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ]
        log_parts << "iterations=#{iteration_count}" if iteration_count
        log_parts << "tools_used=\"#{tools_used.join(',')}\"" if tools_used&.any?
        log_parts << "final_answer=\"#{final_answer&.truncate(100)}\"" if final_answer
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_react_iteration_complete(event)
        payload = event.payload
        iteration = payload[:iteration]
        thought = payload[:thought]
        action = payload[:action]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]

        log_parts = [
          "event=react_iteration",
          "iteration=#{iteration}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ]
        log_parts << "thought=\"#{thought&.truncate(100)}\"" if thought
        log_parts << "action=\"#{action}\"" if action
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_react_tool_call(event)
        payload = event.payload
        iteration = payload[:iteration]
        tool_name = payload[:tool_name]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]

        log_parts = [
          "event=tool_call",
          "tool=#{tool_name}",
          "iteration=#{iteration}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ]
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end
    end
  end
end
