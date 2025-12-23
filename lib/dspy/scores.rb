# frozen_string_literal: true

require_relative 'scores/data_type'
require_relative 'scores/score_event'
require_relative 'scores/evaluators'

module DSPy
  # Score reporting for Langfuse integration
  # Provides a simple API for creating and exporting evaluation scores
  module Scores
    extend T::Sig

    class << self
      extend T::Sig

      # Create a score event from the current context
      #
      # @param name [String] Score identifier (e.g., "accuracy", "relevance")
      # @param value [Numeric, String] Score value
      # @param data_type [DataType] Type of score (default: Numeric)
      # @param comment [String, nil] Optional human-readable comment
      # @param span [Object, nil] Optional span to attach score to
      # @param emit [Boolean] Whether to emit score.create event (default: true)
      # @return [ScoreEvent] The created score event
      sig do
        params(
          name: String,
          value: T.any(Numeric, String),
          data_type: DataType,
          comment: T.nilable(String),
          span: T.untyped,
          trace_id: T.nilable(String),
          observation_id: T.nilable(String),
          emit: T::Boolean
        ).returns(ScoreEvent)
      end
      def create(
        name:,
        value:,
        data_type: DataType::Numeric,
        comment: nil,
        span: nil,
        trace_id: nil,
        observation_id: nil,
        emit: true
      )
        # Extract trace_id from context if not provided
        resolved_trace_id = trace_id || extract_trace_id_from_context
        resolved_observation_id = observation_id || extract_observation_id_from_span(span)

        event = ScoreEvent.new(
          name: name,
          value: value,
          data_type: data_type,
          comment: comment,
          trace_id: resolved_trace_id,
          observation_id: resolved_observation_id
        )

        # Emit score.create event for listeners and exporters
        emit_score_event(event) if emit

        event
      end

      private

      sig { returns(T.nilable(String)) }
      def extract_trace_id_from_context
        return nil unless defined?(DSPy::Context)

        DSPy::Context.current[:trace_id]
      rescue StandardError
        nil
      end

      sig { params(span: T.untyped).returns(T.nilable(String)) }
      def extract_observation_id_from_span(span)
        return nil unless span

        if span.respond_to?(:context) && span.context.respond_to?(:span_id)
          span.context.span_id
        elsif span.respond_to?(:span_id)
          span.span_id
        end
      rescue StandardError
        nil
      end

      sig { params(event: ScoreEvent).void }
      def emit_score_event(event)
        return unless defined?(DSPy) && DSPy.respond_to?(:events)

        DSPy.events.notify('score.create', {
          score_id: event.id,
          score_name: event.name,
          score_value: event.value,
          score_data_type: event.data_type.serialize,
          score_comment: event.comment,
          trace_id: event.trace_id,
          observation_id: event.observation_id,
          timestamp: event.timestamp.iso8601
        })
      rescue StandardError => e
        DSPy.log('score.emit_error', error: e.message) if DSPy.respond_to?(:log)
      end
    end
  end

  # Top-level convenience method for creating scores
  #
  # @example Basic usage
  #   DSPy.score('accuracy', 0.95)
  #
  # @example With comment
  #   DSPy.score('accuracy', 0.95, comment: 'Exact match')
  #
  # @example Boolean score
  #   DSPy.score('is_valid', 1, data_type: DSPy::Scores::DataType::Boolean)
  #
  # @example Categorical score
  #   DSPy.score('sentiment', 'positive', data_type: DSPy::Scores::DataType::Categorical)
  #
  def self.score(name, value, data_type: Scores::DataType::Numeric, comment: nil, span: nil, trace_id: nil, observation_id: nil)
    Scores.create(
      name: name,
      value: value,
      data_type: data_type,
      comment: comment,
      span: span,
      trace_id: trace_id,
      observation_id: observation_id
    )
  end
end
