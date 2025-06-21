# frozen_string_literal: true

require 'spec_helper'
require 'dspy/re_act'
require 'dspy/tools'

class DeepQA < DSPy::Signature
  description "Answer questions with consideration for the context"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

RSpec.describe 'DSPy::ReAct' do
  describe 'when answering a question using a Sorbet signature (auto-augmented output)' do
    let(:date_tool) { SorbetGetTodaysDate.new }
    let(:add_tool) { SorbetAddNumbers.new }
    let(:calculator_tool) { SorbetCalculatorTool.new }
    let(:get_random_number_tool) { SorbetGetRandomNumber.new }
    let(:tools) { [date_tool, add_tool, calculator_tool, get_random_number_tool] }
    let(:agent) { DSPy::ReAct.new(DeepQA, tools: tools) }
    let!(:result) do # Use let! to ensure this runs before each 'it' block in this context
      VCR.use_cassette('openai/gpt4o-mini/sorbet_react_agent_auto_augmented_output') do
        agent.forward(question: "What is 42 plus 58?")
      end
    end

    before(:all) do # Configure DSPy once for this describe block
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
    end

    it 'provides the correct answer' do
      expect(result.answer).to include("100")
    end

    it 'responds to :history' do
      expect(result).to respond_to(:history)
    end

    it 'has history as an array of hashes' do
      expect(result.history).to be_an(Array)
      result.history.each do |entry|
        expect(entry).to be_a(Hash)
        expect(entry).to have_key(:step)
        expect(entry).to have_key(:thought)
        expect(entry).to have_key(:action)
        expect(entry).to have_key(:action_input)
      end
    end

    it 'responds to :iterations' do
      expect(result).to respond_to(:iterations)
    end

    it 'has iterations as an integer' do
      expect(result.iterations).to be_an(Integer)
      expect(result.iterations).to be > 0
    end

    it 'validates that the enhanced output struct is accessible' do
      expect(result.class.superclass).to eq(T::Struct)
    end

    it 'creates result instances of the enhanced output struct' do
      expect(result.class.superclass.name).to eq("T::Struct")
    end

    it 'history contains expected fields' do
      expect(result.history).not_to be_empty
      
      # Validate structure of history entries
      history_entry = result.history.first
      
      expect(history_entry[:thought]).to be_a(String)
      expect(history_entry[:action]).to be_a(String)  
      expect(history_entry[:action_input]).to satisfy { |val| val.is_a?(String) || val.is_a?(Hash) }
      expect(history_entry[:step]).to be_an(Integer)
      
      # Verify that actions used are from available tools
      actions_used = result.history.map { |entry| entry[:action] }.uniq
      tool_names = tools.map(&:name) + ['finish']
      
      actions_used.each do |action|
        expect(tool_names).to include(action), "Action '#{action}' is not in available tools: #{tool_names}"
      end
    end

    it 'uses tools correctly during reasoning' do
      # Check that at least one tool was used (excluding 'finish')
      tool_actions = result.history.map { |entry| entry[:action] }.reject { |action| action == 'finish' }
      expect(tool_actions).not_to be_empty, "Expected at least one tool to be used, but history shows: #{result.history.map { |h| h[:action] }}"
    end

    it 'reaches a finish action' do
      finish_actions = result.history.select { |entry| entry[:action] == 'finish' }
      expect(finish_actions).not_to be_empty, "Expected a 'finish' action but history shows: #{result.history.map { |h| h[:action] }}"
    end

    it 'provides reasoning in the thought process' do
      thoughts = result.history.map { |entry| entry[:thought] }
      expect(thoughts.any? { |thought| thought.length > 10 }).to be(true), "Expected substantial reasoning in thoughts"
    end
  end
end
