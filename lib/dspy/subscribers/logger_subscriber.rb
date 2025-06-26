# frozen_string_literal: true

module DSPy
  module Subscribers
    # Logger subscriber that provides detailed logging based on instrumentation events
    # Subscribes to DSPy events and logs relevant information for debugging and monitoring
    class LoggerSubscriber
      extend T::Sig

      sig { params(logger: T.nilable(Logger)).void }
      def initialize(logger: nil)
        @logger = T.let(logger || DSPy.config.logger, Logger)
        setup_event_subscriptions
      end

      private

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
        tokens = if payload[:tokens_total]
                   " (#{payload[:tokens_total]} tokens)"
                 else
                   ""
                 end

        status_emoji = status == 'success' ? '✅' : '❌'
        @logger.info("#{status_emoji} LM Request [#{provider}/#{model}] - #{status} (#{duration}ms)#{tokens}")
        
        if status == 'error' && payload[:error_message]
          @logger.error("  Error: #{payload[:error_message]}")
        end
      end

      sig { params(event: T.untyped).void }
      def log_prediction(event)
        payload = event.payload
        signature = payload[:signature_class]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]
        input_size = payload[:input_size]

        status_emoji = status == 'success' ? '🔮' : '❌'
        @logger.info("#{status_emoji} Prediction [#{signature}] - #{status} (#{duration}ms)")
        @logger.info("  Input size: #{input_size} chars") if input_size
        
        if status == 'error' && payload[:error_message]
          @logger.error("  Error: #{payload[:error_message]}")
        end
      end

      sig { params(event: T.untyped).void }
      def log_chain_of_thought(event)
        payload = event.payload
        signature = payload[:signature_class]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]
        reasoning_steps = payload[:reasoning_steps]
        reasoning_length = payload[:reasoning_length]

        status_emoji = status == 'success' ? '🧠' : '❌'
        @logger.info("#{status_emoji} Chain of Thought [#{signature}] - #{status} (#{duration}ms)")
        @logger.info("  Reasoning steps: #{reasoning_steps}") if reasoning_steps
        @logger.info("  Reasoning length: #{reasoning_length} chars") if reasoning_length
        
        if status == 'error' && payload[:error_message]
          @logger.error("  Error: #{payload[:error_message]}")
        end
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

        status_emoji = case status
                       when 'success' then '🤖'
                       when 'max_iterations' then '⏰'
                       else '❌'
                       end
        
        @logger.info("#{status_emoji} ReAct Agent [#{signature}] - #{status} (#{duration}ms)")
        @logger.info("  Iterations: #{iteration_count}") if iteration_count
        @logger.info("  Tools used: #{tools_used.join(', ')}") if tools_used&.any?
        @logger.info("  Final answer: #{final_answer}") if final_answer
        
        if status == 'error' && payload[:error_message]
          @logger.error("  Error: #{payload[:error_message]}")
        end
      end

      sig { params(event: T.untyped).void }
      def log_react_iteration_complete(event)
        payload = event.payload
        iteration = payload[:iteration]
        thought = payload[:thought]
        action = payload[:action]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]

        status_emoji = status == 'success' ? '🔄' : '❌'
        @logger.info("#{status_emoji} ReAct Iteration #{iteration} - #{status} (#{duration}ms)")
        @logger.info("  Thought: #{thought.truncate(100)}") if thought
        @logger.info("  Action: #{action}") if action
        
        if status == 'error' && payload[:error_message]
          @logger.error("  Error: #{payload[:error_message]}")
        end
      end

      sig { params(event: T.untyped).void }
      def log_react_tool_call(event)
        payload = event.payload
        iteration = payload[:iteration]
        tool_name = payload[:tool_name]
        duration = payload[:duration_ms]&.round(2)
        status = payload[:status]

        status_emoji = status == 'success' ? '🔧' : '❌'
        @logger.info("#{status_emoji} Tool Call [#{tool_name}] (Iteration #{iteration}) - #{status} (#{duration}ms)")
        
        if status == 'error' && payload[:error_message]
          @logger.error("  Error: #{payload[:error_message]}")
        end
      end
    end
  end
end
