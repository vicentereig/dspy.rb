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

        DSPy::Instrumentation.subscribe('dspy.lm.tokens') do |event|
          log_lm_tokens(event)
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

        # Subscribe to optimization events
        DSPy::Instrumentation.subscribe('dspy.optimization.start') do |event|
          log_optimization_start(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.complete') do |event|
          log_optimization_complete(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.trial_start') do |event|
          log_optimization_trial_start(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.trial_complete') do |event|
          log_optimization_trial_complete(event)
        end

        DSPy::Instrumentation.subscribe('dspy.optimization.error') do |event|
          log_optimization_error(event)
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
        timestamp = format_timestamp(payload)

        log_parts = [
          "event=lm_request",
          timestamp,
          "provider=#{provider}",
          "model=#{model}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ].compact
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_lm_tokens(event)
        payload = event.payload
        provider = payload[:gen_ai_system] || payload[:provider]
        model = payload[:gen_ai_request_model] || payload[:model]
        input_tokens = payload[:input_tokens]
        output_tokens = payload[:output_tokens]
        total_tokens = payload[:total_tokens]
        timestamp = format_timestamp(payload)

        log_parts = [
          "event=lm_tokens",
          timestamp,
          "provider=#{provider}",
          "model=#{model}"
        ].compact
        log_parts << "input_tokens=#{input_tokens}" if input_tokens
        log_parts << "output_tokens=#{output_tokens}" if output_tokens
        log_parts << "total_tokens=#{total_tokens}" if total_tokens

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_prediction(event)
        payload = event.payload
        signature = payload[:signature_class]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]
        input_size = payload[:input_size]
        timestamp = format_timestamp(payload)

        log_parts = [
          "event=prediction",
          timestamp,
          "signature=#{signature}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ].compact
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
        timestamp = format_timestamp(payload)

        log_parts = [
          "event=chain_of_thought",
          timestamp,
          "signature=#{signature}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ].compact
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
        log_parts << "thought=\"#{thought && thought.length > 100 ? thought[0..97] + '...' : thought}\"" if thought
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

      # Optimization event logging methods
      sig { params(event: T.untyped).void }
      def log_optimization_start(event)
        payload = event.payload
        optimization_id = payload[:optimization_id]
        optimizer = payload[:optimizer]
        trainset_size = payload[:trainset_size]
        valset_size = payload[:valset_size]

        log_parts = [
          "event=optimization_start",
          "optimization_id=#{optimization_id}",
          "optimizer=#{optimizer}",
          "trainset_size=#{trainset_size}"
        ]
        log_parts << "valset_size=#{valset_size}" if valset_size

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_optimization_complete(event)
        payload = event.payload
        optimization_id = payload[:optimization_id]
        optimizer = payload[:optimizer]
        duration = payload[:duration_ms]&.round(2)
        best_score = payload[:best_score]
        trials_count = payload[:trials_count]

        log_parts = [
          "event=optimization_complete",
          "optimization_id=#{optimization_id}",
          "optimizer=#{optimizer}",
          "duration_ms=#{duration}"
        ]
        log_parts << "best_score=#{best_score}" if best_score
        log_parts << "trials_count=#{trials_count}" if trials_count

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_optimization_trial_start(event)
        payload = event.payload
        optimization_id = payload[:optimization_id]
        trial_number = payload[:trial_number]
        instruction = payload[:instruction]

        log_parts = [
          "event=optimization_trial_start",
          "optimization_id=#{optimization_id}",
          "trial_number=#{trial_number}"
        ]
        log_parts << "instruction=\"#{instruction&.slice(0, 100)}\"" if instruction

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_optimization_trial_complete(event)
        payload = event.payload
        optimization_id = payload[:optimization_id]
        trial_number = payload[:trial_number]
        duration = payload[:duration_ms]&.round(2)
        score = payload[:score]
        status = payload[:status]

        log_parts = [
          "event=optimization_trial_complete",
          "optimization_id=#{optimization_id}",
          "trial_number=#{trial_number}",
          "status=#{status}",
          "duration_ms=#{duration}"
        ]
        log_parts << "score=#{score}" if score
        log_parts << "error=\"#{payload[:error_message]}\"" if status == 'error' && payload[:error_message]

        logger.info(log_parts.join(' '))
      end

      sig { params(event: T.untyped).void }
      def log_optimization_error(event)
        payload = event.payload
        optimization_id = payload[:optimization_id]
        optimizer = payload[:optimizer]
        error_message = payload[:error_message]
        error_type = payload[:error_type]

        log_parts = [
          "event=optimization_error",
          "optimization_id=#{optimization_id}",
          "optimizer=#{optimizer}",
          "error_type=#{error_type}"
        ]
        log_parts << "error=\"#{error_message}\"" if error_message

        logger.info(log_parts.join(' '))
      end

      # Format timestamp based on configured format
      sig { params(payload: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
      def format_timestamp(payload)
        case DSPy.config.instrumentation.timestamp_format
        when DSPy::TimestampFormat::ISO8601
          if timestamp = payload[:timestamp]
            "timestamp=#{timestamp}"
          end
        when DSPy::TimestampFormat::RFC3339_NANO
          if timestamp = payload[:timestamp]
            "timestamp=#{timestamp}"
          end
        when DSPy::TimestampFormat::UNIX_NANO
          if timestamp_ns = payload[:timestamp_ns]
            "timestamp_ns=#{timestamp_ns}"
          end
        else
          # Fallback to timestamp if available
          if timestamp = payload[:timestamp]
            "timestamp=#{timestamp}"
          end
        end
      end
    end
  end
end
