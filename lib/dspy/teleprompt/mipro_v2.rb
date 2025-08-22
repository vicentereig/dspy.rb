# frozen_string_literal: true

require 'digest'
require 'sorbet-runtime'
require_relative 'teleprompter'
require_relative 'utils'
require_relative '../propose/grounded_proposer'

module DSPy
  module Teleprompt
    # MIPROv2: Multi-prompt Instruction Proposal with Retrieval Optimization
    # State-of-the-art prompt optimization combining bootstrap sampling, 
    # instruction generation, and Bayesian optimization
    class MIPROv2 < Teleprompter
      extend T::Sig

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
          config = MIPROv2Config.new
          config.num_trials = 6
          config.num_instruction_candidates = 3
          config.max_bootstrapped_examples = 2
          config.max_labeled_examples = 8
          config.bootstrap_sets = 3
          config.optimization_strategy = "greedy"
          config.early_stopping_patience = 2
          MIPROv2.new(metric: metric, config: config, **kwargs)
        end

        sig do
          params(
            metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
            kwargs: T.untyped
          ).returns(MIPROv2)
        end
        def self.medium(metric: nil, **kwargs)
          config = MIPROv2Config.new
          config.num_trials = 12
          config.num_instruction_candidates = 5
          config.max_bootstrapped_examples = 4
          config.max_labeled_examples = 16
          config.bootstrap_sets = 5
          config.optimization_strategy = "adaptive"
          config.early_stopping_patience = 3
          MIPROv2.new(metric: metric, config: config, **kwargs)
        end

        sig do
          params(
            metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
            kwargs: T.untyped
          ).returns(MIPROv2)
        end
        def self.heavy(metric: nil, **kwargs)
          config = MIPROv2Config.new
          config.num_trials = 18
          config.num_instruction_candidates = 8
          config.max_bootstrapped_examples = 6
          config.max_labeled_examples = 24
          config.bootstrap_sets = 8
          config.optimization_strategy = "bayesian"
          config.early_stopping_patience = 5
          MIPROv2.new(metric: metric, config: config, **kwargs)
        end
      end

      # Configuration for MIPROv2 optimization
      class MIPROv2Config < Config
        extend T::Sig

        sig { returns(Integer) }
        attr_accessor :num_trials

        sig { returns(Integer) }
        attr_accessor :num_instruction_candidates

        sig { returns(Integer) }
        attr_accessor :bootstrap_sets

        sig { returns(String) }
        attr_accessor :optimization_strategy

        sig { returns(Float) }
        attr_accessor :init_temperature

        sig { returns(Float) }
        attr_accessor :final_temperature

        sig { returns(Integer) }
        attr_accessor :early_stopping_patience

        sig { returns(T::Boolean) }
        attr_accessor :use_bayesian_optimization

        sig { returns(T::Boolean) }
        attr_accessor :track_diversity

        sig { returns(DSPy::Propose::GroundedProposer::Config) }
        attr_accessor :proposer_config

        sig { void }
        def initialize
          super
          @num_trials = 12
          @num_instruction_candidates = 5
          @bootstrap_sets = 5
          @optimization_strategy = "adaptive" # greedy, adaptive, bayesian
          @init_temperature = 1.0
          @final_temperature = 0.1
          @early_stopping_patience = 3
          @use_bayesian_optimization = true
          @track_diversity = true
          @proposer_config = DSPy::Propose::GroundedProposer::Config.new
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          super.merge({
            num_trials: @num_trials,
            num_instruction_candidates: @num_instruction_candidates,
            bootstrap_sets: @bootstrap_sets,
            optimization_strategy: @optimization_strategy,
            init_temperature: @init_temperature,
            final_temperature: @final_temperature,
            early_stopping_patience: @early_stopping_patience,
            use_bayesian_optimization: @use_bayesian_optimization,
            track_diversity: @track_diversity
          })
        end
      end

      # Candidate configuration for optimization trials
      class CandidateConfig
        extend T::Sig

        sig { returns(String) }
        attr_reader :instruction

        sig { returns(T::Array[T.untyped]) }
        attr_reader :few_shot_examples

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :metadata

        sig { returns(String) }
        attr_reader :config_id

        sig do
          params(
            instruction: String,
            few_shot_examples: T::Array[T.untyped],
            metadata: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(instruction:, few_shot_examples:, metadata: {})
          @instruction = instruction
          @few_shot_examples = few_shot_examples
          @metadata = metadata.freeze
          @config_id = generate_config_id
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          {
            instruction: @instruction,
            few_shot_examples: @few_shot_examples.size,
            metadata: @metadata,
            config_id: @config_id
          }
        end

        private

        sig { returns(String) }
        def generate_config_id
          content = "#{@instruction}_#{@few_shot_examples.size}_#{@metadata.hash}"
          Digest::SHA256.hexdigest(content)[0, 12]
        end
      end

      # Result of MIPROv2 optimization
      class MIPROv2Result < OptimizationResult
        extend T::Sig

        sig { returns(T::Array[CandidateConfig]) }
        attr_reader :evaluated_candidates

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :optimization_trace

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :bootstrap_statistics

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :proposal_statistics

        sig do
          params(
            optimized_program: T.untyped,
            scores: T::Hash[Symbol, T.untyped],
            history: T::Hash[Symbol, T.untyped],
            evaluated_candidates: T::Array[CandidateConfig],
            optimization_trace: T::Hash[Symbol, T.untyped],
            bootstrap_statistics: T::Hash[Symbol, T.untyped],
            proposal_statistics: T::Hash[Symbol, T.untyped],
            best_score_name: T.nilable(String),
            best_score_value: T.nilable(Float),
            metadata: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(optimized_program:, scores:, history:, evaluated_candidates:, optimization_trace:, bootstrap_statistics:, proposal_statistics:, best_score_name: nil, best_score_value: nil, metadata: {})
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
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_h
          super.merge({
            evaluated_candidates: @evaluated_candidates.map(&:to_h),
            optimization_trace: @optimization_trace,
            bootstrap_statistics: @bootstrap_statistics,
            proposal_statistics: @proposal_statistics
          })
        end
      end

      sig { returns(MIPROv2Config) }
      attr_reader :mipro_config

      sig { returns(T.nilable(DSPy::Propose::GroundedProposer)) }
      attr_reader :proposer

      sig do
        params(
          metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)),
          config: T.nilable(MIPROv2Config)
        ).void
      end
      def initialize(metric: nil, config: nil)
        @mipro_config = config || MIPROv2Config.new
        super(metric: metric, config: @mipro_config)
        
        @proposer = DSPy::Propose::GroundedProposer.new(config: @mipro_config.proposer_config)
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
          num_trials: @mipro_config.num_trials,
          optimization_strategy: @mipro_config.optimization_strategy,
          mode: infer_auto_mode
        }) do
          # Convert examples to typed format
          typed_trainset = ensure_typed_examples(trainset)
          typed_valset = valset ? ensure_typed_examples(valset) : nil

          # Use validation set if available, otherwise use part of training set
          evaluation_set = typed_valset || typed_trainset.take([typed_trainset.size / 3, 10].max)

          # Phase 1: Bootstrap few-shot examples
          emit_event('phase_start', { phase: 1, name: 'bootstrap' })
          bootstrap_result = phase_1_bootstrap(program, typed_trainset)
          emit_event('phase_complete', { 
            phase: 1, 
            success_rate: bootstrap_result.statistics[:success_rate],
            candidate_sets: bootstrap_result.candidate_sets.size
          })

          # Phase 2: Generate instruction candidates
          emit_event('phase_start', { phase: 2, name: 'instruction_proposal' })
          proposal_result = phase_2_propose_instructions(program, typed_trainset, bootstrap_result)
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
            bootstrap_result
          )
          emit_event('phase_complete', { 
            phase: 3, 
            best_score: optimization_result[:best_score],
            trials_completed: optimization_result[:trials_completed]
          })

          # Build final result
          final_result = build_miprov2_result(
            optimization_result,
            bootstrap_result,
            proposal_result
          )

          save_results(final_result)
          final_result
        end
      end

      private

      # Phase 1: Bootstrap few-shot examples from training data
      sig { params(program: T.untyped, trainset: T::Array[DSPy::Example]).returns(Utils::BootstrapResult) }
      def phase_1_bootstrap(program, trainset)
        bootstrap_config = Utils::BootstrapConfig.new
        bootstrap_config.max_bootstrapped_examples = @mipro_config.max_bootstrapped_examples
        bootstrap_config.max_labeled_examples = @mipro_config.max_labeled_examples
        bootstrap_config.num_candidate_sets = @mipro_config.bootstrap_sets
        bootstrap_config.max_errors = @mipro_config.max_errors
        bootstrap_config.num_threads = @mipro_config.num_threads

        Utils.create_n_fewshot_demo_sets(program, trainset, config: bootstrap_config, metric: @metric)
      end

      # Phase 2: Generate instruction candidates using grounded proposer
      sig do
        params(
          program: T.untyped,
          trainset: T::Array[DSPy::Example],
          bootstrap_result: Utils::BootstrapResult
        ).returns(DSPy::Propose::GroundedProposer::ProposalResult)
      end
      def phase_2_propose_instructions(program, trainset, bootstrap_result)
        # Get current instruction if available
        current_instruction = extract_current_instruction(program)
        
        # Use few-shot examples from bootstrap if available
        few_shot_examples = bootstrap_result.successful_examples.take(5)

        # Get signature class from program
        signature_class = extract_signature_class(program)
        raise ArgumentError, "Cannot extract signature class from program" unless signature_class

        # Configure proposer for this optimization run
        @mipro_config.proposer_config.num_instruction_candidates = @mipro_config.num_instruction_candidates

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
          bootstrap_result: Utils::BootstrapResult
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def phase_3_optimize(program, evaluation_set, proposal_result, bootstrap_result)
        # Generate candidate configurations
        candidates = generate_candidate_configurations(proposal_result, bootstrap_result)
        
        # Initialize optimization state
        optimization_state = initialize_optimization_state(candidates)
        
        # Run optimization trials
        trials_completed = 0
        best_score = 0.0
        best_candidate = nil
        best_program = nil
        
        @mipro_config.num_trials.times do |trial_idx|
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
            score, modified_program = evaluate_candidate(program, candidate, evaluation_set)
            
            # Update optimization state
            update_optimization_state(optimization_state, candidate, score)
            
            # Track best result
            is_best = score > best_score
            if is_best
              best_score = score
              best_candidate = candidate
              best_program = modified_program
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
          trials_completed: trials_completed,
          optimization_state: optimization_state,
          evaluated_candidates: @evaluated_candidates
        }
      end

      # Generate candidate configurations from proposals and bootstrap results
      sig do
        params(
          proposal_result: DSPy::Propose::GroundedProposer::ProposalResult,
          bootstrap_result: Utils::BootstrapResult
        ).returns(T::Array[CandidateConfig])
      end
      def generate_candidate_configurations(proposal_result, bootstrap_result)
        candidates = []
        
        # Base configuration (no modifications)
        candidates << CandidateConfig.new(
          instruction: "",
          few_shot_examples: [],
          metadata: { type: "baseline" }
        )
        
        # Instruction-only candidates
        proposal_result.candidate_instructions.each_with_index do |instruction, idx|
          candidates << CandidateConfig.new(
            instruction: instruction,
            few_shot_examples: [],
            metadata: { type: "instruction_only", proposal_rank: idx }
          )
        end
        
        # Few-shot only candidates
        bootstrap_result.candidate_sets.each_with_index do |candidate_set, idx|
          candidates << CandidateConfig.new(
            instruction: "",
            few_shot_examples: candidate_set,
            metadata: { type: "few_shot_only", bootstrap_rank: idx }
          )
        end
        
        # Combined candidates (instruction + few-shot)
        top_instructions = proposal_result.candidate_instructions.take(3)
        top_bootstrap_sets = bootstrap_result.candidate_sets.take(3)
        
        top_instructions.each_with_index do |instruction, i_idx|
          top_bootstrap_sets.each_with_index do |candidate_set, b_idx|
            candidates << CandidateConfig.new(
              instruction: instruction,
              few_shot_examples: candidate_set,
              metadata: { 
                type: "combined", 
                instruction_rank: i_idx, 
                bootstrap_rank: b_idx 
              }
            )
          end
        end
        
        candidates
      end

      # Initialize optimization state for candidate selection
      sig { params(candidates: T::Array[CandidateConfig]).returns(T::Hash[Symbol, T.untyped]) }
      def initialize_optimization_state(candidates)
        {
          candidates: candidates,
          scores: {},
          exploration_counts: Hash.new(0),
          temperature: @mipro_config.init_temperature,
          best_score_history: [],
          diversity_scores: {},
          no_improvement_count: 0
        }
      end

      # Select next candidate based on optimization strategy
      sig do
        params(
          candidates: T::Array[CandidateConfig],
          state: T::Hash[Symbol, T.untyped],
          trial_idx: Integer
        ).returns(CandidateConfig)
      end
      def select_next_candidate(candidates, state, trial_idx)
        case @mipro_config.optimization_strategy
        when "greedy"
          select_candidate_greedy(candidates, state)
        when "adaptive"
          select_candidate_adaptive(candidates, state, trial_idx)
        when "bayesian"
          select_candidate_bayesian(candidates, state, trial_idx)
        else
          candidates.sample # Random fallback
        end
      end

      # Greedy candidate selection (exploit best known configurations)
      sig { params(candidates: T::Array[CandidateConfig], state: T::Hash[Symbol, T.untyped]).returns(CandidateConfig) }
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
          candidates: T::Array[CandidateConfig],
          state: T::Hash[Symbol, T.untyped],
          trial_idx: Integer
        ).returns(CandidateConfig)
      end
      def select_candidate_adaptive(candidates, state, trial_idx)
        # Update temperature based on progress
        progress = trial_idx.to_f / @mipro_config.num_trials
        state[:temperature] = @mipro_config.init_temperature * (1 - progress) + @mipro_config.final_temperature * progress
        
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
          candidates: T::Array[CandidateConfig],
          state: T::Hash[Symbol, T.untyped],
          trial_idx: Integer
        ).returns(CandidateConfig)
      end
      def select_candidate_bayesian(candidates, state, trial_idx)
        # For now, use adaptive selection with Bayesian-inspired exploration
        # In a full implementation, this would use Gaussian processes or similar
        select_candidate_adaptive(candidates, state, trial_idx)
      end

      # Evaluate a candidate configuration
      sig do
        params(
          program: T.untyped,
          candidate: CandidateConfig,
          evaluation_set: T::Array[DSPy::Example]
        ).returns([Float, T.untyped])
      end
      def evaluate_candidate(program, candidate, evaluation_set)
        # Apply candidate configuration to program
        modified_program = apply_candidate_configuration(program, candidate)
        
        # Evaluate modified program
        evaluation_result = evaluate_program(modified_program, evaluation_set)
        
        # Store evaluation details
        @evaluated_candidates << candidate
        
        [evaluation_result.pass_rate, modified_program]
      end

      # Apply candidate configuration to program
      sig { params(program: T.untyped, candidate: CandidateConfig).returns(T.untyped) }
      def apply_candidate_configuration(program, candidate)
        modified_program = program
        
        # Apply instruction if provided
        if !candidate.instruction.empty? && program.respond_to?(:with_instruction)
          modified_program = modified_program.with_instruction(candidate.instruction)
        end
        
        # Apply few-shot examples if provided
        if candidate.few_shot_examples.any? && program.respond_to?(:with_examples)
          few_shot_examples = candidate.few_shot_examples.map do |example|
            DSPy::FewShotExample.new(
              input: example.input_values,
              output: example.expected_values,
              reasoning: extract_reasoning_from_example(example)
            )
          end
          modified_program = modified_program.with_examples(few_shot_examples)
        end
        
        modified_program
      end

      # Update optimization state after candidate evaluation
      sig do
        params(
          state: T::Hash[Symbol, T.untyped],
          candidate: CandidateConfig,
          score: Float
        ).void
      end
      def update_optimization_state(state, candidate, score)
        state[:scores][candidate.config_id] = score
        state[:exploration_counts][candidate.config_id] += 1
        state[:best_score_history] << score
        
        # Track diversity if enabled
        if @mipro_config.track_diversity
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
        return false if trial_idx < @mipro_config.early_stopping_patience
        
        # Stop if no improvement for patience trials
        state[:no_improvement_count] >= @mipro_config.early_stopping_patience
      end

      # Calculate diversity score for candidate
      sig { params(candidate: CandidateConfig).returns(Float) }
      def calculate_diversity_score(candidate)
        # Simple diversity metric based on instruction length and few-shot count
        instruction_diversity = candidate.instruction.length / 200.0
        few_shot_diversity = candidate.few_shot_examples.size / 10.0
        
        [instruction_diversity + few_shot_diversity, 1.0].min
      end

      # Build final MIPROv2 result
      sig do
        params(
          optimization_result: T::Hash[Symbol, T.untyped],
          bootstrap_result: Utils::BootstrapResult,
          proposal_result: DSPy::Propose::GroundedProposer::ProposalResult
        ).returns(MIPROv2Result)
      end
      def build_miprov2_result(optimization_result, bootstrap_result, proposal_result)
        best_candidate = optimization_result[:best_candidate]
        best_program = optimization_result[:best_program]
        best_score = optimization_result[:best_score]
        
        scores = { pass_rate: best_score }
        
        history = {
          total_trials: optimization_result[:trials_completed],
          optimization_strategy: @mipro_config.optimization_strategy,
          early_stopped: optimization_result[:trials_completed] < @mipro_config.num_trials,
          score_history: optimization_result[:optimization_state][:best_score_history]
        }
        
        metadata = {
          optimizer: "MIPROv2",
          auto_mode: infer_auto_mode,
          best_instruction: best_candidate&.instruction || "",
          best_few_shot_count: best_candidate&.few_shot_examples&.size || 0,
          best_candidate_type: best_candidate&.metadata&.fetch(:type, "unknown"),
          optimization_timestamp: Time.now.iso8601
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
          bootstrap_statistics: bootstrap_result.statistics,
          proposal_statistics: proposal_result.analysis
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
        case @mipro_config.num_trials
        when 0..6 then "light"
        when 7..12 then "medium"
        else "heavy"
        end
      end
    end
  end
end