# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../evaluate'
require_relative '../example'
require_relative 'data_handler'

module DSPy
  module Teleprompt
    # Bootstrap utilities for MIPROv2 optimization
    # Handles few-shot example generation and candidate program evaluation
    module Utils
      extend T::Sig

      # Configuration for bootstrap operations
      class BootstrapConfig
        extend T::Sig

        sig { returns(Integer) }
        attr_accessor :max_bootstrapped_examples

        sig { returns(Integer) }
        attr_accessor :max_labeled_examples

        sig { returns(Integer) }
        attr_accessor :num_candidate_sets

        sig { returns(Integer) }
        attr_accessor :max_errors

        sig { returns(Integer) }
        attr_accessor :num_threads

        sig { returns(Float) }
        attr_accessor :success_threshold

        sig { returns(Integer) }
        attr_accessor :minibatch_size

        sig { void }
        def initialize
          @max_bootstrapped_examples = 4
          @max_labeled_examples = 16
          @num_candidate_sets = 10
          @max_errors = 5
          @num_threads = 1
          @success_threshold = 0.8
          @minibatch_size = 50
        end
      end

      # Result of bootstrap operation
      class BootstrapResult
        extend T::Sig

        sig { returns(T::Array[T::Array[DSPy::Example]]) }
        attr_reader :candidate_sets

        sig { returns(T::Array[DSPy::Example]) }
        attr_reader :successful_examples

        sig { returns(T::Array[DSPy::Example]) }
        attr_reader :failed_examples

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :statistics

        sig do
          params(
            candidate_sets: T::Array[T::Array[DSPy::Example]],
            successful_examples: T::Array[DSPy::Example],
            failed_examples: T::Array[DSPy::Example],
            statistics: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(candidate_sets:, successful_examples:, failed_examples:, statistics:)
          @candidate_sets = candidate_sets.freeze
          @successful_examples = successful_examples.freeze
          @failed_examples = failed_examples.freeze
          @statistics = statistics.freeze
        end

        sig { returns(Float) }
        def success_rate
          total = @successful_examples.size + @failed_examples.size
          return 0.0 if total == 0
          @successful_examples.size.to_f / total.to_f
        end

        sig { returns(Integer) }
        def total_examples
          @successful_examples.size + @failed_examples.size
        end
      end

      # Create multiple candidate sets of few-shot examples through bootstrapping
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          config: BootstrapConfig,
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
        ).returns(BootstrapResult)
      end
      def self.create_n_fewshot_demo_sets(program, trainset, config: BootstrapConfig.new, metric: nil)
        DSPy::Context.with_span(
          operation: 'optimization.bootstrap_start',
          'dspy.module' => 'Bootstrap',
          'bootstrap.trainset_size' => trainset.size,
          'bootstrap.max_examples' => config.max_bootstrapped_examples,
          'bootstrap.num_candidate_sets' => config.num_candidate_sets
        ) do
          # Convert to typed examples if needed
          typed_examples = ensure_typed_examples(trainset)
          
          # Generate successful examples through bootstrap
          successful_examples, failed_examples = generate_successful_examples(
            program, 
            typed_examples, 
            config,
            metric
          )

          # Create candidate sets from successful examples
          candidate_sets = create_candidate_sets(successful_examples, config)

          # Gather statistics
          statistics = {
            total_trainset: trainset.size,
            successful_count: successful_examples.size,
            failed_count: failed_examples.size,
            success_rate: successful_examples.size.to_f / (successful_examples.size + failed_examples.size),
            candidate_sets_created: candidate_sets.size,
            average_set_size: candidate_sets.empty? ? 0 : candidate_sets.map(&:size).sum.to_f / candidate_sets.size
          }

          emit_bootstrap_complete_event(statistics)

          BootstrapResult.new(
            candidate_sets: candidate_sets,
            successful_examples: successful_examples,
            failed_examples: failed_examples,
            statistics: statistics
          )
        end
      end

      # Evaluate a candidate program on examples with proper error handling
      sig do
        params(
          program: T.untyped,
          examples: T::Array[T.untyped],
          config: BootstrapConfig,
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
        ).returns(DSPy::Evaluate::BatchEvaluationResult)
      end
      def self.eval_candidate_program(program, examples, config: BootstrapConfig.new, metric: nil)
        # Use minibatch evaluation for large datasets
        if examples.size > config.minibatch_size
          eval_candidate_program_minibatch(program, examples, config, metric)
        else
          eval_candidate_program_full(program, examples, config, metric)
        end
      end

      # Minibatch evaluation for large datasets
      sig do
        params(
          program: T.untyped,
          examples: T::Array[T.untyped],
          config: BootstrapConfig,
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
        ).returns(DSPy::Evaluate::BatchEvaluationResult)
      end
      def self.eval_candidate_program_minibatch(program, examples, config, metric)
        DSPy::Context.with_span(
          operation: 'optimization.minibatch_evaluation',
          'dspy.module' => 'Bootstrap',
          'minibatch.total_examples' => examples.size,
          'minibatch.size' => config.minibatch_size,
          'minibatch.num_batches' => (examples.size.to_f / config.minibatch_size).ceil
        ) do
          # Randomly sample a minibatch for evaluation
          sample_size = [config.minibatch_size, examples.size].min
          sampled_examples = examples.sample(sample_size)
          
          eval_candidate_program_full(program, sampled_examples, config, metric)
        end
      end

      # Full evaluation on all examples
      sig do
        params(
          program: T.untyped,
          examples: T::Array[T.untyped],
          config: BootstrapConfig,
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
        ).returns(DSPy::Evaluate::BatchEvaluationResult)
      end
      def self.eval_candidate_program_full(program, examples, config, metric)
        # Create evaluator with proper configuration
        evaluator = DSPy::Evaluate.new(
          program,
          metric: metric || default_metric_for_examples(examples),
          num_threads: config.num_threads,
          max_errors: config.max_errors
        )

        # Run evaluation
        evaluator.evaluate(examples, display_progress: false)
      end

      private

      # Convert various example formats to typed examples
      sig { params(examples: T::Array[T.untyped]).returns(T::Array[DSPy::Example]) }
      def self.ensure_typed_examples(examples)
        return examples if examples.all? { |ex| ex.is_a?(DSPy::Example) }
        
        raise ArgumentError, "All examples must be DSPy::Example instances. Legacy format support has been removed. Please convert your examples to use the structured format with :input and :expected keys."
      end

      # Generate successful examples through program execution
      sig do
        params(
          program: T.untyped,
          examples: T::Array[DSPy::Example],
          config: BootstrapConfig,
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
        ).returns([T::Array[DSPy::Example], T::Array[DSPy::Example]])
      end
      def self.generate_successful_examples(program, examples, config, metric)
        successful = []
        failed = []
        error_count = 0

        # Use DataHandler for efficient shuffling
        data_handler = DataHandler.new(examples)
        shuffled_examples = data_handler.shuffle(random_state: 42)

        shuffled_examples.each_with_index do |example, index|
          break if successful.size >= config.max_labeled_examples
          break if error_count >= config.max_errors

          begin
            # Run program on example input
            prediction = program.call(**example.input_values)
            
            # Check if prediction matches expected output
            prediction_hash = extract_output_fields_from_prediction(prediction, example.signature_class)
            
            if metric
              success = metric.call(example, prediction_hash)
            else
              success = example.matches_prediction?(prediction_hash)
            end

            if success
              # Create a new example with the successful prediction as reasoning/context
              successful_example = create_successful_bootstrap_example(example, prediction_hash)
              successful << successful_example
              
              emit_bootstrap_example_event(index, true, nil)
            else
              failed << example
              emit_bootstrap_example_event(index, false, "Prediction did not match expected output")
            end

          rescue => error
            error_count += 1
            failed << example
            emit_bootstrap_example_event(index, false, error.message)
            
            # Log error but continue processing
            DSPy.logger.warn("Bootstrap error on example #{index}: #{error.message}")
            
            # Stop if too many errors
            if error_count >= config.max_errors
              DSPy.logger.error("Too many bootstrap errors (#{error_count}), stopping early")
              break
            end
          end
        end

        [successful, failed]
      end

      # Create candidate sets from successful examples using efficient data handling
      sig do
        params(
          successful_examples: T::Array[DSPy::Example],
          config: BootstrapConfig
        ).returns(T::Array[T::Array[DSPy::Example]])
      end
      def self.create_candidate_sets(successful_examples, config)
        return [] if successful_examples.empty?

        # Use DataHandler for efficient sampling
        data_handler = DataHandler.new(successful_examples)
        set_size = [config.max_bootstrapped_examples, successful_examples.size].min

        # Create candidate sets efficiently
        candidate_sets = data_handler.create_candidate_sets(
          config.num_candidate_sets,
          set_size,
          random_state: 42  # For reproducible results
        )

        candidate_sets
      end

      # Create a bootstrap example that includes the successful prediction
      sig do
        params(
          original_example: DSPy::Example,
          prediction: T::Hash[Symbol, T.untyped]
        ).returns(DSPy::Example)
      end
      def self.create_successful_bootstrap_example(original_example, prediction)
        # Convert prediction to FewShotExample format
        DSPy::Example.new(
          signature_class: original_example.signature_class,
          input: original_example.input_values,
          expected: prediction,
          id: "bootstrap_#{original_example.id || SecureRandom.uuid}",
          metadata: {
            source: "bootstrap",
            original_expected: original_example.expected_values,
            bootstrap_timestamp: Time.now.iso8601
          }
        )
      end

      # Extract only output fields from prediction (exclude input fields)
      sig do
        params(
          prediction: T.untyped,
          signature_class: T.class_of(DSPy::Signature)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def self.extract_output_fields_from_prediction(prediction, signature_class)
        prediction_hash = prediction.to_h
        
        # Get output field names from signature
        output_fields = signature_class.output_field_descriptors.keys
        
        # Filter prediction to only include output fields
        filtered_expected = {}
        output_fields.each do |field_name|
          if prediction_hash.key?(field_name)
            filtered_expected[field_name] = prediction_hash[field_name]
          end
        end
        
        filtered_expected
      end

      # Create default metric for examples
      sig { params(examples: T::Array[T.untyped]).returns(T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))) }
      def self.default_metric_for_examples(examples)
        if examples.first.is_a?(DSPy::Example)
          proc { |example, prediction| example.matches_prediction?(prediction) }
        else
          nil
        end
      end

      # Emit bootstrap completion event
      sig { params(statistics: T::Hash[Symbol, T.untyped]).void }
      def self.emit_bootstrap_complete_event(statistics)
        DSPy.log('optimization.bootstrap_complete', **{
          'bootstrap.successful_count' => statistics[:successful_count],
          'bootstrap.failed_count' => statistics[:failed_count],
          'bootstrap.success_rate' => statistics[:success_rate],
          'bootstrap.candidate_sets_created' => statistics[:candidate_sets_created],
          'bootstrap.average_set_size' => statistics[:average_set_size]
        })
      end

      # Emit individual bootstrap example event
      sig { params(index: Integer, success: T::Boolean, error: T.nilable(String)).void }
      def self.emit_bootstrap_example_event(index, success, error)
        DSPy.log('optimization.bootstrap_example', **{
          'bootstrap.example_index' => index,
          'bootstrap.success' => success,
          'bootstrap.error' => error
        })
      end

      # Infer signature class from examples
      sig { params(examples: T::Array[T.untyped]).returns(T.nilable(T.class_of(Signature))) }
      def self.infer_signature_class(examples)
        return nil if examples.empty?

        first_example = examples.first
        
        if first_example.is_a?(DSPy::Example)
          first_example.signature_class
        elsif first_example.is_a?(Hash) && first_example[:signature_class]
          first_example[:signature_class]
        else
          nil
        end
      end
    end
  end
end