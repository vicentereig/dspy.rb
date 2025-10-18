# frozen_string_literal: true

require 'logger'
require 'sorbet-runtime'
require_relative 'teleprompter'
require_relative 'utils'
require_relative '../../gepa'

module DSPy
  module Teleprompt
    class GEPA < Teleprompter
      extend T::Sig
      DEFAULT_CONFIG = {
        max_metric_calls: 32,
        minibatch_size: 2,
        perfect_score: 1.0,
        skip_perfect_score: true
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

        sig do
          params(
            student: DSPy::Module,
            metric: T.proc.params(arg0: DSPy::Example, arg1: T.untyped).returns(T.untyped),
            reflection_lm: T.nilable(T.untyped)
          ).void
        end
        def initialize(student, metric, reflection_lm: nil)
          @student = student
          @metric = metric
          @reflection_lm = reflection_lm

          name, = @student.named_predictors.first
          @predictor_name = name
          @seed_instruction = extract_instruction(@student)
        end

        sig { returns(T::Hash[String, String]) }
        def seed_candidate
          { @predictor_name => @seed_instruction }
        end

        sig { params(candidate: T::Hash[String, String]).returns(DSPy::Module) }
        def build_program(candidate)
          new_instruction = candidate.fetch(@predictor_name)
          if @student.respond_to?(:with_instruction)
            @student.with_instruction(new_instruction)
          else
            raise ArgumentError, "Student module must respond to #with_instruction"
          end
        end

        sig do
          params(
            batch: T::Array[DSPy::Example],
            candidate: T::Hash[String, String],
            capture_traces: T::Boolean
          ).returns(::GEPA::Core::EvaluationBatch)
        end
        def evaluate(batch, candidate, capture_traces: false)
          program = build_program(candidate)

          if capture_traces
            trajectories = batch.map do |example|
              prediction = program.call(**example.input_values)
              result = @metric.call(example, prediction)
              score, feedback = extract_score_and_feedback(result)

              {
                predictor_name: @predictor_name,
                example: example,
                prediction: prediction,
                score: score,
                feedback: feedback
              }
            end

            scores = trajectories.map { |row| row[:score] }
            outputs = trajectories.map { |row| row[:prediction] }
            ::GEPA::Core::EvaluationBatch.new(outputs: outputs, scores: scores, trajectories: trajectories)
          else
            evaluator = DSPy::Evaluate.new(program, metric: nil, num_threads: nil, max_errors: batch.length * 100, provide_traceback: false)
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

          dataset = {}
          components_to_update.each do |component|
            rows = Array(eval_batch.trajectories).map do |trajectory|
              next unless trajectory[:predictor_name] == component

              example = trajectory[:example]
              prediction = trajectory[:prediction]
              inputs = serialize_struct(example.input)
              expected = serialize_struct(example.expected)
              actual = serialize_prediction(prediction)

              diff = build_diff(expected, actual)

              {
                'Inputs' => inputs,
                'Expected' => expected,
                'Generated Outputs' => actual,
                'Diff' => diff,
                'Feedback' => trajectory[:feedback] || "Score: #{trajectory[:score]}"
              }
            end.compact
            dataset[component] = rows unless rows.empty?
          end

          dataset
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
          adapter_builder: T.nilable(T.proc.params(arg0: DSPy::Module, arg1: T.proc.params(arg0: DSPy::Example, arg1: T.untyped).returns(T.untyped), reflection_lm: T.nilable(T.untyped)).returns(T.untyped)),
          config: T.nilable(T::Hash[Symbol, T.untyped])
        ).void
      end
      def initialize(metric:, reflection_lm: nil, adapter_builder: nil, config: nil)
        super(metric: metric)
        @metric = metric
        @reflection_lm = reflection_lm
        @adapter_builder = adapter_builder || method(:build_adapter)
        @gepa_config = self.class.default_config.merge(config || {})
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

        adapter = @adapter_builder.call(program, @metric, reflection_lm: @reflection_lm)
        seed_candidate = adapter.seed_candidate

        cand_selector = ::GEPA::Strategies::ParetoCandidateSelector.new
        comp_selector = ::GEPA::Strategies::RoundRobinReflectionComponentSelector.new
        batch_sampler = ::GEPA::Strategies::EpochShuffledBatchSampler.new([@gepa_config[:minibatch_size], typed_trainset.size].min)

        telemetry_context = ::GEPA::Telemetry.build_context

        logger = ::GEPA::Logging::BufferingLogger.new
        tracker = ::GEPA::Logging::ExperimentTracker.new

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
          merge_proposer: nil,
          run_dir: nil,
          track_best_outputs: false,
          display_progress_bar: false,
          telemetry: telemetry_context
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

      sig { params(program: DSPy::Module, metric: T.proc.params(arg0: DSPy::Example, arg1: T.untyped).returns(T.untyped), reflection_lm: T.nilable(T.untyped)).returns(PredictAdapter) }
      def build_adapter(program, metric, reflection_lm: nil)
        PredictAdapter.new(program, metric, reflection_lm: reflection_lm)
      end
    end
  end
end
