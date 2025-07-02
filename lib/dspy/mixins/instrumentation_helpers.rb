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
        
        Instrumentation.instrument(event_name, full_payload) do
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
    end
  end
end