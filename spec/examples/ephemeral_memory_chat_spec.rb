# frozen_string_literal: true

require 'spec_helper'
require_relative '../../examples/ephemeral_memory_chat'

RSpec.describe EphemeralMemoryChat do
  FakeClassification = Struct.new(
    :level,
    :confidence,
    :reason,
    :suggested_cost_tier,
    keyword_init: true
  )

  class FakeClassifier < DSPy::Predict
    def initialize(responses)
      super(RouteChatRequest)
      @responses = responses.dup
    end

    def forward_untyped(**_input_values)
      raise 'No more responses' if @responses.empty?

      struct = @responses.shift
      RouteChatRequest.output_struct_class.new(
        level: struct.level,
        confidence: struct.confidence,
        reason: struct.reason,
        suggested_cost_tier: struct.suggested_cost_tier
      )
    end
  end

  class FakePredictor < DSPy::Module
    FakePrediction = Struct.new(:reply, :complexity, :next_action, keyword_init: true)

    attr_reader :lm, :calls

    def initialize(model_id:, label:)
      super()
      @lm = Struct.new(:model_id).new(model_id)
      @label = label
      @calls = []
    end

    def forward_untyped(**input_values)
      @calls << input_values
      FakePrediction.new(
        reply: "#{@label}: #{input_values[:user_message]}",
        complexity: ComplexityLevel::Routine,
        next_action: 'continue'
      )
    end
  end

  let(:classifier_responses) do
    [
      FakeClassification.new(
        level: ComplexityLevel::Routine,
        confidence: 0.81,
        reason: 'Short status request',
        suggested_cost_tier: 'fast'
      ),
      FakeClassification.new(
        level: ComplexityLevel::Critical,
        confidence: 0.92,
        reason: 'Needs detailed migration plan',
        suggested_cost_tier: 'deep'
      )
    ]
  end

  let(:classifier) { FakeClassifier.new(classifier_responses) }
  let(:fast_predictor) { FakePredictor.new(model_id: 'fast-model', label: 'FAST') }
  let(:deep_predictor) { FakePredictor.new(model_id: 'deep-model', label: 'DEEP') }

  let(:router) do
    ChatRouter.new(
      classifier: classifier,
      routes: {
        ComplexityLevel::Routine => fast_predictor,
        ComplexityLevel::Detailed => fast_predictor,
        ComplexityLevel::Critical => deep_predictor
      },
      default_level: ComplexityLevel::Routine
    )
  end

  let(:session) { EphemeralMemoryChat.new(signature: EphemeralMemoryChatSignature, router: router) }

  it 'stores alternating user/assistant turns with routed metadata' do
    session.call(user_message: 'Hi there')
    session.call(user_message: 'Need migration plan')

    roles = session.memory.map(&:role)
    expect(roles).to eq(%w[user assistant user assistant])

    assistant_models = session.memory.select { |turn| turn.role == 'assistant' }.map(&:model_id)
    expect(assistant_models).to eq(%w[fast-model deep-model])
  end

  it 'sends accumulated history into routed predictors' do
    session.call(user_message: 'Status update please')
    session.call(user_message: 'Plan rollout with details')

    history_for_deep = deep_predictor.calls.first[:history]
    expect(history_for_deep.length).to eq(2)
    expect(history_for_deep.first.message).to eq('Status update please')
    expect(history_for_deep.last.message).to include('FAST')
  end
end
