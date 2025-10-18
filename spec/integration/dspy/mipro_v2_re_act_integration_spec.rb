require 'spec_helper'

RSpec.describe 'MIPROv2 optimizing ReAct end-to-end' do
  let(:api_key_name) { 'OPENAI_API_KEY' }
  let(:api_key) { ENV[api_key_name] }
  class MIPROv2ReactSignature < DSPy::Signature
    description "Answer questions using concise grounded reasoning"

    input do
      const :question, String, description: "User question"
    end

    output do
      const :answer, String, description: "Final answer"
    end
  end

  module MIPROv2ReactTools
    class FactLookup < DSPy::Tools::Base
      tool_name "lookup_fact"
      tool_description "Returns the stored fact for simple geography questions"

      sig { params(question: String).returns(String) }
      def call(question:)
        question.downcase.include?("highest mountain") ? "Mount Everest" : "No data"
      end
    end
  end

  let(:train_examples) do
    [
      DSPy::Example.new(
        signature_class: MIPROv2ReactSignature,
        input: {
          question: "What is the highest mountain on Earth?"
        },
        expected: {
          answer: "Mount Everest"
        },
        id: "react_train_1"
      )
    ]
  end

  let(:validation_examples) { train_examples }

  let(:react_program) do
    DSPy::ReAct.new(
      MIPROv2ReactSignature,
      tools: [MIPROv2ReactTools::FactLookup.new],
      max_iterations: 1
    )
  end

  it 'compiles a ReAct program with per-predictor awareness', vcr: { cassette_name: 'miprov2/react_light' } do
    require_api_key!

    DSPy.configure do |config|
      config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: api_key)
      config.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
    end

    baseline_instructions = react_program.predictors.map { |predictor| predictor.prompt.instruction.dup }

    optimizer = DSPy::Teleprompt::MIPROv2.new(metric: proc { |example, prediction|
      prediction && prediction.respond_to?(:answer) && prediction.answer&.include?("Everest")
    })

    optimizer.configure do |config|
      config.num_trials = 1
      config.num_instruction_candidates = 1
      config.bootstrap_sets = 1
      config.max_bootstrapped_examples = 1
      config.max_labeled_examples = 1
      config.optimization_strategy = :greedy
      config.minibatch_size = nil
    end

    result = optimizer.compile(
      react_program,
      trainset: train_examples,
      valset: validation_examples
    )

    expect(result.metadata[:optimizer]).to eq("MIPROv2")
    expect(result.bootstrap_statistics[:num_predictors]).to eq(2)

    trial_logs = result.optimization_trace[:trial_logs]
    expect(trial_logs).not_to be_empty
    expect(trial_logs.values.all? { |entry| entry[:status] == :completed }).to eq(true)

    instructions_map = trial_logs.values.map { |entry| entry[:instructions] }.compact.first
    expect(instructions_map).not_to be_nil
    expect(instructions_map.keys).to include(0)
    expect(instructions_map.keys).to include(1)
    expect(instructions_map[0]).to be_a(String)
    expect(instructions_map[1]).to be_a(String)

    optimized_program = result.optimized_program
    expect(optimized_program.predictors.size).to eq(2)
  end
end
