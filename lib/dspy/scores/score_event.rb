# frozen_string_literal: true

require 'sorbet-runtime'
require 'securerandom'
require_relative 'data_type'

module DSPy
  module Scores
    # Represents a score to be sent to Langfuse
    # Immutable struct with all score attributes
    class ScoreEvent < T::Struct
      extend T::Sig

      # Unique identifier for the score (idempotency key)
      prop :id, String, factory: -> { SecureRandom.uuid }

      # Score name/identifier (required)
      prop :name, String

      # Score value - numeric, boolean (0/1), or categorical (string)
      prop :value, T.any(Numeric, String)

      # Data type for the score
      prop :data_type, DataType, default: DataType::Numeric

      # Optional human-readable comment
      prop :comment, T.nilable(String), default: nil

      # Trace ID to link the score to (required for Langfuse)
      prop :trace_id, T.nilable(String), default: nil

      # Observation/span ID to link the score to (optional)
      prop :observation_id, T.nilable(String), default: nil

      # Timestamp when the score was created
      prop :timestamp, Time, factory: -> { Time.now }

      # Serialize to Langfuse API payload format
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_langfuse_payload
        payload = {
          id: id,
          name: name,
          value: value,
          dataType: data_type.serialize
        }

        payload[:comment] = comment if comment
        payload[:traceId] = trace_id if trace_id
        payload[:observationId] = observation_id if observation_id

        payload
      end
    end
  end
end
