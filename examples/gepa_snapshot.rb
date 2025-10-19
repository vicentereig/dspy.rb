# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative '../lib/dspy/teleprompt/gepa'

module Examples
  module GEPA
    class SimpleSignature < DSPy::Signature
      description 'Return instruction'

      input do
        const :question, String
      end

      output do
        const :answer, String
      end
    end

    class EchoModule < DSPy::Module
      extend T::Sig

      sig { params(instruction: String).void }
      def initialize(instruction)
        super()
        @instruction = instruction
      end

      sig { returns(String) }
      def instruction
        @instruction
      end

      sig { params(new_instruction: String).returns(EchoModule) }
      def with_instruction(new_instruction)
        self.class.new(new_instruction)
      end

      sig { override.returns(T::Array[[String, DSPy::Module]]) }
      def named_predictors
        [['self', self]]
      end

      sig { params(input_values: T.untyped).returns(T::Hash[Symbol, String]) }
      def forward_untyped(**input_values)
        { answer: "#{@instruction} #{input_values[:question]}" }
      end
    end

    METRIC = lambda do |example, prediction|
      prediction[:answer] == example.expected_values[:answer] ? 1.0 : 0.0
    end

    TRAINSET = [
      DSPy::Example.new(
        signature_class: SimpleSignature,
        input: { question: 'world' },
        expected: { answer: 'refined instruction world' }
      )
    ].freeze

    class FixtureReflectionLM
      def initialize(response)
        @response = response
      end

      def call(_prompt)
        @response
      end
    end
  end
end

module Examples
  module GEPA
    OUTPUT_PATH = File.expand_path('../spec/fixtures/gepa/smoke_snapshot.yml', __dir__)

    def self.generate_snapshot(response: "```\nrefined instruction\n```")
      reflection_lm = FixtureReflectionLM.new(response)
      teleprompter = DSPy::Teleprompt::GEPA.new(
        metric: METRIC,
        reflection_lm: reflection_lm.method(:call).to_proc
      )

      result = teleprompter.compile(
        EchoModule.new('base instruction'),
        trainset: TRAINSET,
        valset: TRAINSET
      )

      adapter = teleprompter.send(:build_adapter, result.optimized_program, METRIC)
      evaluation = adapter.evaluate(TRAINSET, adapter.seed_candidate, capture_traces: true)

      trace_snapshot = evaluation.trajectories.map do |trajectory|
        Array(trajectory[:trace]).map do |entry|
          {
            'predictor' => entry[:predictor_name],
            'inputs' => entry[:inputs],
            'output' => entry[:output]
          }
        end
      end

      snapshot = {
        'optimized_instruction' => result.optimized_program.instruction,
        'candidates' => result.metadata[:candidates],
        'best_score_value' => result.best_score_value,
        'trace' => trace_snapshot
      }

      if block_given?
        yield(snapshot)
      else
        FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
        File.write(OUTPUT_PATH, YAML.dump(snapshot))
      end

      snapshot
    end
  end
end

if $PROGRAM_NAME == __FILE__
  snapshot = Examples::GEPA.generate_snapshot
  puts "Snapshot written to #{Examples::GEPA::OUTPUT_PATH}"
  puts YAML.dump(snapshot)
end
