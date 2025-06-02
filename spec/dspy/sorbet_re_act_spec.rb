# frozen_string_literal: true

require 'spec_helper'
require 'dspy/sorbet_re_act'
require 'dspy/tools'
class SorbetDeepQA < DSPy::SorbetSignature
  description "Answer questions with consideration for the context"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end


RSpec.describe 'DSPy::SorbetReAct' do
  describe 'when answering a question using a Sorbet signature (auto-augmented output)' do
    let(:date_tool) { SorbetGetTodaysDate.new }
    let(:add_tool) { SorbetAddNumbers.new }
    let(:calculator_tool) { SorbetCalculatorTool.new }
    let(:get_random_number_tool) { SorbetGetRandomNumber.new }
    let(:tools) { [date_tool, add_tool, calculator_tool, get_random_number_tool] }
    let(:agent) { DSPy::SorbetReAct.new(SorbetDeepQA, tools: tools) }
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
      expect(result.history).not_to be_empty
      result.history.each do |entry|
        expect(entry).to be_a(Hash)
        expect(entry).to have_key(:step)
        expect(entry[:step]).to be_an(Integer)
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
      expect(agent.enhanced_output_struct).to be_a(Class)
      expect(agent.enhanced_output_struct < T::Struct).to be_truthy
    end

    it 'creates result instances of the enhanced output struct' do
      expect(result).to be_an_instance_of(agent.enhanced_output_struct)
    end

    it 'history contains expected fields' do
      expect(result.history).not_to be_empty

      result.history.each do |entry|
        expect(entry).to have_key(:step)
        expect(entry).to have_key(:thought)
        expect(entry).to have_key(:action)
        expect(entry).to have_key(:action_input)

        expect(entry[:step]).to be_an(Integer)
        expect(entry[:thought]).to be_a(String) if entry[:thought]
        expect(entry[:action]).to be_a(String) if entry[:action]
      end
    end

    it 'uses tools correctly during reasoning' do
      # Check that the agent used the AddNumbers tool
      used_tools = result.history.map { |entry| entry[:action] }.compact
      expect(used_tools).to include("add_numbers")
    end

    it 'reaches a finish action' do
      finish_actions = result.history.select { |entry| entry[:action]&.downcase == "finish" }
      expect(finish_actions).not_to be_empty
    end

    it 'provides reasoning in the thought process' do
      thoughts = result.history.map { |entry| entry[:thought] }.compact
      expect(thoughts).not_to be_empty
      thoughts.each do |thought|
        expect(thought).to be_a(String)
        expect(thought.length).to be > 0
      end
    end
  end

  describe 'when max_iterations is reached' do
    let(:tools) { [] } # No tools to force max iterations
    let(:agent) { DSPy::SorbetReAct.new(SorbetDeepQA, tools: tools, max_iterations: 2) }

    let!(:result) do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_react_agent_max_iterations') do
        agent.forward(question: "What is the weather today?")
      end
    end

    before(:all) do
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
    end

    it 'respects max_iterations limit' do
      # The agent should not exceed max_iterations, but may finish early if it realizes the task is impossible
      expect(result.iterations).to be <= 2
      expect(result.iterations).to be >= 1
    end

    it 'still provides history even when max iterations reached' do
      expect(result.history).not_to be_empty
      expect(result.history.length).to be <= 2
    end
  end

  describe 'input validation' do
    let(:agent) { DSPy::SorbetReAct.new(SorbetDeepQA, tools: []) }

    it 'validates required input fields' do
      expect {
        agent.forward(wrong_field: "test")
      }.to raise_error(ArgumentError, /Missing required prop/)
    end

    it 'accepts valid input' do
      result = VCR.use_cassette('openai/gpt4o-mini/sorbet_react_agent_valid_input') do
        agent.forward(question: "test question")
      end
      
      # Verify the result has the expected structure
      expect(result).to respond_to(:answer)
      expect(result).to respond_to(:history)
      expect(result).to respond_to(:iterations)
      
      # Verify the types
      expect(result.answer).to be_a(String)
      expect(result.history).to be_an(Array)
      expect(result.iterations).to be_an(Integer)
      
      # Verify the content is not empty
      expect(result.answer).not_to be_empty
      expect(result.iterations).to be > 0
    end
  end
end
