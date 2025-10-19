# frozen_string_literal: true

require 'spec_helper'
require 'dspy/teleprompt/gepa'

RSpec.describe 'GEPA teleprompter smoke test', :integration do
  before do
    DSPy::Observability.reset!
    DSPy::Context.clear!
  end

  class SmokeTestSignature < DSPy::Signature
    description "Return the instruction back"

    input do
      const :question, String
    end

    output do
      const :answer, String
    end
  end

  class SmokeTestModule < DSPy::Module
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

    sig { params(new_instruction: String).returns(SmokeTestModule) }
    def with_instruction(new_instruction)
      self.class.new(new_instruction)
    end

    sig { override.returns(T::Array[[String, DSPy::Module]]) }
    def named_predictors
      [['self', self]]
    end

    sig { override.params(input_values: T.untyped).returns(T::Hash[Symbol, String]) }
    def forward_untyped(**input_values)
      question = input_values[:question]
      { answer: "#{@instruction} #{question}" }
    end
  end

  class DeterministicReflectionLM
    attr_reader :calls, :prompt_history

    def initialize(response:)
      @response = response
      @calls = 0
      @prompt_history = []
    end

    def call(prompt)
      @calls += 1
      @prompt_history << prompt
      "```#{@response}```"
    end
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: SmokeTestSignature,
        input: { question: 'world' },
        expected: { answer: 'refined instruction world' }
      )
    ]
  end

  let(:metric) do
    lambda do |example, prediction|
      expected = example.expected_values[:answer]
      prediction[:answer] == expected ? 1.0 : 0.0
    end
  end

  it 'runs the full GEPA optimization loop with telemetry, logging, and reflection prompts' do
    captured_logger = nil
    allow(GEPA::Logging::BufferingLogger).to receive(:new).and_wrap_original do |original, *args, &block|
      captured_logger = original.call(*args, &block)
      captured_logger
    end

    captured_tracker = nil
    allow(GEPA::Logging::ExperimentTracker).to receive(:new).and_wrap_original do |original, *args, &block|
      captured_tracker = original.call(*args, &block)
      captured_tracker
    end

    spans = []
    allow(DSPy::Context).to receive(:with_span).and_wrap_original do |original, *args, **kwargs, &block|
      spans << kwargs[:operation]
      original.call(*args, **kwargs, &block)
    end

    reflection_lm = DeterministicReflectionLM.new(response: 'refined instruction')
    teleprompter = DSPy::Teleprompt::GEPA.new(metric: metric, reflection_lm: reflection_lm.method(:call).to_proc)

    result = teleprompter.compile(SmokeTestModule.new('base instruction'), trainset: trainset, valset: trainset)

    optimized = result.optimized_program
    expect(optimized.instruction).to eq('refined instruction')

    expect(reflection_lm.calls).to be >= 1
    expect(reflection_lm.prompt_history.last).to include('## Example 1')
    expect(reflection_lm.prompt_history.last).to include('Generated Outputs')

    expect(spans).to include('gepa.proposer.reflective_mutation.propose')
    expect(spans).to include('gepa.proposer.build_reflective_dataset')
    expect(spans).to include('gepa.proposer.propose_texts')

    expect(captured_logger).not_to be_nil
    expect(captured_logger.messages.join("\n")).to include('Proposed new text for self')

    expect(captured_tracker).not_to be_nil
    expect(captured_tracker.events).to include(hash_including(metrics: hash_including(:iteration => 1)))
    expect(captured_tracker.events).to include(hash_including(metrics: hash_including(:new_instruction_self => 'refined instruction')))
  end
end
