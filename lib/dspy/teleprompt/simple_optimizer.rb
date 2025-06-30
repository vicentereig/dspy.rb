# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'teleprompter'
require_relative 'utils'
require_relative '../propose/grounded_proposer'

module DSPy
  module Teleprompt
    # Simple optimization algorithm using random/grid search
    # Uses grounded proposer for instruction generation and bootstrap for examples
    class SimpleOptimizer < Teleprompter
      extend T::Sig

      # Configuration specific to simple optimization
      class OptimizerConfig < Config
        extend T::Sig

        sig { returns(Integer) }
        attr_accessor :num_trials

        sig { returns(String) }
        attr_accessor :search_strategy

        sig { returns(T::Boolean) }
        attr_accessor :use_instruction_optimization

        sig { returns(T::Boolean) }
        attr_accessor :use_few_shot_optimization

        sig { returns(DSPy::Propose::GroundedProposer::Config) }
        attr_accessor :proposer_config

        sig { void }
        def initialize
          super
          @num_trials = 10
          @search_strategy = "random" # or "grid"
          @use_instruction_optimization = true
          @use_few_shot_optimization = true
          @proposer_config = DSPy::Propose::GroundedProposer::Config.new
        end
      end

      # Result of a single optimization trial
      class TrialResult
        extend T::Sig

        sig { returns(Integer) }
        attr_reader :trial_number

        sig { returns(T.untyped) }
        attr_reader :program

        sig { returns(String) }
        attr_reader :instruction

        sig { returns(T::Array[T.untyped]) }
        attr_reader :few_shot_examples

        sig { returns(DSPy::Evaluate::BatchEvaluationResult) }
        attr_reader :evaluation_result

        sig { returns(Float) }
        attr_reader :score

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :metadata

        sig do
          params(
            trial_number: Integer,
            program: T.untyped,
            instruction: String,
            few_shot_examples: T::Array[T.untyped],
            evaluation_result: DSPy::Evaluate::BatchEvaluationResult,
            score: Float,
            metadata: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(trial_number:, program:, instruction:, few_shot_examples:, evaluation_result:, score:, metadata:)
          @trial_number = trial_number
          @program = program
          @instruction = instruction
          @few_shot_examples = few_shot_examples
          @evaluation_result = evaluation_result
          @score = score
          @metadata = metadata.freeze
        end

        sig { returns(T::Boolean) }
        def successful?
          @score > 0.0
        end
      end

      sig { returns(OptimizerConfig) }
      attr_reader :optimizer_config

      sig { returns(T.nilable(DSPy::Propose::GroundedProposer)) }
      attr_reader :proposer

      sig do
        params(
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
          config: T.nilable(OptimizerConfig)
        ).void
      end
      def initialize(metric: nil, config: nil)
        @optimizer_config = config || OptimizerConfig.new
        super(metric: metric, config: @optimizer_config)
        
        @proposer = if @optimizer_config.use_instruction_optimization
          DSPy::Propose::GroundedProposer.new(config: @optimizer_config.proposer_config)
        else
          nil
        end
      end

      # Main optimization method
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).returns(OptimizationResult)
      end
      def compile(program, trainset:, valset: nil)
        validate_inputs(program, trainset, valset)

        instrument_step('compile', {
          trainset_size: trainset.size,
          valset_size: valset&.size || 0,
          num_trials: @optimizer_config.num_trials,
          search_strategy: @optimizer_config.search_strategy
        }) do
          # Convert examples to typed format
          typed_trainset = ensure_typed_examples(trainset)
          typed_valset = valset ? ensure_typed_examples(valset) : nil

          # Use validation set if available, otherwise use part of training set
          evaluation_set = typed_valset || typed_trainset.take(10)

          # Bootstrap few-shot examples if enabled
          bootstrap_result = nil
          if @optimizer_config.use_few_shot_optimization
            bootstrap_result = bootstrap_examples(program, typed_trainset)
          end

          # Generate instruction candidates if enabled
          instruction_candidates = []
          if @optimizer_config.use_instruction_optimization && @proposer
            instruction_candidates = generate_instruction_candidates(program, typed_trainset, bootstrap_result)
          end

          # Run optimization trials
          trials = run_optimization_trials(
            program,
            evaluation_set,
            instruction_candidates,
            bootstrap_result
          )

          # Find best trial
          best_trial = find_best_trial(trials)

          # Build optimization result
          optimization_result = build_optimization_result(best_trial, trials)
          
          save_results(optimization_result)
          optimization_result
        end
      end

      private

      # Bootstrap few-shot examples from training set
      sig { params(program: T.untyped, trainset: T::Array[DSPy::Example]).returns(Utils::BootstrapResult) }
      def bootstrap_examples(program, trainset)
        bootstrap_config = Utils::BootstrapConfig.new
        bootstrap_config.max_bootstrapped_examples = @optimizer_config.max_bootstrapped_examples
        bootstrap_config.max_labeled_examples = @optimizer_config.max_labeled_examples
        bootstrap_config.num_candidate_sets = [@optimizer_config.num_trials / 2, 5].max
        bootstrap_config.max_errors = @optimizer_config.max_errors
        bootstrap_config.num_threads = @optimizer_config.num_threads

        Utils.create_n_fewshot_demo_sets(program, trainset, config: bootstrap_config, metric: @metric)
      end

      # Generate instruction candidates using the proposer
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[DSPy::Example],
          bootstrap_result: T.nilable(Utils::BootstrapResult)
        ).returns(T::Array[String])
      end
      def generate_instruction_candidates(program, trainset, bootstrap_result)
        return [] unless @proposer

        # Get current instruction if available
        current_instruction = extract_current_instruction(program)
        
        # Use few-shot examples from bootstrap if available
        few_shot_examples = bootstrap_result&.successful_examples&.take(5)

        # Get signature class from program
        signature_class = extract_signature_class(program)
        return [] unless signature_class

        proposal_result = @proposer.propose_instructions(
          signature_class,
          trainset,
          few_shot_examples: few_shot_examples,
          current_instruction: current_instruction
        )

        proposal_result.candidate_instructions
      end

      # Run optimization trials with different configurations
      sig do
        params(
          program: T.untyped,
          evaluation_set: T::Array[DSPy::Example],
          instruction_candidates: T::Array[String],
          bootstrap_result: T.nilable(Utils::BootstrapResult)
        ).returns(T::Array[TrialResult])
      end
      def run_optimization_trials(program, evaluation_set, instruction_candidates, bootstrap_result)
        trials = []
        
        # Generate trial configurations
        trial_configs = generate_trial_configurations(instruction_candidates, bootstrap_result)
        
        trial_configs.take(@optimizer_config.num_trials).each_with_index do |config, index|
          trial_number = index + 1
          
          emit_event('trial_start', {
            trial_number: trial_number,
            instruction: config[:instruction],
            num_few_shot: config[:few_shot_examples]&.size || 0
          })

          begin
            trial_result = run_single_trial(program, evaluation_set, config, trial_number)
            trials << trial_result

            emit_event('trial_complete', {
              trial_number: trial_number,
              score: trial_result.score,
              successful: trial_result.successful?,
              duration_ms: trial_result.metadata[:duration_ms] || 0
            })
          rescue => error
            emit_event('error', {
              trial_number: trial_number,
              error_type: error.class.name,
              error_message: error.message
            })
            
            DSPy.logger.error("Trial #{trial_number} failed: #{error.message}")
          end
        end

        trials
      end

      # Generate configurations for trials
      sig do
        params(
          instruction_candidates: T::Array[String],
          bootstrap_result: T.nilable(Utils::BootstrapResult)
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def generate_trial_configurations(instruction_candidates, bootstrap_result)
        configs = []
        
        # Base configuration (no changes)
        configs << { instruction: nil, few_shot_examples: [] }
        
        # Instruction-only trials
        instruction_candidates.each do |instruction|
          configs << { instruction: instruction, few_shot_examples: [] }
        end
        
        # Few-shot only trials
        if bootstrap_result&.candidate_sets&.any?
          bootstrap_result.candidate_sets.each do |candidate_set|
            configs << { instruction: nil, few_shot_examples: candidate_set }
          end
        end
        
        # Combined instruction + few-shot trials
        if instruction_candidates.any? && bootstrap_result&.candidate_sets&.any?
          instruction_candidates.take(3).each do |instruction|
            bootstrap_result.candidate_sets.take(2).each do |candidate_set|
              configs << { instruction: instruction, few_shot_examples: candidate_set }
            end
          end
        end
        
        # Shuffle for random strategy
        if @optimizer_config.search_strategy == "random"
          configs.shuffle
        else
          configs
        end
      end

      # Run a single optimization trial
      sig do
        params(
          program: T.untyped,
          evaluation_set: T::Array[DSPy::Example],
          config: T::Hash[Symbol, T.untyped],
          trial_number: Integer
        ).returns(TrialResult)
      end
      def run_single_trial(program, evaluation_set, config, trial_number)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        
        # Create modified program
        modified_program = apply_trial_configuration(program, config)
        
        # Evaluate the modified program
        evaluation_result = evaluate_program(modified_program, evaluation_set)
        
        # Calculate score (using pass_rate as primary metric)
        score = evaluation_result.pass_rate
        
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration_ms = ((end_time - start_time) * 1000).round(2)
        
        metadata = {
          duration_ms: duration_ms,
          num_examples_evaluated: evaluation_result.total_examples,
          instruction_length: config[:instruction]&.length || 0,
          num_few_shot_examples: config[:few_shot_examples]&.size || 0
        }
        
        TrialResult.new(
          trial_number: trial_number,
          program: modified_program,
          instruction: config[:instruction] || "",
          few_shot_examples: config[:few_shot_examples] || [],
          evaluation_result: evaluation_result,
          score: score,
          metadata: metadata
        )
      end

      # Apply trial configuration to program
      sig { params(program: T.untyped, config: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def apply_trial_configuration(program, config)
        modified_program = program
        
        # Apply instruction modification
        if config[:instruction] && respond_to_instruction_modification?(program)
          modified_program = apply_instruction_modification(modified_program, config[:instruction])
        end
        
        # Apply few-shot examples
        if config[:few_shot_examples]&.any? && respond_to_few_shot_modification?(program)
          modified_program = apply_few_shot_modification(modified_program, config[:few_shot_examples])
        end
        
        modified_program
      end

      # Apply instruction modification to program
      sig { params(program: T.untyped, instruction: String).returns(T.untyped) }
      def apply_instruction_modification(program, instruction)
        if program.respond_to?(:with_instruction)
          program.with_instruction(instruction)
        else
          program
        end
      end

      # Apply few-shot examples to program
      sig { params(program: T.untyped, examples: T::Array[T.untyped]).returns(T.untyped) }
      def apply_few_shot_modification(program, examples)
        if program.respond_to?(:with_examples)
          # Convert to FewShotExample format
          few_shot_examples = examples.map do |example|
            DSPy::FewShotExample.new(
              input: example.input_values,
              output: example.expected_values,
              reasoning: extract_reasoning_from_example(example)
            )
          end
          program.with_examples(few_shot_examples)
        else
          program
        end
      end

      # Find the best trial based on score
      sig { params(trials: T::Array[TrialResult]).returns(T.nilable(TrialResult)) }
      def find_best_trial(trials)
        return nil if trials.empty?
        
        trials.max_by(&:score)
      end

      # Build the final optimization result
      sig { params(best_trial: T.nilable(TrialResult), all_trials: T::Array[TrialResult]).returns(OptimizationResult) }
      def build_optimization_result(best_trial, all_trials)
        if best_trial
          scores = { pass_rate: best_trial.score }
          history = {
            total_trials: all_trials.size,
            successful_trials: all_trials.count(&:successful?),
            trial_scores: all_trials.map(&:score),
            best_trial_number: best_trial.trial_number
          }
          
          OptimizationResult.new(
            optimized_program: best_trial.program,
            scores: scores,
            history: history,
            best_score_name: "pass_rate",
            best_score_value: best_trial.score,
            metadata: {
              optimizer: "SimpleOptimizer",
              search_strategy: @optimizer_config.search_strategy,
              num_trials: @optimizer_config.num_trials,
              best_instruction: best_trial.instruction,
              best_num_few_shot: best_trial.few_shot_examples.size,
              optimization_timestamp: Time.now.iso8601
            }
          )
        else
          # No successful trials
          OptimizationResult.new(
            optimized_program: nil,
            scores: { pass_rate: 0.0 },
            history: { total_trials: all_trials.size, successful_trials: 0 },
            best_score_name: "pass_rate",
            best_score_value: 0.0,
            metadata: { optimizer: "SimpleOptimizer", error: "No successful trials" }
          )
        end
      end

      # Helper methods for program introspection
      sig { params(program: T.untyped).returns(T.nilable(String)) }
      def extract_current_instruction(program)
        if program.respond_to?(:prompt) && program.prompt.respond_to?(:instruction)
          program.prompt.instruction
        elsif program.respond_to?(:system_signature)
          # Try to extract from system signature
          system_sig = program.system_signature
          system_sig.is_a?(String) ? system_sig : nil
        else
          nil
        end
      end

      sig { params(program: T.untyped).returns(T.nilable(T.class_of(DSPy::Signature))) }
      def extract_signature_class(program)
        if program.respond_to?(:signature_class)
          program.signature_class
        else
          nil
        end
      end

      sig { params(program: T.untyped).returns(T::Boolean) }
      def respond_to_instruction_modification?(program)
        program.respond_to?(:with_instruction)
      end

      sig { params(program: T.untyped).returns(T::Boolean) }
      def respond_to_few_shot_modification?(program)
        program.respond_to?(:with_examples)
      end

      sig { params(example: T.untyped).returns(T.nilable(String)) }
      def extract_reasoning_from_example(example)
        case example
        when DSPy::Example
          if example.expected_values.key?(:reasoning)
            example.expected_values[:reasoning]
          elsif example.expected_values.key?(:explanation)
            example.expected_values[:explanation]
          else
            nil
          end
        else
          nil
        end
      end
    end
  end
end