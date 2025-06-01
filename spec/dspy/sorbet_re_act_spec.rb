# frozen_string_literal: true

require 'spec_helper'
require 'dspy/sorbet_re_act'
require 'dspy/tools'

RSpec.describe 'DSPy::SorbetReAct' do
  # Define the DeepQA Signature using SorbetSignature
  class SorbetDeepQA < DSPy::SorbetSignature
    description "Answer questions with consideration for the context"
    
    input do |builder|
      builder.const :question, String
    end
    
    output do |builder|
      builder.const :answer, String
    end
  end

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
      expect(used_tools).to include("addnumbers")
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
      expect {
        VCR.use_cassette('openai/gpt4o-mini/sorbet_react_agent_valid_input') do
          agent.forward(question: "test question")
        end
      }.not_to raise_error
    end
  end
end

# Test the new Sorbet Tool DSL
RSpec.describe 'DSPy::Tools::SorbetTool DSL' do
  describe 'tool_name and tool_description DSL methods' do
    it 'sets and retrieves tool name correctly' do
      expect(SorbetGetTodaysDate.tool_name_value).to eq('get_todays_date')
      expect(SorbetGetTodaysDate.new.name).to eq('get_todays_date')
    end
    
    it 'sets and retrieves tool description correctly' do
      expect(SorbetGetTodaysDate.tool_description_value).to eq('Returns the current date in a human-readable format')
      expect(SorbetGetTodaysDate.new.description).to eq('Returns the current date in a human-readable format')
    end
    
    it 'falls back to class name when tool_name is not set' do
      # Create a tool class without tool_name DSL
      temp_tool_class = Class.new(DSPy::Tools::SorbetTool) do
        extend T::Sig
        sig { returns(String) }
        def call
          "test"
        end
      end
      
      # Should fall back to lowercased class name
      expect(temp_tool_class.new.name).to eq("unknown_tool")
    end
  end
  
  describe 'sig integration' do
    it 'properly types the call method parameters and return values' do
      tool = SorbetGetTodaysDate.new
      result = tool.call
      expect(result).to be_a(String)
      expect(result).to match(/\w+ \d{1,2}, \d{4}/) # Date format: "Month DD, YYYY"
    end
    
    it 'handles complex tool operations with proper typing' do
      calculator = SorbetCalculatorTool.new
      expect(calculator.call(operation: "add", num1: 10.0, num2: 20.0)).to eq(30.0)
      expect(calculator.call(operation: "multiply", num1: 5.0, num2: 6.0)).to eq(30.0)
      expect(calculator.call(operation: "divide", num1: 10.0, num2: 2.0)).to eq(5.0)
      expect(calculator.call(operation: "invalid", num1: 1.0, num2: 2.0)).to be_a(String) # Error message
    end
    
    it 'works with tools that have optional parameters' do
      random_tool = SorbetGetRandomNumber.new
      result = random_tool.call
      expect(result).to be_a(Integer)
      expect(result).to be_between(1, 100)
      
      # Should also work with nil input
      result2 = random_tool.call(min: 1, max: 100)
      expect(result2).to be_a(Integer)
      expect(result2).to be_between(1, 100)
    end
  end
  
  describe 'call_schema method' do
    it 'returns a basic schema structure' do
      schema = SorbetGetTodaysDate.call_schema
      expect(schema).to be_a(Hash)
      expect(schema).to have_key(:type)
      expect(schema).to have_key(:properties)
      expect(schema[:type]).to eq(:object)
    end
    
    it 'generates schema for tools with no parameters' do
      schema = SorbetGetTodaysDate.call_schema
      expect(schema[:properties]).to be_empty
      expect(schema[:required]).to be_empty
    end
    
    it 'generates schema for tools with required parameters' do
      schema = SorbetAddNumbers.call_schema
      expect(schema[:properties]).to have_key(:x)
      expect(schema[:properties]).to have_key(:y)
      expect(schema[:properties][:x][:type]).to eq(:number)
      expect(schema[:properties][:y][:type]).to eq(:number)
      expect(schema[:required]).to include('x', 'y')
    end
    
    it 'generates schema for tools with mixed parameter types' do
      schema = SorbetCalculatorTool.call_schema
      expect(schema[:properties]).to have_key(:operation)
      expect(schema[:properties]).to have_key(:num1)
      expect(schema[:properties]).to have_key(:num2)
      expect(schema[:properties][:operation][:type]).to eq(:string)
      expect(schema[:properties][:num1][:type]).to eq(:number)
      expect(schema[:properties][:num2][:type]).to eq(:number)
      expect(schema[:required]).to include('operation', 'num1', 'num2')
    end
    
    it 'generates schema for tools with optional parameters' do
      schema = SorbetGetRandomNumber.call_schema
      expect(schema[:properties]).to have_key(:min)
      expect(schema[:properties]).to have_key(:max)
      expect(schema[:properties][:min][:type]).to eq(:integer)
      expect(schema[:properties][:max][:type]).to eq(:integer)
      expect(schema[:properties][:min][:description]).to include('optional')
      expect(schema[:properties][:max][:description]).to include('optional')
      expect(schema[:required]).to be_empty # Both parameters are optional
    end
  end
  
  describe 'dynamic_call method' do
    it 'handles Hash input for tools with parameters' do
      tool = SorbetAddNumbers.new
      result = tool.dynamic_call({ "x" => 10, "y" => 20 })
      expect(result).to eq(30)
    end
    
    it 'handles JSON string input for tools with parameters' do
      tool = SorbetAddNumbers.new
      result = tool.dynamic_call('{"x": 15, "y": 25}')
      expect(result).to eq(40)
    end
    
    it 'returns error for missing required parameters' do
      tool = SorbetAddNumbers.new
      result = tool.dynamic_call('{"x": 10}')
      expect(result).to be_a(String)
      expect(result).to include("Missing required parameter: y")
    end
    
    it 'returns error for invalid JSON input' do
      tool = SorbetAddNumbers.new
      result = tool.dynamic_call('invalid json')
      expect(result).to be_a(String)
      expect(result).to include("Invalid JSON input")
    end
    
    it 'handles tools with no parameters' do
      tool = SorbetGetTodaysDate.new
      result = tool.dynamic_call({})
      expect(result).to be_a(String)
      expect(result).to include(Date.today.year.to_s)
    end
    
    it 'converts argument types correctly' do
      tool = SorbetCalculatorTool.new
      # Pass integers which should be converted to floats
      result = tool.dynamic_call({ "operation" => "add", "num1" => 10, "num2" => 20 })
      expect(result).to eq(30.0)
    end
    
    it 'handles tools with optional parameters' do
      tool = SorbetGetRandomNumber.new
      result = tool.dynamic_call({ "min" => 5, "max" => 10 })
      expect(result).to be_between(5, 10)
      
      # Test with no parameters (should use defaults)
      result_no_params = tool.dynamic_call({})
      expect(result_no_params).to be_between(1, 100)
    end
  end
end

# Enhanced tool definitions using the new Sorbet DSL
class SorbetGetTodaysDate < DSPy::Tools::SorbetTool
  extend T::Sig
  
  tool_name 'get_todays_date'
  tool_description 'Returns the current date in a human-readable format'
  
  sig { returns(String) }
  def call
    Date.today.strftime("%B %d, %Y")
  end
end

class SorbetAddNumbers < DSPy::Tools::SorbetTool
  extend T::Sig
  
  tool_name 'add_numbers'
  tool_description 'Adds two numbers together'
  
  sig { params(x: Numeric, y: Numeric).returns(Numeric) }
  def call(x:, y:)
    x + y
  end
end

# Example of a more complex tool with structured input/output
class SorbetCalculatorTool < DSPy::Tools::SorbetTool
  extend T::Sig
  
  tool_name 'calculator'
  tool_description 'Performs basic arithmetic operations'
  
  sig { params(operation: String, num1: Float, num2: Float).returns(T.any(Float, String)) }
  def call(operation:, num1:, num2:)
    case operation.downcase
    when 'add'
      num1 + num2
    when 'subtract'
      num1 - num2
    when 'multiply'
      num1 * num2
    when 'divide'
      return "Error: Cannot divide by zero" if num2 == 0
      num1 / num2
    else
      "Error: Unknown operation '#{operation}'. Use add, subtract, multiply, or divide"
    end
  end
end

# Example of a tool with optional parameters
class SorbetGetRandomNumber < DSPy::Tools::SorbetTool
  extend T::Sig
  
  tool_name 'get_random_number'
  tool_description 'Returns a random number'
  
  sig { params(min: T.nilable(Integer), max: T.nilable(Integer)).returns(Integer) }
  def call(min: nil, max: nil)
    min_val = min || 1
    max_val = max || 100
    rand(min_val..max_val)
  end
end
