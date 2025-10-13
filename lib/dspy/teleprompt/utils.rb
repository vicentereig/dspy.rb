# frozen_string_literal: true

require 'sorbet-runtime'
require 'fileutils'
require_relative '../evaluate'
require_relative '../example'
require_relative 'data_handler'

module DSPy
  module Teleprompt
    # Bootstrap utilities for MIPROv2 optimization
    # Handles few-shot example generation and candidate program evaluation
    module Utils
      extend T::Sig

      # Wrapper class that provides Python-compatible signature API
      # Wraps a Predict instance to provide signature access and modification
      class SignatureWrapper
        extend T::Sig

        sig { returns(T.untyped) }
        attr_reader :predictor

        sig { params(predictor: T.untyped).void }
        def initialize(predictor)
          @predictor = predictor
        end

        sig { returns(String) }
        def instructions
          # Get instructions from the predictor's prompt
          @predictor.prompt.instruction
        end

        sig { params(new_instructions: String).returns(SignatureWrapper) }
        def with_instructions(new_instructions)
          # Return a new wrapper that will apply new instructions when set
          updated_wrapper = SignatureWrapper.new(@predictor)
          updated_wrapper.instance_variable_set(:@pending_instructions, new_instructions)
          updated_wrapper
        end

        sig { returns(T.nilable(String)) }
        def pending_instructions
          @pending_instructions
        end
      end

      # Get signature information from a predictor (Python compatibility)
      # Returns a wrapper that provides Python-like signature API
      #
      # @param predictor [Predict] The predictor to get signature from
      # @return [SignatureWrapper] Wrapper providing signature access
      sig { params(predictor: T.untyped).returns(SignatureWrapper) }
      def self.get_signature(predictor)
        SignatureWrapper.new(predictor)
      end

      # Set signature on a predictor (Python compatibility)
      # Updates the predictor's prompt with new instructions
      #
      # @param predictor [Predict] The predictor to update
      # @param updated_signature [SignatureWrapper] The updated signature wrapper
      sig { params(predictor: T.untyped, updated_signature: SignatureWrapper).void }
      def self.set_signature(predictor, updated_signature)
        # Extract pending instructions from the wrapper
        new_instructions = updated_signature.pending_instructions

        if new_instructions
          # Update the predictor's prompt with new instructions
          # We mutate the prompt's instruction directly for MIPROv2 compatibility
          predictor.prompt.instance_variable_set(:@instruction, new_instructions)
        end
      end

      # Create a minibatch from the trainset using random sampling
      # This function is compatible with Python DSPy's MIPROv2 implementation
      #
      # @param trainset [Array] The training dataset to sample from
      # @param batch_size [Integer] The desired size of the minibatch (default: 50)
      # @param rng [Random, nil] Optional random number generator for reproducible sampling
      # @return [Array] A randomly sampled subset of the trainset
      sig do
        params(
          trainset: T::Array[T.untyped],
          batch_size: Integer,
          rng: T.nilable(Random)
        ).returns(T::Array[T.untyped])
      end
      def self.create_minibatch(trainset, batch_size = 50, rng = nil)
        # Ensure batch_size isn't larger than the size of the dataset
        actual_batch_size = [batch_size, trainset.size].min

        # Randomly sample from trainset
        # If RNG is provided, use it for reproducible sampling
        if rng
          trainset.sample(actual_batch_size, random: rng)
        else
          trainset.sample(actual_batch_size)
        end
      end

      # Get program with highest average score from minibatch trials
      # Used as a helper function for Bayesian + minibatching optimizers
      #
      # @param param_score_dict [Hash] Maps combo keys to arrays of [score, program, params] tuples
      # @param fully_evaled_param_combos [Array] List of combo keys that have been fully evaluated
      # @return [Array] Returns [program, mean_score, combo_key, params]
      sig do
        params(
          param_score_dict: T::Hash[String, T::Array[T::Array[T.untyped]]],
          fully_evaled_param_combos: T::Array[String]
        ).returns([T.untyped, Float, String, T::Hash[Symbol, T.untyped]])
      end
      def self.get_program_with_highest_avg_score(param_score_dict, fully_evaled_param_combos)
        # Calculate the mean for each combination of categorical parameters, based on past trials
        results = []
        param_score_dict.each do |key, values|
          scores = values.map { |v| v[0] }
          mean = scores.sum.to_f / scores.size
          program = values[0][1]
          params = values[0][2]
          results << [key, mean, program, params]
        end

        # Sort results by the mean in descending order
        sorted_results = results.sort_by { |_key, mean, _program, _params| -mean }

        # Find the combination with the highest mean, skip fully evaluated ones
        sorted_results.each do |key, mean, program, params|
          next if fully_evaled_param_combos.include?(key)
          return [program, mean, key, params]
        end

        # If no valid program is found, return the last valid one
        _key, mean, program, params = sorted_results.last
        [program, mean, _key, params]
      end

      # Save a candidate program to the log directory
      # Used during optimization to save intermediate trial results
      #
      # @param program [Module] The program to save
      # @param log_dir [String, nil] The directory to save to (returns nil if nil)
      # @param trial_num [Integer] The trial number for naming the file
      # @param note [String, nil] Optional note to append to filename
      # @return [String, nil] The path where program was saved, or nil if log_dir is nil
      sig do
        params(
          program: T.untyped,
          log_dir: T.nilable(String),
          trial_num: Integer,
          note: T.nilable(String)
        ).returns(T.nilable(String))
      end
      def self.save_candidate_program(program, log_dir, trial_num, note: nil)
        return nil if log_dir.nil?

        # Ensure the directory exists
        eval_programs_dir = File.join(log_dir, "evaluated_programs")
        FileUtils.mkdir_p(eval_programs_dir) unless Dir.exist?(eval_programs_dir)

        # Define the save path for the program
        filename = if note
          "program_#{trial_num}_#{note}.json"
        else
          "program_#{trial_num}.json"
        end
        save_path = File.join(eval_programs_dir, filename)

        # Save the program
        program.save(save_path)

        save_path
      end

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

      # Create multiple candidate sets of few-shot demonstrations using different bootstrap strategies
      #
      # This is the Python-compatible implementation that uses a seed-based loop to create
      # demo sets using 4 strategies: ZeroShot (-3), LabeledOnly (-2), Unshuffled (-1), and Shuffled (>=0)
      #
      # @param student [DSPy::Module] The student program to bootstrap
      # @param num_candidate_sets [Integer] Number of demo sets to create (accounts for special seeds)
      # @param trainset [Array<DSPy::Example>] Training examples
      # @param max_bootstrapped_demos [Integer] Maximum bootstrapped demonstrations per set
      # @param max_labeled_demos [Integer] Maximum labeled demonstrations to prepend
      # @param min_num_samples [Integer] Minimum number of samples for shuffled strategy
      # @param metric [Proc] Optional metric to validate bootstrapped examples
      # @param teacher_settings [Hash] Settings for teacher program (future use)
      # @param seed [Integer] Random seed for reproducibility
      # @param include_non_bootstrapped [Boolean] Include ZeroShot and LabeledOnly strategies
      # @param labeled_sample [Boolean] Whether to sample labeled examples randomly
      # @return [Hash{Integer => Array<Array<DSPy::FewShotExample>>}] Map of predictor index to demo sets
      sig do
        params(
          student: T.untyped,
          num_candidate_sets: Integer,
          trainset: T::Array[T.untyped],
          max_bootstrapped_demos: Integer,
          max_labeled_demos: Integer,
          min_num_samples: Integer,
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean)),
          teacher_settings: T::Hash[Symbol, T.untyped],
          seed: T.nilable(Integer),
          include_non_bootstrapped: T::Boolean,
          labeled_sample: T::Boolean
        ).returns(T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]])
      end
      def self.create_n_fewshot_demo_sets(
        student,
        num_candidate_sets,
        trainset,
        max_bootstrapped_demos: 3,
        max_labeled_demos: 3,
        min_num_samples: 1,
        metric: nil,
        teacher_settings: {},
        seed: nil,
        include_non_bootstrapped: true,
        labeled_sample: true
      )
        demo_candidates = Hash.new { |h, k| h[k] = [] }
        rng = seed ? Random.new(seed) : Random.new

        # Get number of predictors (simplified: assume single predictor)
        num_predictors = 1

        # Adjust for 3 special seeds (-3, -2, -1)
        adjusted_num_sets = num_candidate_sets - 3

        # Loop from -3 to adjusted_num_sets (exclusive)
        (-3...adjusted_num_sets).each do |current_seed|
          case current_seed
          when -3  # ZeroShot strategy
            next unless include_non_bootstrapped
            # Empty demo sets for all predictors
            num_predictors.times { |idx| demo_candidates[idx] << [] }

          when -2  # LabeledOnly strategy
            next unless include_non_bootstrapped && max_labeled_demos > 0
            # Sample or take labeled examples
            labeled_demos = create_labeled_demos(trainset, max_labeled_demos, labeled_sample, rng)
            num_predictors.times { |idx| demo_candidates[idx] << labeled_demos }

          when -1  # Unshuffled strategy
            # Bootstrap without shuffle
            bootstrapped_demos = create_bootstrapped_demos(
              student, trainset, max_bootstrapped_demos, max_labeled_demos, metric
            )
            num_predictors.times { |idx| demo_candidates[idx] << bootstrapped_demos }

          else  # Shuffled strategies (seed >= 0)
            # Shuffle trainset with current seed
            seed_rng = Random.new(current_seed)
            shuffled_trainset = trainset.shuffle(random: seed_rng)

            # Random demo count between min and max
            num_demos = seed_rng.rand(min_num_samples..max_bootstrapped_demos)

            # Bootstrap with shuffled data
            bootstrapped_demos = create_bootstrapped_demos(
              student, shuffled_trainset, num_demos, max_labeled_demos, metric
            )
            num_predictors.times { |idx| demo_candidates[idx] << bootstrapped_demos }
          end
        end

        demo_candidates
      end

      # Create labeled demonstrations from trainset examples
      sig do
        params(
          trainset: T::Array[T.untyped],
          max_labeled: Integer,
          labeled_sample: T::Boolean,
          rng: Random
        ).returns(T::Array[DSPy::FewShotExample])
      end
      def self.create_labeled_demos(trainset, max_labeled, labeled_sample, rng)
        examples = if labeled_sample
          trainset.sample([max_labeled, trainset.size].min, random: rng)
        else
          trainset.take(max_labeled)
        end

        examples.map do |ex|
          DSPy::FewShotExample.new(
            input: ex.input_values,
            output: ex.expected_values
          )
        end
      end

      # Create bootstrapped demonstrations by executing student on trainset
      sig do
        params(
          student: T.untyped,
          trainset: T::Array[T.untyped],
          max_bootstrapped: Integer,
          max_labeled: Integer,
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
        ).returns(T::Array[DSPy::FewShotExample])
      end
      def self.create_bootstrapped_demos(student, trainset, max_bootstrapped, max_labeled, metric)
        successful_demos = []

        # Execute student on trainset to bootstrap demonstrations
        trainset.each do |example|
          break if successful_demos.size >= max_bootstrapped

          begin
            # Call student with input
            prediction = student.call(**example.input_values)
            prediction_hash = prediction.respond_to?(:to_h) ? prediction.to_h : prediction

            # Check if prediction matches expected output
            success = if metric
              metric.call(example, prediction_hash)
            else
              example.matches_prediction?(prediction_hash)
            end

            if success
              # Extract only output fields from prediction
              output_fields = extract_output_fields_for_demo(prediction_hash, example.signature_class)

              demo = DSPy::FewShotExample.new(
                input: example.input_values,
                output: output_fields
              )
              successful_demos << demo
            end
          rescue => e
            # Continue on errors
            DSPy.logger.warn("Bootstrap error: #{e.message}") if DSPy.logger
          end
        end

        # Prepend labeled examples if requested
        if max_labeled > 0
          labeled = trainset.take(max_labeled).map do |ex|
            DSPy::FewShotExample.new(
              input: ex.input_values,
              output: ex.expected_values
            )
          end
          successful_demos = labeled + successful_demos
        end

        successful_demos
      end

      # Extract only output fields from prediction hash
      sig do
        params(
          prediction_hash: T::Hash[Symbol, T.untyped],
          signature_class: T.class_of(DSPy::Signature)
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def self.extract_output_fields_for_demo(prediction_hash, signature_class)
        output_field_names = signature_class.output_field_descriptors.keys
        prediction_hash.slice(*output_field_names)
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