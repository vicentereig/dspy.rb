# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::ReAct' do
  # Define the DeepQA Signature as requested by the user
  class DeepQA < DSPy::Signature
    description "Given a question finds the answer"

    input do
      required(:question).value(:string).meta(description: 'the question we want to answer')
    end

    output do
      required(:answer).value(:string).meta(description: 'The actual answer')
      # history and iterations are now automatically added by ReAct
    end
  end

  describe 'when answering a question using a signature (auto-augmented output)' do
    let(:date_tool) { GetTodaysDate.new }
    let(:add_tool) { AddNumbers.new }
    let(:tools) { [date_tool, add_tool] }
    let(:agent) { DSPy::ReAct.new(DeepQA, tools: tools) }
    let!(:result) do # Use let! to ensure this runs before each 'it' block in this context
      VCR.use_cassette('openai/gpt4o-mini/react_agent_auto_augmented_output') do
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
      expect(result.history).not_to be_empty
      result.history.each do |entry|
        expect(entry).to be_a(Hash)
        expect(entry).to have_key(:step)
        expect(entry[:step]).to be_an(Integer)
      end
    end

    it 'history includes the first thought' do
      first_entry = result.history.find { |entry| entry[:step] == 1 }
      expect(first_entry).not_to be_nil
      expect(first_entry[:thought]).to match(/what 42 plus 58 is/i) # More flexible matching for thought
    end

    it 'history includes the add_numbers action and its details' do
      add_action_entry = result.history.find { |entry| entry[:action]&.downcase == "add_numbers" }
      expect(add_action_entry).not_to be_nil
      expect(add_action_entry[:action]).to eq("add_numbers")
      expect(add_action_entry[:action_input]).to match(/42\s*,\s*58/) # Flexible for spacing
      expect(add_action_entry[:observation]).to match(/100(\.0)?/) # Allow for 100 or 100.0
    end

    it 'history includes the finish action and its input' do
      finish_action_entry = result.history.find { |entry| entry[:action]&.downcase == "finish" }
      expect(finish_action_entry).not_to be_nil
      expect(finish_action_entry[:action]).to eq("finish")
      expect(finish_action_entry[:action_input]).to match(/100(\.0)?/) # Allow for 100 or 100.0
    end

    it 'responds to :iterations' do
      expect(result).to respond_to(:iterations)
    end

    it 'has iterations as an integer' do
      expect(result.iterations).to be_an(Integer)
    end

    it 'has a positive number of iterations' do
      expect(result.iterations).to be > 0
    end
  end
end

unless defined?(GetTodaysDate)
  class GetTodaysDate < DSPy::Tools::Tool
    def initialize
      super('get_todays_date', 'Get today\'s date')
    end

    def call(input = nil)
      Date.today.to_s
    end
  end
end

unless defined?(AddNumbers)
  class AddNumbers < DSPy::Tools::Tool
    def initialize
      super('add_numbers', 'Add two numbers together')
    end

    def call(input)
      numbers = input.split(',').map(&:strip).map(&:to_f)
      if numbers.length != 2
        raise ArgumentError, "Expected exactly 2 numbers separated by comma, got: #{input}"
      end
      numbers.sum.to_s
    end
  end
end
