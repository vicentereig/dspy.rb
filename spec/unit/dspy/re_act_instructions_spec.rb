# frozen_string_literal: true

require 'spec_helper'
require 'dspy/re_act'

class DescribedAgentSignature < DSPy::Signature
  description "You are a pirate assistant. Always answer in pirate speak."

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

class UndescribedAgentSignature < DSPy::Signature
  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

RSpec.describe 'ReAct loop instructions', type: :unit do
  let(:thought_instruction) do
    ->(agent) { agent.instance_variable_get(:@thought_generator).prompt.instruction }
  end

  let(:observation_instruction) do
    ->(agent) { agent.instance_variable_get(:@observation_processor).prompt.instruction }
  end

  it 'carries the user signature description into the loop prompt' do
    agent = DSPy::ReAct.new(DescribedAgentSignature, tools: [])

    expect(thought_instruction.call(agent))
      .to start_with("You are a pirate assistant. Always answer in pirate speak.")
    expect(observation_instruction.call(agent))
      .to start_with("You are a pirate assistant. Always answer in pirate speak.")
  end

  it 'appends the loop mechanics after the user instructions' do
    agent = DSPy::ReAct.new(DescribedAgentSignature, tools: [])

    expect(thought_instruction.call(agent))
      .to end_with("Generate a thought about what to do next to process the given inputs.")
    expect(observation_instruction.call(agent))
      .to end_with("Process the observation from a tool and decide what to do next.")
  end

  it 'falls back to the loop mechanics alone when the signature has no description' do
    agent = DSPy::ReAct.new(UndescribedAgentSignature, tools: [])

    expect(thought_instruction.call(agent))
      .to eq("Generate a thought about what to do next to process the given inputs.")
    expect(observation_instruction.call(agent))
      .to eq("Process the observation from a tool and decide what to do next.")
  end

  it 'still honors with_instruction overrides' do
    agent = DSPy::ReAct.new(DescribedAgentSignature, tools: []).with_instruction("Custom override.")

    expect(thought_instruction.call(agent)).to eq("Custom override.")
    expect(observation_instruction.call(agent)).to eq("Custom override.")
  end
end
