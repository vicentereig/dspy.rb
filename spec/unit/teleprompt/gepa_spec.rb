# frozen_string_literal: true

require 'spec_helper'
require 'dspy/teleprompt/gepa'

RSpec.describe DSPy::Teleprompt::GEPA do
  before do
    DSPy::Observability.reset!
  end

  class SimpleSignature < DSPy::Signature
    description "Return the instruction back"

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

  let(:metric) do
    lambda do |example, prediction|
      expected = example.expected_values[:answer]
      actual = prediction[:answer]
      actual == expected ? 1.0 : 0.0
    end
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: SimpleSignature,
        input: { question: 'world' },
        expected: { answer: 'base improved world' }
      )
    ]
  end

  it 'optimizes instruction text using GEPA engine pipeline' do
    teleprompter = described_class.new(metric: metric)

    adapter = teleprompter.send(:build_adapter, EchoModule.new('base'), metric)
    base_eval = adapter.evaluate(trainset, adapter.seed_candidate, capture_traces: true)
    expect(base_eval.scores).to eq([0.0])
    improved_eval = adapter.evaluate(trainset, { 'self' => 'base improved' }, capture_traces: false)
    expect(improved_eval.scores).to eq([1.0])

    result = teleprompter.compile(EchoModule.new('base'), trainset: trainset, valset: trainset)

    optimized = result.optimized_program
    expect(optimized).to be_a(EchoModule)
    expect(result.metadata[:candidates]).to be > 1

    output = optimized.call(question: 'world')
    expect(output[:answer]).to eq('base improved world')
    expect(result.best_score_value).to eq(1.0)
  end
end
