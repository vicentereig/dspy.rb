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

  class CompositeModule < DSPy::Module
    extend T::Sig

    sig { params(alpha_instruction: String, beta_instruction: String).void }
    def initialize(alpha_instruction, beta_instruction)
      super()
      @alpha = EchoModule.new(alpha_instruction)
      @beta = EchoModule.new(beta_instruction)
    end

    sig { override.returns(T::Array[[String, DSPy::Module]]) }
    def named_predictors
      [['alpha', @alpha], ['beta', @beta]]
    end

    sig { params(input_values: T.untyped).returns(T::Hash[Symbol, String]) }
    def forward_untyped(**input_values)
      first = @alpha.forward_untyped(**input_values)
      second = @beta.forward_untyped(**input_values)
      { answer: "#{first[:answer]} | #{second[:answer]}" }
    end
  end

  class FakeReflectionLM
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def call(_prompt)
      @calls += 1
      "```
base reflection upgrade
```"
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

  it 'uses the provided reflection LM when available' do
    reflection_metric = lambda do |_example, prediction|
      prediction[:answer] == 'base reflection upgrade world' ? 1.0 : 0.0
    end
    reflection_trainset = [
      DSPy::Example.new(
        signature_class: SimpleSignature,
        input: { question: 'world' },
        expected: { answer: 'base reflection upgrade world' }
      )
    ]

    reflection_lm = FakeReflectionLM.new
    teleprompter = described_class.new(metric: reflection_metric, reflection_lm: reflection_lm.method(:call).to_proc)

    result = teleprompter.compile(EchoModule.new('base'), trainset: reflection_trainset, valset: reflection_trainset)

    optimized = result.optimized_program
    expect(reflection_lm.calls).to be > 0

    output = optimized.call(question: 'world')
    expect(output[:answer]).to eq('base reflection upgrade world')
  end

  it 'supports multi-predictor instruction candidates' do
    adapter = DSPy::Teleprompt::GEPA::PredictAdapter.new(CompositeModule.new('alpha base', 'beta base'), metric)

    seed = adapter.seed_candidate
    expect(seed).to eq('alpha' => 'alpha base', 'beta' => 'beta base')

    updated = adapter.build_program({ 'alpha' => 'alpha refined', 'beta' => 'beta refined' })
    predictors = updated.named_predictors.to_h { |name, module_obj| [name, module_obj] }

    expect(predictors['alpha'].instruction).to eq('alpha refined')
    expect(predictors['beta'].instruction).to eq('beta refined')

    original_predictors = adapter.instance_variable_get(:@student).named_predictors.to_h { |name, module_obj| [name, module_obj] }
    expect(original_predictors['alpha'].instruction).to eq('alpha base')
    expect(original_predictors['beta'].instruction).to eq('beta base')

    eval_batch = adapter.evaluate(trainset, adapter.seed_candidate, capture_traces: true)
    trace = eval_batch.trajectories.first[:trace]
    expect(trace.map { |entry| entry[:predictor_name] }).to include('alpha', 'beta')
  end
end
