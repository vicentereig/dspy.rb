# frozen_string_literal: true

require 'logger'
require 'set'
require 'sorbet-runtime'
require_relative 'teleprompter'
require_relative 'utils'
require_relative 'instruction_updates'
require_relative '../../gepa'

module DSPy
  module Teleprompt
    class GEPA < Teleprompter
      extend T::Sig
      DEFAULT_CONFIG = {
        max_metric_calls: 32,
        minibatch_size: 2,
        perfect_score: 1.0,
        skip_perfect_score: true,
        use_merge: true,
        max_merge_invocations: 5
      }.freeze

      def self.configure
        yield(default_config) if block_given?
      end

      def self.default_config
        @default_config ||= DEFAULT_CONFIG.dup
      end

      class NullExperimentTracker
        extend T::Sig
        attr_reader :events

        def initialize
          @events = []
        end

        sig { params(metrics: T::Hash[Symbol, T.untyped], step: T.nilable(Integer)).void }
        def log_metrics(metrics, step: nil)
          @events << { metrics: metrics, step: step }
        end
      end

      class NullLogger
        extend T::Sig
        attr_reader :messages

        def initialize
          @messages = []
        end

        sig { params(message: String).void }
        def log(message)
          @messages << message
          DSPy.log('gepa.log', message: message)
        end
      end

      class PredictAdapter
        extend T::Sig

        ReflectionLMType = T.type_alias do
          T.any(DSPy::ReflectionLM, T.proc.params(arg0: String).returns(String))
        end

        FeedbackFnType = T.type_alias do
          T.proc.params(
            predictor_output: T.untyped,
            predictor_inputs: T::Hash[T.any(String, Symbol), T.untyped],
            module_inputs: DSPy::Example,
            module_outputs: T.untyped,
            captured_trace: T::Array[T::Hash[Symbol, T.untyped]]
          ).returns(T.untyped)
        end

        sig do
          params(
            student: DSPy::Module,
            metric: T.proc.params(arg0: DSPy::Example, arg1: T.untyped).returns(T.untyped),
            reflection_lm: T.nilable(ReflectionLMType),
            feedback_map: T::Hash[String, FeedbackFnType]
          ).void
        end
        def initialize(student, metric, reflection_lm: nil, feedback_map: {})
          @student = student
          @metric = metric
          @reflection_lm = reflection_lm
          @feedback_map = feedback_map.transform_keys(&:to_s)

          @predictor_entries = resolve_predictors(@student)
          @predictor_names = @predictor_entries.map(&:first)
        end

        sig { returns(T::Hash[String, String]) }
        def seed_candidate
          @predictor_entries.each_with_object({}) do |(name, predictor), memo|
            memo[name] = extract_instruction(predictor)
          end
        end

        sig do
          params(candidate: T::Hash[String, String], recorder: T.nilable(T.untyped)).returns(DSPy::Module)
        end
        def build_program(candidate, recorder: nil)
          program = clone_module(@student)
          duplicate_predictors!(program)

          predictor_map = resolve_predictors(program).to_h
          candidate.each do |name, new_instruction|
            predictor = predictor_map[name]
            next unless predictor

            program, updated = InstructionUpdates.apply_instruction(program, predictor, new_instruction)

            predictor_map[name] = updated
          end

          wrap_predictors_for_tracing!(program, recorder: recorder) if recorder
          program
        end

        sig do
          params(
            batch: T::Array[DSPy::Example],
            candidate: T::Hash[String, String],
            capture_traces: T::Boolean
          ).returns(::GEPA::Core::EvaluationBatch)
        end
        def evaluate(batch, candidate, capture_traces: false)
          recorder = capture_traces ? TraceRecorder.new : nil
          program = build_program(candidate, recorder: recorder)

          if capture_traces
            trajectories = batch.map do |example|
              recorder&.start_example
              prediction = program.call(**example.input_values)
              result = @metric.call(example, prediction)
              score, feedback = extract_score_and_feedback(result)
              trace_entries = recorder ? recorder.finish_example : []

              {
                example: example,
                prediction: prediction,
                score: score,
                feedback: feedback,
                trace: trace_entries
              }
            end

            scores = trajectories.map { |row| row[:score] }
            outputs = trajectories.map { |row| row[:prediction] }
            ::GEPA::Core::EvaluationBatch.new(outputs: outputs, scores: scores, trajectories: trajectories)
          else
            evaluator = DSPy::Evals.new(program, metric: nil, num_threads: nil, max_errors: batch.length * 100, provide_traceback: false)
            results = batch.map do |example|
              prediction = program.call(**example.input_values)
              result = @metric.call(example, prediction)
              score, = extract_score_and_feedback(result)
              [prediction, score]
            end
            outputs = results.map(&:first)
            scores = results.map(&:last)
            ::GEPA::Core::EvaluationBatch.new(outputs: outputs, scores: scores, trajectories: nil)
          end
        end

        sig do
          params(
            candidate: T::Hash[String, String],
            eval_batch: ::GEPA::Core::EvaluationBatch,
            components_to_update: T::Array[String]
          ).returns(T::Hash[String, T::Array[T::Hash[String, T.untyped]]])
        end
        def make_reflective_dataset(candidate, eval_batch, components_to_update)
          return {} unless eval_batch.trajectories

          components_to_update.each_with_object({}) do |component, memo|
            rows = eval_batch.trajectories.flat_map do |trajectory|
              example = trajectory[:example]
              expected = serialize_struct(example.expected)
              actual_program_output = serialize_prediction(trajectory[:prediction])
              diff = build_diff(expected, actual_program_output)
              default_feedback = trajectory[:feedback] || "Score: #{trajectory[:score]}"
              default_score = trajectory[:score]
              full_trace = Array(trajectory[:trace])

              full_trace.filter_map do |entry|
                next unless entry[:predictor_name] == component

                raw_inputs = entry[:inputs] || {}
                raw_output = entry[:output]
                inputs = serialize_struct(raw_inputs)
                outputs = serialize_prediction(raw_output)

                feedback_text = default_feedback
                score_value = default_score
                score_overridden = false

                if (feedback_fn = @feedback_map[component])
                  feedback_result = feedback_fn.call(
                    predictor_output: raw_output,
                    predictor_inputs: raw_inputs,
                    module_inputs: example,
                    module_outputs: trajectory[:prediction],
                    captured_trace: full_trace
                  )
                  override_score, override_feedback = extract_score_and_feedback(feedback_result)
                  feedback_text = override_feedback if override_feedback
                  unless override_score.nil?
                    score_value = override_score
                    score_overridden = true
                  end
                end

                row = {
                  'Inputs' => inputs,
                  'Expected' => expected,
                  'Generated Outputs' => outputs,
                  'Diff' => diff,
                  'Feedback' => feedback_text
                }
                row['Score'] = score_value if score_overridden
                row
              end
            end
            memo[component] = rows unless rows.empty?
          end
        end

        sig do
          params(
            candidate: T::Hash[String, String],
            reflective_dataset: T::Hash[String, T::Array[T::Hash[String, T.untyped]]],
            components_to_update: T::Array[String]
          ).returns(T::Hash[String, String])
        end
        def propose_new_texts(candidate, reflective_dataset, components_to_update)
          if @reflection_lm
            components_to_update.to_h do |name|
              response = ::GEPA::Strategies::InstructionProposalSignature.run(
                @reflection_lm,
                {
                  'current_instruction_doc' => candidate[name],
                  'dataset_with_feedback' => reflective_dataset.fetch(name, [])
                }
              )
              [name, response.fetch('new_instruction')]
            end
          else
            components_to_update.to_h do |name|
              [name, "#{candidate[name]} improved"]
            end
          end
        end

        private

        sig { params(program: DSPy::Module).returns(T::Array[[String, DSPy::Module]]) }
        def resolve_predictors(program)
          pairs = program.named_predictors
          pairs = [['self', program]] if pairs.empty?
          pairs
        end

        sig { params(mod: DSPy::Module).returns(DSPy::Module) }
        def clone_module(mod)
          safe_clone(mod)
        end

        sig { params(program: DSPy::Module).void }
        def duplicate_predictors!(program)
          resolve_predictors(program).each do |name, predictor|
            next unless @predictor_names.include?(name)
            next if predictor.equal?(program)
            clone = safe_clone(predictor)
            InstructionUpdates.replace_reference(program, predictor, clone)
          end
        end

        sig { params(program: DSPy::Module, recorder: T.nilable(T.untyped)).void }
        def wrap_predictors_for_tracing!(program, recorder: nil)
          return unless recorder

          resolve_predictors(program).each do |name, predictor|
            wrap_predictor_for_tracing(program, predictor, name, recorder)
          end
        end

        sig { params(program: DSPy::Module, predictor: DSPy::Module, name: String, recorder: T.untyped).void }
        def wrap_predictor_for_tracing(program, predictor, name, recorder)
          original_forward = predictor.method(:forward_untyped)
          recorder_ref = recorder
          predictor_name = name

          predictor.define_singleton_method(:forward_untyped) do |**input_values|
            result = original_forward.call(**input_values)
            recorder_ref.record(
              predictor_name: predictor_name,
              inputs: input_values.dup,
              output: result
            )
            result
          end
        end

        # instruction update helpers handled by InstructionUpdates

        sig { params(object: T.untyped).returns(T.untyped) }
        def safe_clone(object)
          object.clone
        rescue TypeError
          object.dup
        end

        class TraceRecorder
          def initialize
            @current_trace = nil
          end

          def start_example
            @current_trace = []
          end

          def record(entry)
            return unless @current_trace
            @current_trace << entry
          end

          def finish_example
            trace = @current_trace || []
            @current_trace = nil
            trace
          end
        end

        sig { params(program: DSPy::Module).returns(String) }
        def extract_instruction(program)
          if program.respond_to?(:prompt) && program.prompt.respond_to?(:instruction)
            program.prompt.instruction
          elsif program.respond_to?(:instruction)
            program.instruction
          else
            raise ArgumentError, "Program must expose prompt.instruction or #instruction"
          end
        end

        sig { params(struct: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_struct(struct)
          if struct.respond_to?(:to_h)
            struct.to_h
          elsif struct.instance_variables.any?
            struct.instance_variables.each_with_object({}) do |ivar, memo|
              key = ivar.to_s.delete_prefix('@').to_sym
              memo[key] = struct.instance_variable_get(ivar)
            end
          else
            {}
          end
        end

        sig { params(prediction: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_prediction(prediction)
          case prediction
          when DSPy::Prediction
            prediction.to_h
          when Hash
            prediction
          else
            serialize_struct(prediction)
          end
        end

        sig { params(expected: T::Hash[Symbol, T.untyped], actual: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def build_diff(expected, actual)
          keys = expected.keys | actual.keys
          keys.each_with_object({}) do |key, memo|
            exp = expected[key]
            act = actual[key]
            next if exp == act

            memo[key] = { expected: exp, actual: act }
          end
        end

        sig { params(result: T.untyped).returns([Float, T.nilable(String)]) }
        def extract_score_and_feedback(result)
          case result
          when DSPy::Prediction
            score = result.respond_to?(:score) ? result.score : 0.0
            feedback = result.respond_to?(:feedback) ? result.feedback : nil
            [score.to_f, feedback]
          when Hash
            [result[:score].to_f, result[:feedback]]
          else
            [result.to_f, nil]
          end
        end
      end

      sig do
        params(
          metric: T.proc.params(arg0: DSPy::Example, arg1: T.untyped).returns(T.untyped),
          reflection_lm: T.nilable(T.untyped),
          feedback_map: T.nilable(T::Hash[String, PredictAdapter::FeedbackFnType]),
          adapter_builder: T.nilable(T.proc.returns(T.untyped)),
          config: T.nilable(T::Hash[Symbol, T.untyped]),
          experiment_tracker: T.nilable(T.untyped)
        ).void
      end
      def initialize(metric:, reflection_lm: nil, feedback_map: nil, adapter_builder: nil, config: nil, experiment_tracker: nil)
        super(metric: metric)
        @metric = metric
        @reflection_lm = reflection_lm
        @feedback_map = (feedback_map || {}).transform_keys(&:to_s)
        @adapter_builder = adapter_builder || method(:build_adapter)
        @gepa_config = self.class.default_config.merge(config || {})
        @experiment_tracker = experiment_tracker
      end

      sig do
        override.params(
          program: DSPy::Module,
          trainset: T::Array[T.untyped],
          valset: T.nilable(T::Array[T.untyped])
        ).returns(OptimizationResult)
      end
      def compile(program, trainset:, valset: nil)
        validate_inputs(program, trainset, valset)

        typed_trainset = ensure_typed_examples(trainset)
        typed_valset = valset ? ensure_typed_examples(valset) : typed_trainset

        adapter = @adapter_builder.call(
          program,
          @metric,
          reflection_lm: @reflection_lm,
          feedback_map: @feedback_map
        )
        seed_candidate = adapter.seed_candidate

        cand_selector = ::GEPA::Strategies::ParetoCandidateSelector.new
        comp_selector = ::GEPA::Strategies::RoundRobinReflectionComponentSelector.new
        batch_sampler = ::GEPA::Strategies::EpochShuffledBatchSampler.new([@gepa_config[:minibatch_size], typed_trainset.size].min)

        telemetry_context = ::GEPA::Telemetry.build_context

        logger = ::GEPA::Logging::BufferingLogger.new
        tracker = @experiment_tracker || ::GEPA::Logging::ExperimentTracker.new

        reflective = ::GEPA::Proposer::ReflectiveMutationProposer.new(
          logger: logger,
          trainset: typed_trainset,
          adapter: adapter,
          candidate_selector: cand_selector,
          module_selector: comp_selector,
          batch_sampler: batch_sampler,
          perfect_score: @gepa_config[:perfect_score],
          skip_perfect_score: @gepa_config[:skip_perfect_score],
          experiment_tracker: tracker,
          reflection_lm: nil,
          telemetry: telemetry_context
        )

        evaluator = lambda do |dataset, candidate|
          batch = adapter.evaluate(dataset, candidate, capture_traces: false)
          [batch.outputs, batch.scores]
        end

        merge_proposer = nil
        if @gepa_config[:use_merge]
          merge_proposer = ::GEPA::Proposer::MergeProposer.new(
            logger: logger,
            valset: typed_valset,
            evaluator: evaluator,
            use_merge: true,
            max_merge_invocations: @gepa_config[:max_merge_invocations],
            rng: Random.new(0),
            telemetry: telemetry_context
          )
        end

        engine = ::GEPA::Core::Engine.new(
          evaluator: evaluator,
          valset: typed_valset,
          seed_candidate: seed_candidate,
          max_metric_calls: @gepa_config[:max_metric_calls],
          perfect_score: @gepa_config[:perfect_score],
          seed: 0,
          reflective_proposer: reflective,
          logger: logger,
          experiment_tracker: tracker,
          merge_proposer: merge_proposer,
          run_dir: nil,
          track_best_outputs: false,
          display_progress_bar: false,
          telemetry: telemetry_context,
          raise_on_exception: true
        )

        state = engine.run
        result = ::GEPA::Core::Result.from_state(state)
        best_program = adapter.build_program(result.best_candidate)

        OptimizationResult.new(
          optimized_program: best_program,
          scores: { best: result.val_aggregate_scores[result.best_idx] },
          history: { total_candidates: result.num_candidates },
          best_score_name: 'best',
          best_score_value: result.val_aggregate_scores[result.best_idx],
          metadata: { candidates: result.num_candidates }
        )
      end

      private

      sig do
        params(
          program: DSPy::Module,
          metric: T.proc.params(arg0: DSPy::Example, arg1: T.untyped).returns(T.untyped),
          reflection_lm: T.nilable(T.untyped),
          feedback_map: T::Hash[String, PredictAdapter::FeedbackFnType]
        ).returns(PredictAdapter)
      end
      def build_adapter(program, metric, reflection_lm: nil, feedback_map: {})
        PredictAdapter.new(program, metric, reflection_lm: reflection_lm, feedback_map: feedback_map)
      end
    end
  end
end
