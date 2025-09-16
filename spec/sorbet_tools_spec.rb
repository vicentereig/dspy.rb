require 'spec_helper'
require 'date'

# Test the new Sorbet Tool DSL
RSpec.describe 'DSPy::Tools::Baseq DSL' do
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
      temp_tool_class = Class.new(DSPy::Tools::Base) do
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
      expect(schema).to have_key(:function)
      expect(schema[:type]).to eq('function')
      expect(schema[:function]).to have_key(:parameters)
      expect(schema[:function][:parameters]).to have_key(:type)
      expect(schema[:function][:parameters]).to have_key(:properties)
      expect(schema[:function][:parameters][:type]).to eq('object')
    end

    it 'generates schema for tools with no parameters' do
      schema = SorbetGetTodaysDate.call_schema
      expect(schema[:function][:parameters][:properties]).to be_empty
      expect(schema[:function][:parameters][:required]).to be_empty
    end

    it 'generates schema for tools with required parameters' do
      schema = SorbetAddNumbers.call_schema
      properties = schema[:function][:parameters][:properties]
      expect(properties).to have_key(:x)
      expect(properties).to have_key(:y)
      expect(properties[:x][:type]).to eq('number')
      expect(properties[:y][:type]).to eq('number')
      expect(schema[:function][:parameters][:required]).to include('x', 'y')
    end

    it 'generates schema for tools with mixed parameter types' do
      schema = SorbetCalculatorTool.call_schema
      properties = schema[:function][:parameters][:properties]
      expect(properties).to have_key(:operation)
      expect(properties).to have_key(:num1)
      expect(properties).to have_key(:num2)
      expect(properties[:operation][:type]).to eq('string')
      expect(properties[:num1][:type]).to eq('number')
      expect(properties[:num2][:type]).to eq('number')
      expect(schema[:function][:parameters][:required]).to include('operation', 'num1', 'num2')
    end

    it 'generates schema for tools with optional parameters' do
      schema = SorbetGetRandomNumber.call_schema
      properties = schema[:function][:parameters][:properties]
      expect(properties).to have_key(:min)
      expect(properties).to have_key(:max)
      expect(properties[:min][:type]).to eq('integer')
      expect(properties[:max][:type]).to eq('integer')
      expect(properties[:min][:description]).to include('optional')
      expect(properties[:max][:description]).to include('optional')
      expect(schema[:function][:parameters][:required]).to be_empty # Both parameters are optional
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
