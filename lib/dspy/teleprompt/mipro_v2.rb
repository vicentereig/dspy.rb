# frozen_string_literal: true

require 'digest'
require 'time'
require 'concurrent-ruby'
require 'sorbet-runtime'
require 'securerandom'
require_relative 'teleprompter'
require_relative 'utils'
require_relative '../propose/grounded_proposer'
require_relative '../optimizers/gaussian_process'

module DSPy
  module Teleprompt
    # Enum for candidate configuration types
    class CandidateType < T::Enum
      enums do
        Baseline = new("baseline")
        InstructionOnly = new("instruction_only")
        FewShotOnly = new("few_shot_only")
        Combined = new("combined")
      end
    end

    # Enum for optimization strategies
    class OptimizationStrategy < T::Enum
      enums do
        Greedy = new("greedy")
        Adaptive = new("adaptive") 
        Bayesian = new("bayesian")
      end
    end
    # MIPROv2: Multi-prompt Instruction Proposal with Retrieval Optimization
    # State-of-the-art prompt optimization combining bootstrap sampling, 
    # instruction generation, and Bayesian optimization
    class MIPROv2 < Teleprompter
      extend T::Sig
      include Dry::Configurable

      # Auto-configuration modes for different optimization needs
      module AutoMode
        extend T::Sig

        sig do
          params(
            metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
            kwargs: T.untyped
          ).returns(MIPROv2)
        end
        def self.light(metric: nil, **kwargs)
          optimizer = MIPROv2.new(metric: metric, **kwargs)
          optimizer.configure do |config|
            config.num_trials = 6
            config.num_instruction_candidates = 3
            config.max_bootstrapped_examples = 2
            config.max_labeled_examples = 8
            config.bootstrap_sets = 3
            config.optimization_strategy = :greedy
            config.early_stopping_patience = 2
          end
          optimizer
        end

        sig do
          params(
            metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
            kwargs: T.untyped
          ).returns(MIPROv2)
        end
        def self.medium(metric: nil, **kwargs)
          optimizer = MIPROv2.new(metric: metric, **kwargs)
          optimizer.configure do |config|
            config.num_trials = 12
            config.num_instruction_candidates = 5
            config.max_bootstrapped_examples = 4
            config.max_labeled_examples = 16
            config.bootstrap_sets = 5
            config.optimization_strategy = :adaptive
            config.early_stopping_patience = 3
          end
          optimizer
        end

        sig do
          params(
            metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
            kwargs: T.untyped
          ).returns(MIPROv2)
        end
        def self.heavy(metric: nil, **kwargs)
          optimizer = MIPROv2.new(metric: metric, **kwargs)
          optimizer.configure do |config|
            config.num_trials = 18
            config.num_instruction_candidates = 8
            config.max_bootstrapped_examples = 6
            config.max_labeled_examples = 24
            config.bootstrap_sets = 8
            config.optimization_strategy = :bayesian
            config.early_stopping_patience = 5
          end
          optimizer
        end
      end

      # Dry-configurable settings for MIPROv2
      setting :num_trials, default: 12
      setting :num_instruction_candidates, default: 5
      setting :bootstrap_sets, default: 5
      setting :max_bootstrapped_examples, default: 4
      setting :max_labeled_examples, default: 16
      setting :optimization_strategy, default: OptimizationStrategy::Adaptive, constructor: ->(value) {
        # Coerce symbols to enum values
        case value
        when :greedy then OptimizationStrategy::Greedy
        when :adaptive then OptimizationStrategy::Adaptive
        when :bayesian then OptimizationStrategy::Bayesian
        when OptimizationStrategy then value
        when nil then OptimizationStrategy::Adaptive
        else
          raise ArgumentError, "Invalid optimization strategy: #{value}. Must be one of :greedy, :adaptive, :bayesian"
        end
      }
      setting :init_temperature, default: 1.0
      setting :final_temperature, default: 0.1
      setting :early_stopping_patience, default: 3
      setting :use_bayesian_optimization, default: true
      setting :track_diversity, default: true
      setting :max_errors, default: 3
      setting :num_threads, default: 1
      setting :minibatch_size, default: nil

      # Class-level configuration method - sets defaults for new instances
      def self.configure(&block)
        if block_given?
          # Store configuration in a class variable for new instances
          @default_config_block = block
        end
      end

      # Get the default configuration block
      def self.default_config_block
        @default_config_block
      end


      # Simple data structure for evaluated candidate configurations (immutable)
      EvaluatedCandidate = Data.define(
        :instruction,
        :few_shot_examples,
        :type,
        :metadata,
        :config_id
      ) do
        extend T::Sig
        
        # Generate a config ID based on content
        sig { params(instruction: String, few_shot_examples: T::Array[T.untyped], type: CandidateType, metadata: T::Hash[Symbol, T.untyped]).returns(EvaluatedCandidate) }
        def self.create(instruction:, few_shot_examples: [], type: CandidateType::Baseline, metadata: {})
          content = "#{instruction}_#{few_shot_examples.size}_#{type.serialize}_#{metadata.hash}"
          config_id = Digest::SHA256.hexdigest(content)[0, 12]
          
          new(
            instruction: instruction.freeze,
            few_shot_examples: few_shot_examples.freeze,
            type: type,
            metadata: metadata.freeze,
            config_id: config_id
          )
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            instruction: instruction,
            few_shot_examples: few_shot_examples.size,
            type: type.serialize,
            metadata: metadata,
            config_id: config_id
          }
        end
      end

      # Result of MIPROv2 optimization
      class MIPROv2Result < OptimizationResult
        extend T::Sig

        sig { returns(T::Array[EvaluatedCandidate]) }
        attr_reader :evaluated_candidates

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :optimization_trace

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :bootstrap_statistics

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :proposal_statistics

        sig { returns(T.nilable(DSPy::Evaluate::BatchEvaluationResult)) }
        attr_reader :best_evaluation_result

        sig do
          params(
            optimized_program: T.untyped,
            scores: T::Hash[Symbol, T.untyped],
            history: T::Hash[Symbol, T.untyped],
            evaluated_candidates: T::Array[EvaluatedCandidate],
            optimization_trace: T::Hash[Symbol, T.untyped],
            bootstrap_statistics: T::Hash[Symbol, T.untyped],
            proposal_statistics: T::Hash[Symbol, T.untyped],
            best_score_name: T.nilable(String),
            best_score_value: T.nilable(Float),
            metadata: T::Hash[Symbol, T.untyped],
            best_evaluation_result: T.nilable(DSPy::Evaluate::BatchEvaluationResult)
          ).void
        end
        def initialize(optimized_program:, scores:, history:, evaluated_candidates:, optimization_trace:, bootstrap_statistics:, proposal_statistics:, best_score_name: nil, best_score_value: nil, metadata: {}, best_evaluation_result: nil)
          super(
            optimized_program: optimized_program,
            scores: scores,
            history: history,
            best_score_name: best_score_name,
            best_score_value: best_score_value,
            metadata: metadata
          )
          @evaluated_candidates = evaluated_candidates.freeze
          @optimization_trace = optimization_trace.freeze
          @bootstrap_statistics = bootstrap_statistics.freeze
          @proposal_statistics = proposal_statistics.freeze
          @best_evaluation_result = best_evaluation_result&.freeze
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          super.merge({
            evaluated_candidates: @evaluated_candidates.map(&:to_h),
            optimization_trace: @optimization_trace,
            bootstrap_statistics: @bootstrap_statistics,
            proposal_statistics: @proposal_statistics,
            best_evaluation_result: @best_evaluation_result&.to_h
          })
        end
      end

      sig { returns(MIPROv2Config) }
      attr_reader :mipro_config

      sig { returns(T.nilable(DSPy::Propose::GroundedProposer)) }
      attr_reader :proposer

      # Override dry-configurable's initialize to add our parameter validation
      def initialize(metric: nil, **kwargs)
        # Reject old config parameter pattern
        if kwargs.key?(:config)
          raise ArgumentError, "config parameter is no longer supported. Use .configure blocks instead."
        end
        
        # Let dry-configurable handle its initialization
        super(**kwargs)
        
        # Apply class-level configuration if it exists
        if self.class.default_config_block
          configure(&self.class.default_config_block)
        end
        
        @metric = metric
        
        # Initialize proposer with a basic config for now (will be updated later)  
        @proposer = DSPy::Propose::GroundedProposer.new(config: DSPy::Propose::GroundedProposer::Config.new)
        @optimization_trace = []
        @evaluated_candidates = []
        @trial_history = {}
      end

      # Main MIPROv2 optimization method
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).returns(MIPROv2Result)
      end
      def compile(program, trainset:, valset: nil)
        validate_inputs(program, trainset, valset)

        instrument_step('miprov2_compile', {
          trainset_size: trainset.size,
          valset_size: valset&.size || 0,
          num_trials: config.num_trials,
          optimization_strategy: config.optimization_strategy,
          mode: infer_auto_mode
        }) do
          # Convert examples to typed format
          typed_trainset = ensure_typed_examples(trainset)
          typed_valset = valset ? ensure_typed_examples(valset) : nil

          # Use validation set if available, otherwise use part of training set
          evaluation_set = typed_valset || typed_trainset.take([typed_trainset.size / 3, 10].max)

          # Phase 1: Bootstrap few-shot examples
          emit_event('phase_start', { phase: 1, name: 'bootstrap' })
          demo_candidates = phase_1_bootstrap(program, typed_trainset)
          emit_event('phase_complete', {
            phase: 1,
            num_predictors: demo_candidates.keys.size,
            demo_sets_per_predictor: demo_candidates[0]&.size || 0
          })

          # Phase 2: Generate instruction candidates
          emit_event('phase_start', { phase: 2, name: 'instruction_proposal' })
          proposal_result = phase_2_propose_instructions(program, typed_trainset, demo_candidates)
          emit_event('phase_complete', {
            phase: 2,
            num_candidates: proposal_result.num_candidates,
            best_instruction_preview: proposal_result.best_instruction[0, 50]
          })

          # Phase 3: Bayesian optimization
          emit_event('phase_start', { phase: 3, name: 'optimization' })
          optimization_result = phase_3_optimize(
            program,
            evaluation_set,
            proposal_result,
            demo_candidates
          )
          emit_event('phase_complete', { 
            phase: 3, 
            best_score: optimization_result[:best_score],
            trials_completed: optimization_result[:trials_completed]
          })

          # Build final result
          final_result = build_miprov2_result(
            optimization_result,
            demo_candidates,
            proposal_result
          )

          @trial_history = optimization_result[:trial_logs] || {}

          save_results(final_result)
          final_result
        end
      end

      private

      # Phase 1: Bootstrap few-shot examples from training data
      # Returns a hash mapping predictor indices to arrays of demo sets
      sig { params(program: T.untyped, trainset: T::Array[DSPy::Example]).returns(T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]]) }
      def phase_1_bootstrap(program, trainset)
        Utils.create_n_fewshot_demo_sets(
          program,
          config.bootstrap_sets,  # num_candidate_sets
          trainset,
          max_bootstrapped_demos: config.max_bootstrapped_examples,
          max_labeled_demos: config.max_labeled_examples,
          metric: @metric
        )
      end

      # Phase 2: Generate instruction candidates using grounded proposer
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[DSPy::Example],
          demo_candidates: T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]]
        ).returns(DSPy::Propose::GroundedProposer::ProposalResult)
      end
      def phase_2_propose_instructions(program, trainset, demo_candidates)
        # Get current instruction if available
        current_instruction = extract_current_instruction(program)

        # Use few-shot examples from bootstrap if available
        # Flatten demo sets from first predictor and take first 5 examples
        few_shot_examples = demo_candidates[0]&.flatten&.take(5) || []

        # Re-initialize proposer with program and trainset for awareness features
        # This enables program_aware and use_dataset_summary flags to work correctly
        proposer_config = DSPy::Propose::GroundedProposer::Config.new
        proposer_config.num_instruction_candidates = config.num_instruction_candidates

        @proposer = DSPy::Propose::GroundedProposer.new(
          config: proposer_config,
          program: program,
          trainset: trainset
        )

        @proposer.propose_instructions_for_program(
          trainset: trainset,
          program: program,
          demo_candidates: demo_candidates,
          trial_logs: @trial_history,
          num_instruction_candidates: config.num_instruction_candidates
        )
      end

      # Phase 3: Bayesian optimization to find best configuration
      sig do
        params(
          program: T.untyped,
          evaluation_set: T::Array[DSPy::Example],
          proposal_result: DSPy::Propose::GroundedProposer::ProposalResult,
          demo_candidates: T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]]
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def phase_3_optimize(program, evaluation_set, proposal_result, demo_candidates)
        # Generate candidate configurations
        candidates = generate_candidate_configurations(proposal_result, demo_candidates)
        
        # Initialize optimization state
        optimization_state = initialize_optimization_state(candidates)

        # Initialize trial tracking structures
        trial_logs = {}
        param_score_dict = Hash.new { |hash, key| hash[key] = [] }
        fully_evaled_param_combos = {}
        total_eval_calls = 0

        # Run optimization trials
        trials_completed = 0
        best_score = 0.0
        best_candidate = nil
        best_program = program
        best_evaluation_result = nil
        
        config.num_trials.times do |trial_idx|
          trials_completed = trial_idx + 1
          
          # Select next candidate based on optimization strategy
          candidate = select_next_candidate(candidates, optimization_state, trial_idx)
          batch_size = evaluation_set.size

          trial_logs[trials_completed] = create_trial_log_entry(
            trial_number: trials_completed,
            candidate: candidate,
            evaluation_type: :full,
            batch_size: batch_size
          )
          
          emit_event('trial_start', {
            trial_number: trials_completed,
            candidate_id: candidate.config_id,
            instruction_preview: candidate.instruction[0, 50],
            num_few_shot: candidate.few_shot_examples.size
          })

          begin
            # Evaluate candidate
            score, modified_program, evaluation_result = evaluate_candidate(program, candidate, evaluation_set)
            total_eval_calls += batch_size

            instructions_snapshot = extract_program_instructions(modified_program)
            trial_logs[trials_completed][:instructions] = instructions_snapshot unless instructions_snapshot.empty?
            trial_logs[trials_completed][:instruction] = instructions_snapshot[0] if instructions_snapshot.key?(0)
            
            # Update optimization state
            update_optimization_state(optimization_state, candidate, score)
            record_param_score(
              param_score_dict,
              candidate,
              score,
              evaluation_type: :full,
              instructions: instructions_snapshot
            )
            update_fully_evaled_param_combos(
              fully_evaled_param_combos,
              candidate,
              score,
              instructions: instructions_snapshot
            )
            
            # Track best result
            is_best = best_candidate.nil? || score > best_score
            if is_best
              best_score = score
              best_candidate = candidate
              best_program = modified_program
              best_evaluation_result = evaluation_result
            end

            finalize_trial_log_entry(
              trial_logs,
              trials_completed,
              score: score,
              evaluation_type: :full,
              batch_size: batch_size,
              total_eval_calls: total_eval_calls
            )

            emit_event('trial_complete', {
              trial_number: trials_completed,
              score: score,
              is_best: is_best,
              candidate_id: candidate.config_id
            })

            # Check early stopping
            if should_early_stop?(optimization_state, trial_idx)
              DSPy.logger.info("Early stopping at trial #{trials_completed}")
              break
            end

          rescue => error
            finalize_trial_log_entry(
              trial_logs,
              trials_completed,
              score: nil,
              evaluation_type: :full,
              batch_size: batch_size,
              total_eval_calls: total_eval_calls,
              error: error.message
            )

            emit_event('trial_error', {
              trial_number: trials_completed,
              error: error.message,
              candidate_id: candidate.config_id
            })
            
            DSPy.logger.warn("Trial #{trials_completed} failed: #{error.message}")
          end
        end

        {
          best_score: best_score,
          best_candidate: best_candidate,
          best_program: best_program,
          best_evaluation_result: best_evaluation_result,
          trials_completed: trials_completed,
          optimization_state: optimization_state,
          evaluated_candidates: @evaluated_candidates,
          trial_logs: trial_logs,
          param_score_dict: param_score_dict,
          fully_evaled_param_combos: fully_evaled_param_combos,
          total_eval_calls: total_eval_calls
        }
      end

      # Generate candidate configurations from proposals and demo candidates
      sig do
        params(
          proposal_result: DSPy::Propose::GroundedProposer::ProposalResult,
          demo_candidates: T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]]
        ).returns(T::Array[EvaluatedCandidate])
      end
      def generate_candidate_configurations(proposal_result, demo_candidates)
        candidates = []

        predictor_instruction_map = if proposal_result.respond_to?(:predictor_instructions) && proposal_result.predictor_instructions.any?
          proposal_result.predictor_instructions
        else
          { 0 => proposal_result.candidate_instructions }
        end

        instruction_maps = build_instruction_maps(predictor_instruction_map)
        demo_maps = build_demo_maps(demo_candidates)

        # Base configuration (no modifications)
        candidates << EvaluatedCandidate.new(
          instruction: "",
          few_shot_examples: [],
          type: CandidateType::Baseline,
          metadata: {
            instructions_map: {},
            demos_map: {}
          },
          config_id: SecureRandom.hex(6)
        )

        instruction_maps.each_with_index do |instruction_map, combo_idx|
          primary_instruction = instruction_map[0] || instruction_map.values.first || ""
          candidates << EvaluatedCandidate.new(
            instruction: primary_instruction,
            few_shot_examples: [],
            type: CandidateType::InstructionOnly,
            metadata: {
              proposal_rank: combo_idx,
              instructions_map: duplicate_instruction_map(instruction_map),
              demos_map: {}
            },
            config_id: SecureRandom.hex(6)
          )
        end

        demo_maps.each_with_index do |demo_map, idx|
          next if demo_map.empty?

          flattened_examples = demo_map.values.flatten
          candidates << EvaluatedCandidate.new(
            instruction: "",
            few_shot_examples: flattened_examples,
            type: CandidateType::FewShotOnly,
            metadata: {
              bootstrap_rank: idx,
              instructions_map: {},
              demos_map: duplicate_demo_map(demo_map)
            },
            config_id: SecureRandom.hex(6)
          )
        end
        
        # Combined candidates (instruction + few-shot)
        instruction_maps.each_with_index do |instruction_map, combo_idx|
          primary_instruction = instruction_map[0] || instruction_map.values.first || ""
          demo_maps.first(3).each_with_index do |demo_map, demo_idx|
            next if demo_map.empty?

            flattened_examples = demo_map.values.flatten
            candidates << EvaluatedCandidate.new(
              instruction: primary_instruction,
              few_shot_examples: flattened_examples,
              type: CandidateType::Combined,
              metadata: {
                instruction_rank: combo_idx,
                bootstrap_rank: demo_idx,
                instructions_map: duplicate_instruction_map(instruction_map),
                demos_map: duplicate_demo_map(demo_map)
              },
              config_id: SecureRandom.hex(6)
            )
          end
        end

        candidates
      end

      sig { params(predictor_instruction_map: T::Hash[Integer, T::Array[String]]).returns(T::Array[T::Hash[Integer, String]]) }
      def build_instruction_maps(predictor_instruction_map)
        return [{}] if predictor_instruction_map.nil? || predictor_instruction_map.empty?

        normalized = predictor_instruction_map.each_with_object({}) do |(index, instructions), memo|
          next if instructions.nil? || instructions.empty?
          memo[index] = instructions.take(3)
        end

        return [{}] if normalized.empty?

        cartesian_product(normalized)
      end

      sig do
        params(demo_candidates: T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]]).returns(T::Array[T::Hash[Integer, T::Array[DSPy::FewShotExample]]])
      end
      def build_demo_maps(demo_candidates)
        return [{}] if demo_candidates.nil? || demo_candidates.empty?

        normalized = demo_candidates.each_with_object({}) do |(index, sets), memo|
          next if sets.nil? || sets.empty?
          memo[index] = sets.take(3)
        end

        return [{}] if normalized.empty?

        cartesian_product(normalized)
      end

      sig do
        params(options_hash: T::Hash[Integer, T::Array[T.untyped]]).returns(T::Array[T::Hash[Integer, T.untyped]])
      end
      def cartesian_product(options_hash)
        options_hash.sort_by { |index, _| index }.reduce([{}]) do |acc, (index, values)|
          next acc if values.nil? || values.empty?

          acc.flat_map do |existing|
            values.map do |value|
              existing.merge(index => value)
            end
          end
        end
      end

      sig { params(instruction_map: T::Hash[Integer, String]).returns(T::Hash[Integer, String]) }
      def duplicate_instruction_map(instruction_map)
        instruction_map.each_with_object({}) do |(index, instruction), memo|
          memo[index] = instruction.is_a?(String) ? instruction.dup : instruction
        end
      end

      sig do
        params(demo_map: T::Hash[Integer, T::Array[DSPy::FewShotExample]]).returns(T::Hash[Integer, T::Array[DSPy::FewShotExample]])
      end
      def duplicate_demo_map(demo_map)
        demo_map.each_with_object({}) do |(index, demos), memo|
          next if demos.nil?
          memo[index] = demos.map { |demo| demo }
        end
      end

      sig { params(examples: T::Array[T.untyped]).returns(T::Array[DSPy::FewShotExample]) }
      def normalize_few_shot_examples(examples)
        examples.map do |example|
          if example.is_a?(DSPy::FewShotExample)
            example
          elsif example.is_a?(DSPy::Example)
            DSPy::FewShotExample.new(
              input: example.input_values,
              output: example.expected_values,
              reasoning: extract_reasoning_from_example(example)
            )
          else
            example
          end
        end
      end

      sig { params(predictor: T.untyped, examples: T::Array[DSPy::FewShotExample]).void }
      def assign_predictor_examples(predictor, examples)
        predictor.demos = examples if predictor.respond_to?(:demos=)
        return unless predictor.respond_to?(:prompt)

        cloned_examples = examples.map { |ex| ex }
        predictor.prompt.instance_variable_set(:@few_shot_examples, cloned_examples.freeze)
      end

      # Initialize optimization state for candidate selection
      sig { params(candidates: T::Array[EvaluatedCandidate]).returns(T::Hash[Symbol, T.untyped]) }
      def initialize_optimization_state(candidates)
        {
          candidates: candidates,
          scores: {},
          exploration_counts: Hash.new(0),
          temperature: config.init_temperature,
          best_score_history: [],
          diversity_scores: {},
          no_improvement_count: 0
        }
      end

      # Select next candidate based on optimization strategy
      sig do
        params(
          candidates: T::Array[EvaluatedCandidate],
          state: T::Hash[Symbol, T.untyped],
          trial_idx: Integer
        ).returns(EvaluatedCandidate)
      end
      def select_next_candidate(candidates, state, trial_idx)
        case config.optimization_strategy
        when OptimizationStrategy::Greedy
          select_candidate_greedy(candidates, state)
        when OptimizationStrategy::Adaptive
          select_candidate_adaptive(candidates, state, trial_idx)
        when OptimizationStrategy::Bayesian
          select_candidate_bayesian(candidates, state, trial_idx)
        else
          candidates.sample # Random fallback
        end
      end

      # Greedy candidate selection (exploit best known configurations)
      sig { params(candidates: T::Array[EvaluatedCandidate], state: T::Hash[Symbol, T.untyped]).returns(EvaluatedCandidate) }
      def select_candidate_greedy(candidates, state)
        # Prioritize unexplored candidates, then highest scoring
        unexplored = candidates.reject { |c| state[:scores].key?(c.config_id) }
        return unexplored.sample if unexplored.any?
        
        # Among explored, pick the best
        scored_candidates = candidates.select { |c| state[:scores].key?(c.config_id) }
        scored_candidates.max_by { |c| state[:scores][c.config_id] } || candidates.first
      end

      # Adaptive candidate selection (balance exploration and exploitation)
      sig do
        params(
          candidates: T::Array[EvaluatedCandidate],
          state: T::Hash[Symbol, T.untyped],
          trial_idx: Integer
        ).returns(EvaluatedCandidate)
      end
      def select_candidate_adaptive(candidates, state, trial_idx)
        # Update temperature based on progress
        progress = trial_idx.to_f / config.num_trials
        state[:temperature] = config.init_temperature * (1 - progress) + config.final_temperature * progress
        
        # Calculate selection scores combining exploitation and exploration
        candidate_scores = candidates.map do |candidate|
          exploitation_score = state[:scores][candidate.config_id] || 0.0
          exploration_bonus = 1.0 / (state[:exploration_counts][candidate.config_id] + 1)
          
          total_score = exploitation_score + state[:temperature] * exploration_bonus
          [candidate, total_score]
        end
        
        # Select using softmax with temperature
        if state[:temperature] > 0.01
          # Probabilistic selection
          weights = candidate_scores.map { |_, score| Math.exp(score / state[:temperature]) }
          total_weight = weights.sum
          probabilities = weights.map { |w| w / total_weight }
          
          random_value = rand
          cumulative = 0.0
          candidate_scores.each_with_index do |(candidate, _), idx|
            cumulative += probabilities[idx]
            return candidate if random_value <= cumulative
          end
        end
        
        # Fallback to highest scoring
        candidate_scores.max_by { |_, score| score }.first
      end

      # Bayesian candidate selection (use probabilistic model)
      sig do
        params(
          candidates: T::Array[EvaluatedCandidate],
          state: T::Hash[Symbol, T.untyped],
          trial_idx: Integer
        ).returns(EvaluatedCandidate)
      end
      def select_candidate_bayesian(candidates, state, trial_idx)
        # Need at least 3 observations to fit GP, otherwise fall back to adaptive
        return select_candidate_adaptive(candidates, state, trial_idx) if state[:scores].size < 3
        
        # Get scored candidates for training the GP
        scored_candidates = candidates.select { |c| state[:scores].key?(c.config_id) }
        return select_candidate_adaptive(candidates, state, trial_idx) if scored_candidates.size < 3
        
        begin
          # Encode candidates as numerical features
          all_candidate_features = encode_candidates_for_gp(candidates)
          scored_features = encode_candidates_for_gp(scored_candidates)
          scored_targets = scored_candidates.map { |c| state[:scores][c.config_id].to_f }
          
          # Train Gaussian Process
          gp = DSPy::Optimizers::GaussianProcess.new(
            length_scale: 1.0,
            signal_variance: 1.0,
            noise_variance: 0.01
          )
          gp.fit(scored_features, scored_targets)
          
          # Predict mean and uncertainty for all candidates
          means, stds = gp.predict(all_candidate_features, return_std: true)
          
          # Upper Confidence Bound (UCB) acquisition function
          kappa = 2.0 * Math.sqrt(Math.log(trial_idx + 1))  # Exploration parameter
          acquisition_scores = means.to_a.zip(stds.to_a).map { |m, s| m + kappa * s }
          
          # Select candidate with highest acquisition score
          best_idx = acquisition_scores.each_with_index.max_by { |score, _| score }[1]
          candidates[best_idx]
          
        rescue => e
          # If GP fails for any reason, fall back to adaptive selection
          DSPy.logger.warn("Bayesian optimization failed: #{e.message}. Falling back to adaptive selection.")
          select_candidate_adaptive(candidates, state, trial_idx)
        end
      end
      
      private

      
      # Encode candidates as numerical features for Gaussian Process
      sig { params(candidates: T::Array[EvaluatedCandidate]).returns(T::Array[T::Array[Float]]) }
      def encode_candidates_for_gp(candidates)
        # Simple encoding: use hash of config as features
        # In practice, this could be more sophisticated (e.g., instruction embeddings)
        candidates.map do |candidate|
          # Create deterministic numerical features from the candidate config
          config_hash = candidate.config_id.hash.abs
          
          # Extract multiple features to create a feature vector
          features = []
          features << (config_hash % 1000).to_f / 1000.0  # Feature 1: hash mod 1000, normalized
          features << ((config_hash / 1000) % 1000).to_f / 1000.0  # Feature 2: different part of hash
          features << ((config_hash / 1_000_000) % 1000).to_f / 1000.0  # Feature 3: high bits
          
          # Add instruction length if available (Python-compatible: no cap)
          instruction = candidate.instruction
          if instruction && !instruction.empty?
            features << instruction.length.to_f / 100.0  # Instruction length, uncapped
          else
            features << 0.5  # Default value
          end
          
          features
        end
      end

      # Evaluate a candidate configuration
      sig do
        params(
          program: T.untyped,
          candidate: EvaluatedCandidate,
          evaluation_set: T::Array[DSPy::Example]
        ).returns([Float, T.untyped, DSPy::Evaluate::BatchEvaluationResult])
      end
      def evaluate_candidate(program, candidate, evaluation_set)
        # Apply candidate configuration to program
        modified_program = apply_candidate_configuration(program, candidate)
        
        # Evaluate modified program
        evaluation_result = if use_concurrent_evaluation?(evaluation_set)
          evaluate_candidate_concurrently(modified_program, evaluation_set)
        else
          evaluate_program(modified_program, evaluation_set)
        end
        
        # Store evaluation details
        @evaluated_candidates << candidate
        
        [evaluation_result.pass_rate, modified_program, evaluation_result]
      end

      sig { params(evaluation_set: T::Array[DSPy::Example]).returns(T::Boolean) }
      def use_concurrent_evaluation?(evaluation_set)
        minibatch_size = config.minibatch_size
        return false unless minibatch_size&.positive?
        return false unless config.num_threads && config.num_threads > 1

        evaluation_set.size > minibatch_size
      end

      sig do
        params(
          modified_program: T.untyped,
          evaluation_set: T::Array[DSPy::Example]
        ).returns(DSPy::Evaluate::BatchEvaluationResult)
      end
      def evaluate_candidate_concurrently(modified_program, evaluation_set)
        chunk_size = T.must(config.minibatch_size)
        chunks = evaluation_set.each_slice(chunk_size).map(&:dup)
        return evaluate_program(modified_program, evaluation_set) if chunks.size <= 1

        pool_size = [config.num_threads, chunks.size].min
        pool_size = 1 if pool_size <= 0
        executor = Concurrent::FixedThreadPool.new(pool_size)

        futures = chunks.map do |chunk|
          Concurrent::Promises.future_on(executor) do
            evaluate_program(modified_program, chunk)
          end
        end

        results = futures.map(&:value!)
        combine_batch_results(results)
      ensure
        if executor
          executor.shutdown
          executor.wait_for_termination
        end
      end

      sig do
        params(batch_results: T::Array[DSPy::Evaluate::BatchEvaluationResult]).returns(DSPy::Evaluate::BatchEvaluationResult)
      end
      def combine_batch_results(batch_results)
        return DSPy::Evaluate::BatchEvaluationResult.new(results: [], aggregated_metrics: {}) if batch_results.empty?

        combined_results = batch_results.flat_map(&:results)
        total_examples = batch_results.sum(&:total_examples)
        aggregated_metrics = merge_aggregated_metrics(batch_results, total_examples)

        DSPy::Evaluate::BatchEvaluationResult.new(
          results: combined_results,
          aggregated_metrics: aggregated_metrics
        )
      end

      sig do
        params(
          batch_results: T::Array[DSPy::Evaluate::BatchEvaluationResult],
          total_examples: Integer
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def merge_aggregated_metrics(batch_results, total_examples)
        return {} if total_examples.zero?

        keys = batch_results.flat_map { |res| res.aggregated_metrics.keys }.uniq
        keys.each_with_object({}) do |key, memo|
          numeric_weight = 0.0
          numeric_sum = 0.0
          fallback_value = nil

          batch_results.each do |res|
            value = res.aggregated_metrics[key]
            next if value.nil?

            if value.is_a?(Numeric)
              numeric_sum += value.to_f * res.total_examples
              numeric_weight += res.total_examples
            else
              fallback_value = value
            end
          end

          if numeric_weight.positive?
            memo[key] = numeric_sum / numeric_weight
          elsif fallback_value
            memo[key] = fallback_value
          end
        end
      end

      # Apply candidate configuration to program
      sig { params(program: T.untyped, candidate: EvaluatedCandidate).returns(T.untyped) }
      def apply_candidate_configuration(program, candidate)
        instructions_map = candidate.metadata[:instructions_map] || {}
        demos_map = candidate.metadata[:demos_map] || {}

        modified_program = program
        if modified_program.respond_to?(:predictors) && (instructions_map.any? || demos_map.any?)
          modified_program = modified_program.clone
          modified_program.predictors.each_with_index do |predictor, idx|
            if instructions_map.key?(idx)
              signature = Utils.get_signature(predictor)
              updated_signature = signature.with_instructions(instructions_map[idx])
              Utils.set_signature(predictor, updated_signature)
            end

            if demos_map.key?(idx)
              normalized_examples = normalize_few_shot_examples(demos_map[idx])
              assign_predictor_examples(predictor, normalized_examples)
            end
          end
        end

        # Apply instruction if provided (top-level programs still respect with_instruction)
        if !candidate.instruction.empty? && modified_program.respond_to?(:with_instruction)
          modified_program = modified_program.with_instruction(candidate.instruction)
        end

        should_apply_global_examples = candidate.few_shot_examples.any? &&
          modified_program.respond_to?(:with_examples) &&
          (demos_map.empty? || !modified_program.respond_to?(:predictors))

        if should_apply_global_examples
          normalized_few_shot = normalize_few_shot_examples(candidate.few_shot_examples)
          modified_program = modified_program.with_examples(normalized_few_shot)
        end
        
        modified_program
      end

      # Update optimization state after candidate evaluation
      sig do
        params(
          state: T::Hash[Symbol, T.untyped],
          candidate: EvaluatedCandidate,
          score: Float
        ).void
      end
      def update_optimization_state(state, candidate, score)
        state[:scores][candidate.config_id] = score
        state[:exploration_counts][candidate.config_id] += 1
        state[:best_score_history] << score
        
        # Track diversity if enabled
        if config.track_diversity
          state[:diversity_scores][candidate.config_id] = calculate_diversity_score(candidate)
        end
        
        # Update no improvement counter
        if state[:best_score_history].size > 1 && score > state[:best_score_history][-2]
          state[:no_improvement_count] = 0
        else
          state[:no_improvement_count] += 1
        end
      end

      # Check if optimization should stop early
      sig { params(state: T::Hash[Symbol, T.untyped], trial_idx: Integer).returns(T::Boolean) }
      def should_early_stop?(state, trial_idx)
        # Don't stop too early
        return false if trial_idx < config.early_stopping_patience
        
        # Stop if no improvement for patience trials
        state[:no_improvement_count] >= config.early_stopping_patience
      end

      # Calculate diversity score for candidate (Python-compatible: only few-shot count)
      sig { params(candidate: EvaluatedCandidate).returns(Float) }
      def calculate_diversity_score(candidate)
        # Python DSPy doesn't use instruction length for diversity, only few-shot count
        few_shot_diversity = candidate.few_shot_examples.size / 10.0

        [few_shot_diversity, 1.0].min
      end

      # Build final MIPROv2 result
      sig do
        params(
          optimization_result: T::Hash[Symbol, T.untyped],
          demo_candidates: T::Hash[Integer, T::Array[T::Array[DSPy::FewShotExample]]],
          proposal_result: DSPy::Propose::GroundedProposer::ProposalResult
        ).returns(MIPROv2Result)
      end
      def build_miprov2_result(optimization_result, demo_candidates, proposal_result)
        best_candidate = optimization_result[:best_candidate]
        best_program = optimization_result[:best_program]
        best_score = optimization_result[:best_score]
        best_evaluation_result = optimization_result[:best_evaluation_result]

        scores = { pass_rate: best_score }

        history = {
          total_trials: optimization_result[:trials_completed],
          optimization_strategy: config.optimization_strategy,
          early_stopped: optimization_result[:trials_completed] < config.num_trials,
          score_history: optimization_result[:optimization_state][:best_score_history],
          total_eval_calls: optimization_result[:total_eval_calls]
        }

        metadata = {
          optimizer: "MIPROv2",
          auto_mode: infer_auto_mode,
          best_instruction: best_candidate&.instruction || "",
          best_few_shot_count: best_candidate&.few_shot_examples&.size || 0,
          best_candidate_type: best_candidate&.type&.serialize || "unknown",
          optimization_timestamp: Time.now.iso8601
        }

        # Create bootstrap statistics from demo_candidates
        num_predictors = demo_candidates.keys.size
        sets_per_predictor = demo_candidates.values.map(&:size)
        all_demo_sets = demo_candidates.values.flat_map { |sets| sets }
        bootstrap_statistics = {
          num_predictors: num_predictors,
          demo_sets_per_predictor: sets_per_predictor.max || 0,
          avg_demos_per_set: all_demo_sets.empty? ? 0 : all_demo_sets.map(&:size).sum.to_f / all_demo_sets.size
        }
        bootstrap_statistics[:per_predictor_demo_counts] = sets_per_predictor if sets_per_predictor.any?

        optimization_trace = serialize_optimization_trace(optimization_result[:optimization_state])
        optimization_trace[:trial_logs] = serialize_trial_logs(optimization_result[:trial_logs])
        optimization_trace[:param_score_dict] = serialize_param_score_dict(optimization_result[:param_score_dict])
        optimization_trace[:fully_evaled_param_combos] = serialize_fully_evaled_param_combos(optimization_result[:fully_evaled_param_combos])
        optimization_trace[:total_eval_calls] = optimization_result[:total_eval_calls]

        MIPROv2Result.new(
          optimized_program: best_program,
          scores: scores,
          history: history,
          best_score_name: "pass_rate",
          best_score_value: best_score,
          metadata: metadata,
          evaluated_candidates: @evaluated_candidates,
          optimization_trace: optimization_trace,
          bootstrap_statistics: bootstrap_statistics,
          proposal_statistics: proposal_result.analysis,
          best_evaluation_result: best_evaluation_result
        )
      end

      # Serialize optimization trace for better JSON output
      sig { params(optimization_state: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_optimization_trace(optimization_state)
        return {} unless optimization_state
        
        serialized_trace = optimization_state.dup
        
        # Convert candidate objects to their hash representations
        if serialized_trace[:candidates]
          serialized_trace[:candidates] = serialized_trace[:candidates].map(&:to_h)
        end
        
        serialized_trace
      end

      sig do
        params(
          trial_number: Integer,
          candidate: EvaluatedCandidate,
          evaluation_type: Symbol,
          batch_size: Integer
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def create_trial_log_entry(trial_number:, candidate:, evaluation_type:, batch_size:)
        # Preserve interface parity with Python implementation (trial number stored implicitly via hash key)
        trial_number # no-op to acknowledge parameter usage
        instructions_map = candidate.metadata[:instructions_map] || {}
        demos_map = candidate.metadata[:demos_map] || {}
        entry = {
          candidate_id: candidate.config_id,
          candidate_type: candidate.type.serialize,
          instruction_preview: candidate.instruction.to_s[0, 160],
          few_shot_count: candidate.few_shot_examples.size,
          metadata: deep_dup(candidate.metadata),
          evaluation_type: evaluation_type,
          batch_size: batch_size,
          status: :in_progress,
          started_at: Time.now.iso8601
        }
        if instructions_map.any?
          entry[:instructions] = duplicate_instruction_map(instructions_map)
          entry[:instruction] = entry[:instructions][0] if entry[:instructions].key?(0)
        elsif candidate.instruction && !candidate.instruction.empty?
          predictor_index = candidate.metadata[:predictor_index] || 0
          entry[:instruction] = candidate.instruction
          entry[:instructions] = { predictor_index => candidate.instruction }
        end
        entry[:few_shot_map] = duplicate_demo_map(demos_map) if demos_map.any?
        entry
      end

      sig do
        params(
          trial_logs: T::Hash[Integer, T::Hash[Symbol, T.untyped]],
          trial_number: Integer,
          score: T.nilable(Float),
          evaluation_type: Symbol,
          batch_size: Integer,
          total_eval_calls: Integer,
          error: T.nilable(String)
        ).void
      end
      def finalize_trial_log_entry(trial_logs, trial_number, score:, evaluation_type:, batch_size:, total_eval_calls:, error: nil)
        entry = trial_logs[trial_number] || {}
        entry[:score] = score if score
        entry[:evaluation_type] = evaluation_type
        entry[:batch_size] = batch_size
        entry[:total_eval_calls] = total_eval_calls
        entry[:status] = error ? :error : :completed
        entry[:error] = error if error
        entry[:completed_at] = Time.now.iso8601
        trial_logs[trial_number] = entry
      end

      sig do
        params(
          param_score_dict: T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]],
          candidate: EvaluatedCandidate,
          score: Float,
          evaluation_type: Symbol,
          instructions: T.nilable(T::Hash[Integer, String])
        ).void
      end
      def record_param_score(param_score_dict, candidate, score, evaluation_type:, instructions: nil)
        instructions_hash = instructions || {}
        if instructions_hash.empty? && candidate.instruction && !candidate.instruction.empty?
          predictor_index = candidate.metadata[:predictor_index] || 0
          instructions_hash[predictor_index] = candidate.instruction
        end

        record = {
          candidate_id: candidate.config_id,
          candidate_type: candidate.type.serialize,
          score: score,
          evaluation_type: evaluation_type,
          timestamp: Time.now.iso8601,
          metadata: deep_dup(candidate.metadata)
        }
        primary_instruction = instructions_hash[0] || candidate.instruction
        record[:instruction] = primary_instruction if primary_instruction && !primary_instruction.empty?
        record[:instructions] = instructions_hash unless instructions_hash.empty?

        param_score_dict[candidate.config_id] << record
      end

      sig do
        params(
          fully_evaled_param_combos: T::Hash[String, T::Hash[Symbol, T.untyped]],
          candidate: EvaluatedCandidate,
          score: Float,
          instructions: T.nilable(T::Hash[Integer, String])
        ).void
      end
      def update_fully_evaled_param_combos(fully_evaled_param_combos, candidate, score, instructions: nil)
        existing = fully_evaled_param_combos[candidate.config_id]
        if existing.nil? || score > existing[:score]
          instructions_hash = instructions || {}
          if instructions_hash.empty? && candidate.instruction && !candidate.instruction.empty?
            predictor_index = candidate.metadata[:predictor_index] || 0
            instructions_hash[predictor_index] = candidate.instruction
          end

          fully_evaled_param_combos[candidate.config_id] = {
            candidate_id: candidate.config_id,
            candidate_type: candidate.type.serialize,
            score: score,
            metadata: deep_dup(candidate.metadata),
            updated_at: Time.now.iso8601
          }
          unless instructions_hash.empty?
            fully_evaled_param_combos[candidate.config_id][:instructions] = instructions_hash
            fully_evaled_param_combos[candidate.config_id][:instruction] = instructions_hash[0] || candidate.instruction
          end
        end
      end

      sig { params(trial_logs: T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]])).returns(T::Hash[Integer, T::Hash[Symbol, T.untyped]]) }
      def serialize_trial_logs(trial_logs)
        return {} unless trial_logs

        allowed_keys = [
          :candidate_id,
          :candidate_type,
          :instruction_preview,
          :instruction,
          :instructions,
          :few_shot_count,
          :metadata,
          :evaluation_type,
          :batch_size,
          :score,
          :status,
          :error,
          :started_at,
          :completed_at,
          :total_eval_calls
        ]

        trial_logs.transform_values do |entry|
          entry.each_with_object({}) do |(key, value), memo|
            memo[key] = value if allowed_keys.include?(key)
          end
        end
      end

      sig { params(param_score_dict: T.nilable(T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]])).returns(T::Hash[String, T::Array[T::Hash[Symbol, T.untyped]]]) }
      def serialize_param_score_dict(param_score_dict)
        return {} unless param_score_dict

        allowed_keys = [:candidate_id, :candidate_type, :score, :evaluation_type, :timestamp, :metadata, :instruction, :instructions]

        param_score_dict.transform_values do |records|
          records.map do |record|
            record.each_with_object({}) do |(key, value), memo|
              memo[key] = value if allowed_keys.include?(key)
            end
          end
        end
      end

      sig { params(fully_evaled_param_combos: T.nilable(T::Hash[String, T::Hash[Symbol, T.untyped]])).returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
      def serialize_fully_evaled_param_combos(fully_evaled_param_combos)
        return {} unless fully_evaled_param_combos

        allowed_keys = [:candidate_id, :candidate_type, :score, :metadata, :updated_at, :instruction, :instructions]

        fully_evaled_param_combos.transform_values do |record|
          record.each_with_object({}) do |(key, value), memo|
            memo[key] = value if allowed_keys.include?(key)
          end
        end
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), memo| memo[k] = deep_dup(v) }
        when Array
          value.map { |element| deep_dup(element) }
        else
          value
        end
      end

      # Helper methods
      sig { params(program: T.untyped).returns(T.nilable(String)) }
      def extract_current_instruction(program)
        if program.respond_to?(:prompt) && program.prompt.respond_to?(:instruction)
          program.prompt.instruction
        elsif program.respond_to?(:system_signature)
          system_sig = program.system_signature
          system_sig.is_a?(String) ? system_sig : nil
        else
          nil
        end
      end

      sig { params(program: T.untyped).returns(T::Hash[Integer, String]) }
      def extract_program_instructions(program)
        instructions = {}
        if program.respond_to?(:predictors)
          program.predictors.each_with_index do |predictor, index|
            if predictor.respond_to?(:prompt) && predictor.prompt.respond_to?(:instruction)
              value = predictor.prompt.instruction
              instructions[index] = value if value
            end
          end
        else
          fallback_instruction = extract_current_instruction(program)
          instructions[0] = fallback_instruction if fallback_instruction
        end
        instructions
      end

      sig { params(program: T.untyped).returns(T.nilable(T.class_of(DSPy::Signature))) }
      def extract_signature_class(program)
        program.respond_to?(:signature_class) ? program.signature_class : nil
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

      # Infer auto mode based on configuration
      sig { returns(String) }
      def infer_auto_mode
        case config.num_trials
        when 0..6 then "light"
        when 7..12 then "medium"
        else "heavy"
        end
      end
    end
  end
end
