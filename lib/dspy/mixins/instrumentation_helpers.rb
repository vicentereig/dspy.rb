# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../instrumentation'

module DSPy
  module Mixins
    # Shared instrumentation helper methods for DSPy modules
    module InstrumentationHelpers
      extend T::Sig

      private

      # Prepares base instrumentation payload for prediction-based modules
      sig { params(signature_class: T.class_of(DSPy::Signature), input_values: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def prepare_base_instrumentation_payload(signature_class, input_values)
        {
          signature_class: signature_class.name,
          model: lm.model,
          provider: lm.provider,
          input_fields: input_values.keys.map(&:to_s)
        }
      end

      # Instruments a prediction operation with base payload
      sig { params(event_name: String, signature_class: T.class_of(DSPy::Signature), input_values: T::Hash[Symbol, T.untyped], additional_payload: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def instrument_prediction(event_name, signature_class, input_values, additional_payload = {})
        base_payload = prepare_base_instrumentation_payload(signature_class, input_values)
        full_payload = base_payload.merge(additional_payload)
        
        # Check if we should emit this event based on trace level
        trace_level = DSPy.config.instrumentation.trace_level
        
        if should_emit_event?(event_name, trace_level)
          Instrumentation.instrument(event_name, full_payload) do
            yield
          end
        else
          # Skip instrumentation, just execute the block
          yield
        end
      end

      # Emits a validation error event
      sig { params(signature_class: T.class_of(DSPy::Signature), validation_type: String, error_message: String).void }
      def emit_validation_error(signature_class, validation_type, error_message)
        Instrumentation.emit('dspy.prediction.validation_error', {
          signature_class: signature_class.name,
          validation_type: validation_type,
          validation_errors: { validation_type.to_sym => error_message }
        })
      end

      # Emits a prediction completion event
      sig { params(signature_class: T.class_of(DSPy::Signature), success: T::Boolean, additional_data: T::Hash[Symbol, T.untyped]).void }
      def emit_prediction_complete(signature_class, success, additional_data = {})
        Instrumentation.emit('dspy.prediction.complete', {
          signature_class: signature_class.name,
          success: success
        }.merge(additional_data))
      end

      # Determines if an event should be emitted based on trace level
      sig { params(event_name: String, trace_level: Symbol).returns(T::Boolean) }
      def should_emit_event?(event_name, trace_level)
        case trace_level
        when :minimal
          # Only emit the highest-level events (chain_of_thought, react, etc.)
          event_name.match?(/^dspy\.(chain_of_thought|react)$/)
        when :standard
          # Emit consolidated events - skip nested events when a higher-level event is being emitted
          # This is the key change: detect if we're in a nested context and skip lower-level events
          if is_nested_context?
            # If we're in a nested context, only emit higher-level events
            event_name.match?(/^dspy\.(chain_of_thought|react)$/)
          else
            # If we're not in a nested context, emit all events normally
            true
          end
        when :detailed
          # Emit all events with additional correlation information
          true
        else
          true
        end
      end

      # Determines if this is a top-level event (not nested)
      sig { params(event_name: String).returns(T::Boolean) }
      def is_top_level_event?(event_name)
        # Check if we're in a nested call by looking at the call stack
        caller_locations = caller_locations(1, 20)
        return false if caller_locations.nil?
        
        # Look for other instrumentation calls in the stack
        instrumentation_calls = caller_locations.select do |loc|
          loc.label.include?('instrument_prediction') || 
          loc.label.include?('instrument') ||
          loc.path.include?('instrumentation')
        end
        
        # If we have more than one instrumentation call, this is nested
        instrumentation_calls.size <= 1
      end

      # Determines if we're in a nested call context
      sig { returns(T::Boolean) }
      def is_nested_call?
        !is_top_level_event?('')
      end

      # Determines if we're in a nested context where higher-level events are being emitted
      sig { returns(T::Boolean) }
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

    end
  end
end