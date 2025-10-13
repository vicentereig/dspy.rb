# frozen_string_literal: true

require 'digest'
require 'sorbet-runtime'
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

        # Get signature class from program
        signature_class = extract_signature_class(program)
        raise ArgumentError, "Cannot extract signature class from program" unless signature_class

        # Re-initialize proposer with program and trainset for awareness features
        # This enables program_aware and use_dataset_summary flags to work correctly
        proposer_config = DSPy::Propose::GroundedProposer::Config.new
        proposer_config.num_instruction_candidates = config.num_instruction_candidates

        @proposer = DSPy::Propose::GroundedProposer.new(
          config: proposer_config,
          program: program,
          trainset: trainset
        )

        @proposer.propose_instructions(
          signature_class,
          trainset,
          few_shot_examples: few_shot_examples,
          current_instruction: current_instruction
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
        
        # Run optimization trials
        trials_completed = 0
        best_score = 0.0
        best_candidate = nil
        best_program = nil
        best_evaluation_result = nil
        
        config.num_trials.times do |trial_idx|
          trials_completed = trial_idx + 1
          
          # Select next candidate based on optimization strategy
          candidate = select_next_candidate(candidates, optimization_state, trial_idx)
          
          emit_event('trial_start', {
            trial_number: trials_completed,
            candidate_id: candidate.config_id,
            instruction_preview: candidate.instruction[0, 50],
            num_few_shot: candidate.few_shot_examples.size
          })

          begin
            # Evaluate candidate
            score, modified_program, evaluation_result = evaluate_candidate(program, candidate, evaluation_set)
            
            # Update optimization state
            update_optimization_state(optimization_state, candidate, score)
            
            # Track best result
            is_best = score > best_score
            if is_best
              best_score = score
              best_candidate = candidate
              best_program = modified_program
              best_evaluation_result = evaluation_result
            end

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
          evaluated_candidates: @evaluated_candidates
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

        # Base configuration (no modifications)
        candidates << EvaluatedCandidate.new(
          instruction: "",
          few_shot_examples: [],
          type: CandidateType::Baseline,
          metadata: {},
          config_id: SecureRandom.hex(6)
        )

        # Instruction-only candidates
        proposal_result.candidate_instructions.each_with_index do |instruction, idx|
          candidates << EvaluatedCandidate.new(
            instruction: instruction,
            few_shot_examples: [],
            type: CandidateType::InstructionOnly,
            metadata: { proposal_rank: idx },
            config_id: SecureRandom.hex(6)
          )
        end

        # Few-shot only candidates
        # Extract demo sets from first predictor (predictor index 0)
        demo_sets = demo_candidates[0] || []
        demo_sets.each_with_index do |demo_set, idx|
          candidates << EvaluatedCandidate.new(
            instruction: "",
            few_shot_examples: demo_set,
            type: CandidateType::FewShotOnly,
            metadata: { bootstrap_rank: idx },
            config_id: SecureRandom.hex(6)
          )
        end
        
        # Combined candidates (instruction + few-shot)
        top_instructions = proposal_result.candidate_instructions.take(3)
        top_bootstrap_sets = demo_sets.take(3)
        
        top_instructions.each_with_index do |instruction, i_idx|
          top_bootstrap_sets.each_with_index do |candidate_set, b_idx|
            candidates << EvaluatedCandidate.new(
              instruction: instruction,
              few_shot_examples: candidate_set,
              type: CandidateType::Combined,
              metadata: { 
                instruction_rank: i_idx, 
                bootstrap_rank: b_idx 
              },
              config_id: SecureRandom.hex(6)
            )
          end
        end
        
        candidates
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
        evaluation_result = evaluate_program(modified_program, evaluation_set)
        
        # Store evaluation details
        @evaluated_candidates << candidate
        
        [evaluation_result.pass_rate, modified_program, evaluation_result]
      end

      # Apply candidate configuration to program
      sig { params(program: T.untyped, candidate: EvaluatedCandidate).returns(T.untyped) }
      def apply_candidate_configuration(program, candidate)
        modified_program = program
        
        # Apply instruction if provided
        if !candidate.instruction.empty? && program.respond_to?(:with_instruction)
          modified_program = modified_program.with_instruction(candidate.instruction)
        end
        
        # Apply few-shot examples if provided
        if candidate.few_shot_examples.any? && program.respond_to?(:with_examples)
          few_shot_examples = candidate.few_shot_examples.map do |example|
            # If already a FewShotExample, use it directly
            if example.is_a?(DSPy::FewShotExample)
              example
            else
              # Convert from DSPy::Example
              DSPy::FewShotExample.new(
                input: example.input_values,
                output: example.expected_values,
                reasoning: extract_reasoning_from_example(example)
              )
            end
          end
          modified_program = modified_program.with_examples(few_shot_examples)
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
          score_history: optimization_result[:optimization_state][:best_score_history]
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
        demo_sets = demo_candidates[0] || []
        bootstrap_statistics = {
          num_predictors: demo_candidates.keys.size,
          demo_sets_per_predictor: demo_sets.size,
          avg_demos_per_set: demo_sets.empty? ? 0 : demo_sets.map(&:size).sum.to_f / demo_sets.size
        }

        MIPROv2Result.new(
          optimized_program: best_program,
          scores: scores,
          history: history,
          best_score_name: "pass_rate",
          best_score_value: best_score,
          metadata: metadata,
          evaluated_candidates: @evaluated_candidates,
          optimization_trace: serialize_optimization_trace(optimization_result[:optimization_state]),
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