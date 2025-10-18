# frozen_string_literal: true

require 'securerandom'
require 'sorbet-runtime'
require 'dspy'

module GEPA
  # Telemetry helpers for the GEPA optimizer.
  #
  # The helpers wrap DSPy context spans and structured logs so that the GEPA
  # port can attach observability data consistently across the optimization
  # lifecycle. They mirror the phases from the Python sequence diagrams:
  #
  # - `gepa.optimize` (API entry)
  # - `gepa.state.initialize`
  # - `gepa.engine.run` / `gepa.engine.iteration`
  # - `gepa.proposer.*` (selection, evaluation, reflection, acceptance)
  #
  # Later phases of the port can depend on these helpers without reimplementing
  # span naming or default attributes.
  module Telemetry
    extend T::Sig

    DEFAULT_ATTRIBUTES = T.let({
      optimizer: 'GEPA',
      'gepa.instrumentation_version': 'phase0',
      'langfuse.observation.type': 'span'
    }.freeze, T::Hash[Symbol, T.untyped])

    class Context < T::Struct
      extend T::Sig

      const :run_id, String
      const :attributes, T::Hash[Symbol, T.untyped]

      sig do
        params(
          operation: String,
          metadata: T::Hash[T.any(String, Symbol), T.untyped],
          block: T.proc.returns(T.untyped)
        ).returns(T.untyped)
      end
      def with_span(operation, metadata = {}, &block)
        Telemetry.with_span(operation, base_attributes.merge(Telemetry.send(:symbolize, metadata)), &block)
      end

      sig do
        params(
          event_name: String,
          metadata: T::Hash[T.any(String, Symbol), T.untyped]
        ).void
      end
      def emit(event_name, metadata = {})
        Telemetry.emit(event_name, base_attributes.merge(Telemetry.send(:symbolize, metadata)))
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def base_attributes
        attributes.merge(run_id: run_id)
      end
    end

    sig do
      params(
        additional_attributes: T::Hash[T.any(String, Symbol), T.untyped]
      ).returns(Context)
    end
    def self.build_context(additional_attributes = {})
      attributes = DEFAULT_ATTRIBUTES.merge(symbolize(additional_attributes.dup))
      run_id = attributes.delete(:run_id) || SecureRandom.uuid

      Context.new(run_id: run_id, attributes: attributes)
    end

    sig do
      params(
        operation: String,
        attributes: T::Hash[T.any(String, Symbol), T.untyped],
        block: T.proc.returns(T.untyped)
      ).returns(T.untyped)
    end
    def self.with_span(operation, attributes = {}, &block)
      operation_name = normalize_operation(operation)
      span_attributes = DEFAULT_ATTRIBUTES.merge(symbolize(attributes))

      DSPy::Context.with_span(operation: operation_name, **span_attributes, &block)
    end

    sig do
      params(
        event_name: String,
        attributes: T::Hash[T.any(String, Symbol), T.untyped]
      ).void
    end
    def self.emit(event_name, attributes = {})
      payload = DEFAULT_ATTRIBUTES.merge(symbolize(attributes))
      DSPy.log("gepa.#{event_name}", **payload)
    end

    sig { params(operation: String).returns(String) }
    def self.normalize_operation(operation)
      return operation if operation.start_with?('gepa.')

      "gepa.#{operation}"
    end
    private_class_method :normalize_operation

    sig do
      params(
        attributes: T::Hash[T.any(String, Symbol), T.untyped]
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def self.symbolize(attributes)
      attributes.each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = value
      end
    end
    private_class_method :symbolize
  end
end
