# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../evaluate'
require_relative '../example'

module DSPy
  module Teleprompt
    # Base class for all DSPy teleprompters (optimizers)
    # Defines the common interface and provides shared functionality for prompt optimization
    class Teleprompter
      extend T::Sig

      # Configuration for optimization runs
      class Config
        extend T::Sig

        sig { returns(T.nilable(Integer)) }
        attr_accessor :max_bootstrapped_examples

        sig { returns(T.nilable(Integer)) }
        attr_accessor :max_labeled_examples

        sig { returns(T.nilable(Integer)) }
        attr_accessor :num_candidate_examples

        sig { returns(T.nilable(Integer)) }
        attr_accessor :num_threads

        sig { returns(T.nilable(Integer)) }
        attr_accessor :max_errors

        sig { returns(T::Boolean) }
        attr_accessor :require_validation_examples

        sig { returns(T::Boolean) }
        attr_accessor :save_intermediate_results

        sig { returns(T.nilable(String)) }
        attr_accessor :save_path

        sig { void }
        def initialize
          @max_bootstrapped_examples = 4
          @max_labeled_examples = 16
          @num_candidate_examples = 50
          @num_threads = 1
          @max_errors = 5
          @require_validation_examples = true
          @save_intermediate_results = false
          @save_path = nil
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            max_bootstrapped_examples: @max_bootstrapped_examples,
            max_labeled_examples: @max_labeled_examples,
            num_candidate_examples: @num_candidate_examples,
            num_threads: @num_threads,
            max_errors: @max_errors,
            require_validation_examples: @require_validation_examples,
            save_intermediate_results: @save_intermediate_results,
            save_path: @save_path
          }
        end
      end

      # Result of an optimization run
      class OptimizationResult
        extend T::Sig

        sig { returns(T.untyped) }
        attr_reader :optimized_program

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :scores

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :history

        sig { returns(T.nilable(String)) }
        attr_reader :best_score_name

        sig { returns(T.nilable(Float)) }
        attr_reader :best_score_value

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :metadata

        sig do
          params(
            optimized_program: T.untyped,
            scores: T::Hash[Symbol, T.untyped],
            history: T::Hash[Symbol, T.untyped],
            best_score_name: T.nilable(String),
            best_score_value: T.nilable(Float),
            metadata: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(optimized_program:, scores:, history:, best_score_name: nil, best_score_value: nil, metadata: {})
          @optimized_program = optimized_program
          @scores = scores.freeze
          @history = history.freeze
          @best_score_name = best_score_name
          @best_score_value = best_score_value
          @metadata = metadata.freeze
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            scores: @scores,
            history: @history,
            best_score_name: @best_score_name,
            best_score_value: @best_score_value,
            metadata: @metadata
          }
        end
      end

      sig { returns(Config) }
      attr_reader :config

      sig { returns(T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped))) }
      attr_reader :metric

      sig { returns(T.nilable(DSPy::Evaluate)) }
      attr_reader :evaluator

      sig do
        params(
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
          config: T.nilable(Config)
        ).void
      end
      def initialize(metric: nil, config: nil)
        @metric = metric
        @config = config || Config.new
        @evaluator = nil
      end

      # Main optimization method - must be implemented by subclasses
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).returns(OptimizationResult)
      end
      def compile(program, trainset:, valset: nil)
        raise NotImplementedError, "Subclasses must implement the compile method"
      end

      # Validate optimization inputs
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).void
      end
      def validate_inputs(program, trainset, valset = nil)
        raise ArgumentError, "Program cannot be nil" unless program
        raise ArgumentError, "Training set cannot be empty" if trainset.empty?

        if @config.require_validation_examples && (valset.nil? || valset.empty?)
          raise ArgumentError, "Validation set is required but not provided"
        end

        # Validate training examples
        validate_examples(trainset, "training")
        validate_examples(valset, "validation") if valset && valset.any?
      end

      # Ensure examples are properly typed (only DSPy::Example instances supported)
      sig { params(examples: T::Array[T.untyped], signature_class: T.nilable(T.class_of(Signature))).returns(T::Array[DSPy::Example]) }
      def ensure_typed_examples(examples, signature_class = nil)
        # If examples are already DSPy::Example objects, return as-is
        return examples if examples.all? { |ex| ex.is_a?(DSPy::Example) }

        raise ArgumentError, "All examples must be DSPy::Example instances. Legacy format support has been removed. Please convert your examples to use the structured format with :input and :expected keys."
      end

      # Create evaluator for given examples and metric
      sig { params(examples: T::Array[T.untyped]).returns(DSPy::Evaluate) }
      def create_evaluator(examples)
        # Use provided metric or create a default one for DSPy::Example objects
        evaluation_metric = @metric || default_metric_for_examples(examples)
        
        @evaluator = DSPy::Evaluate.new(
          nil, # Program will be set during evaluation
          metric: evaluation_metric,
          num_threads: @config.num_threads,
          max_errors: @config.max_errors
        )
      end

      # Evaluate program performance on given examples
      sig do
        params(
          program: T.untyped,
          examples: T::Array[T.untyped],
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped))
        ).returns(DSPy::Evaluate::BatchEvaluationResult)
      end
      def evaluate_program(program, examples, metric: nil)
        evaluation_metric = metric || @metric || default_metric_for_examples(examples)
        
        evaluator = DSPy::Evaluate.new(
          program,
          metric: evaluation_metric,
          num_threads: @config.num_threads,
          max_errors: @config.max_errors
        )
        
        evaluator.evaluate(examples, display_progress: false)
      end

      # Save optimization results if configured
      sig { params(result: OptimizationResult).void }
      def save_results(result)
        # Legacy file-based saving
        if @config.save_intermediate_results && @config.save_path
          File.open(@config.save_path, 'w') do |f|
            f.write(JSON.pretty_generate(result.to_h))
          end
        end

        # Modern storage system integration
        if @config.save_intermediate_results
          storage_manager = DSPy::Storage::StorageManager.instance
          storage_manager.save_optimization_result(
            result,
            tags: [self.class.name.split('::').last.downcase],
            description: "Optimization by #{self.class.name}",
            metadata: {
              teleprompter_class: self.class.name,
              config: @config.to_h,
              optimization_duration: result.metadata[:optimization_duration] || 0
            }
          )
        end

        # Registry system integration for version management
        if @config.save_intermediate_results
          registry_manager = DSPy::Registry::RegistryManager.instance
          registry_manager.register_optimization_result(
            result,
            metadata: {
              teleprompter_class: self.class.name,
              config: @config.to_h
            }
          )
        end
      end

      protected

      # Validate that examples are in the correct format
      sig { params(examples: T.nilable(T::Array[T.untyped]), context: String).void }
      def validate_examples(examples, context)
        return unless examples

        examples.each_with_index do |example, index|
          validate_single_example(example, "#{context} example #{index}")
        end
      end

      # Validate a single example
      sig { params(example: T.untyped, context: String).void }
      def validate_single_example(example, context)
        case example
        when DSPy::Example
          # Already validated
          return
        when Hash
          # Only support structured format with :input and :expected keys
          if example.key?(:input) && example.key?(:expected)
            return
          elsif example.key?('input') && example.key?('expected')
            return
          end
        else
          # Check if it's an object with the right methods
          return if example.respond_to?(:input) && example.respond_to?(:expected)
        end

        raise ArgumentError, "Invalid #{context}: must be DSPy::Example or structured hash with :input and :expected keys. Legacy flat format is no longer supported."
      end


      # Infer signature class from examples
      sig { params(examples: T::Array[T.untyped]).returns(T.nilable(T.class_of(Signature))) }
      def infer_signature_class(examples)
        require_relative 'utils'
        Utils.infer_signature_class(examples)
      end

      # Create a default metric for examples
      sig { params(examples: T::Array[T.untyped]).returns(T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))) }
      def default_metric_for_examples(examples)
        # For DSPy::Example objects, use built-in matching
        if examples.first.is_a?(DSPy::Example)
          proc { |example, prediction| example.matches_prediction?(prediction) }
        else
          # For other formats, no default metric
          nil
        end
      end

      # Instrument optimization steps
      sig { params(step_name: String, payload: T::Hash[Symbol, T.untyped], block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def instrument_step(step_name, payload = {}, &block)
        DSPy::Context.with_span(
          operation: "optimization.#{step_name}",
          'dspy.module' => 'Teleprompter',
          'teleprompter.class' => self.class.name,
          'teleprompter.config' => @config.to_h,
          **payload
        ) do
          yield
        end
      end

      # Emit optimization events
      sig { params(event_name: String, payload: T::Hash[Symbol, T.untyped]).void }
      def emit_event(event_name, payload = {})
        DSPy.log("optimization.#{event_name}", **payload.merge({
          'teleprompter.class': self.class.name
        }))
      end
    end
  end
end