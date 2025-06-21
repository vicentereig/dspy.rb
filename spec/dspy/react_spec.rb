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
    let(:question) { "What is 42 plus 58?" }
    let(:date_tool) { SorbetGetTodaysDate.new }
    let(:add_tool) { SorbetAddNumbers.new }
    let(:calculator_tool) { SorbetCalculatorTool.new }
    let(:get_random_number_tool) { SorbetGetRandomNumber.new }
    let(:tools) { [date_tool, add_tool, calculator_tool, get_random_number_tool] }
    let(:agent) { DSPy::ReAct.new(DeepQA, tools: tools) }
    let(:prediction) do
      VCR.use_cassette('openai/gpt4o-mini/sorbet_react_agent_auto_augmented_output') do
        agent.forward(question: question)
      end
    end

    before(:all) do # Configure DSPy once for this describe block
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
    end

    it 'includes the input fields in the combined output struct' do
      expect(prediction.question).to include(question)
    end

    it 'provides the correct answer' do
      expect(prediction.answer).to include("100")
    end

    it 'responds to :history' do
      expect(prediction).to respond_to(:history)
    end

    it 'has history as an array of hashes' do
      expect(prediction.history).to be_an(Array)
    end

    it 'has history entries as hashes' do
      prediction.history.each do |entry|
        expect(entry).to be_a(Hash)
      end
    end

    it 'has history entries with :step key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:step)
      end
    end

    it 'has history entries with :thought key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:thought)
      end
    end

    it 'has history entries with :action key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:action)
      end
    end

    it 'has history entries with :action_input key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:action_input)
      end
    end

    it 'responds to :iterations' do
      expect(prediction).to respond_to(:iterations)
    end

    it 'has iterations as an integer' do
      expect(prediction.iterations).to be > 0
    end

    it 'validates that the enhanced output struct is accessible' do
      expect(prediction.class.superclass).to eq(T::Struct)
    end

    it 'creates result instances of the enhanced output struct' do
      expect(prediction.class.superclass.name).to eq("T::Struct")
    end

    it 'history contains expected fields' do
      expect(prediction.history).not_to be_empty
    end

    it 'history entries have thought as a string' do
      prediction.history.each do |entry|
        expect(entry[:thought]).to be_a(String)
      end
    end

    it 'history entries have action as a string' do
      prediction.history.each do |entry|
        expect(entry[:action]).to be_a(String)
      end
    end

    it 'history entries have action_input as a string or hash' do
      prediction.history.each do |entry|
        expect(entry[:action_input]).to satisfy { |val| val.is_a?(String) || val.is_a?(Hash) }
      end
    end

    it 'history entries have step as an integer' do
      prediction.history.each do |entry|
        expect(entry[:step]).to be_an(Integer)
      end
    end

    it 'actions used are from available tools' do
      actions_used = prediction.history.map { |entry| entry[:action] }.uniq
      tool_names = tools.map(&:name) + ['finish']
      actions_used.each do |action|
        expect(tool_names).to include(action), "Action '#{action}' is not in available tools: #{tool_names}"
      end
    end

    it 'uses tools correctly during reasoning' do
      tool_actions = prediction.history.map { |entry| entry[:action] }.reject { |action| action == 'finish' }
      expect(tool_actions).not_to be_empty, "Expected at least one tool to be used, but history shows: #{prediction.history.map { |h| h[:action] }}"
    end

    it 'reaches a finish action' do
      finish_actions = prediction.history.select { |entry| entry[:action] == 'finish' }
      expect(finish_actions).not_to be_empty, "Expected a 'finish' action but history shows: #{prediction.history.map { |h| h[:action] }}"
    end

    it 'provides reasoning in the thought process' do
      thoughts = prediction.history.map { |entry| entry[:thought] }
      expect(thoughts.any? { |thought| thought.length > 10 }).to be(true), "Expected substantial reasoning in thoughts"
    end
  end

  describe 'tool schema serialization' do
    let(:date_tool) { SorbetGetTodaysDate.new }
    let(:add_tool) { SorbetAddNumbers.new }
    let(:calculator_tool) { SorbetCalculatorTool.new }
    let(:tools) { [date_tool, add_tool, calculator_tool] }
    let(:agent) { DSPy::ReAct.new(DeepQA, tools: tools) }

    it 'generates valid JSON for each tool schema' do
      tools.each do |tool|
        expect { JSON.parse(tool.schema) }.not_to raise_error
      end
    end

    it 'does not contain escaped newlines in tool schemas' do
      tools.each do |tool|
        schema_json = tool.schema
        expect(schema_json).not_to include('\\n')
      end
    end

    it 'produces compact single-line JSON schemas' do
      tools.each do |tool|
        schema_json = tool.schema
        expect(schema_json.lines.count).to eq(1)
      end
    end

    it 'includes name field in tool schema structure' do
      tools.each do |tool|
        parsed_schema = JSON.parse(tool.schema)
        expect(parsed_schema).to have_key('name')
      end
    end

    it 'includes description field in tool schema structure' do
      tools.each do |tool|
        parsed_schema = JSON.parse(tool.schema)
        expect(parsed_schema).to have_key('description')
      end
    end

    it 'includes parameters field in tool schema structure' do
      tools.each do |tool|
        parsed_schema = JSON.parse(tool.schema)
        expect(parsed_schema).to have_key('parameters')
      end
    end

    it 'has parameters with type field' do
      tools.each do |tool|
        parsed_schema = JSON.parse(tool.schema)
        expect(parsed_schema['parameters']).to have_key('type')
      end
    end

    it 'has parameters with object type' do
      tools.each do |tool|
        parsed_schema = JSON.parse(tool.schema)
        expect(parsed_schema['parameters']['type']).to eq('object')
      end
    end

    it 'creates available_tools as an array' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      expect(available_tools_array).to be_an(Array)
    end

    it 'has correct number of tools in available_tools array' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      expect(available_tools_array.length).to eq(3)
    end

    it 'has each available_tools element as a hash' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema).to be_a(Hash)
      end
    end

    it 'has name field in each available_tools element' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema).to have_key('name')
      end
    end

    it 'has description field in each available_tools element' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema).to have_key('description')
      end
    end

    it 'has parameters field in each available_tools element' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema).to have_key('parameters')
      end
    end

    it 'has type field in each tool parameters' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params).to have_key('type')
      end
    end

    it 'has properties field in each tool parameters' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params).to have_key('properties')
      end
    end

    it 'has required field in each tool parameters' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params).to have_key('required')
      end
    end

    it 'has object type in each tool parameters' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params['type']).to eq('object')
      end
    end

    it 'has properties as hash in each tool parameters' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params['properties']).to be_a(Hash)
      end
    end

    it 'has required as array in each tool parameters' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params['required']).to be_an(Array)
      end
    end

    it 'maintains identical schemas after round-trip serialization' do
      tools.each do |tool|
        original_schema = tool.schema
        parsed = JSON.parse(original_schema)
        reserialized = JSON.generate(parsed)
        expect(reserialized).to eq(original_schema)
      end
    end

    it 'allows re-parsing after round-trip serialization' do
      tools.each do |tool|
        original_schema = tool.schema
        parsed = JSON.parse(original_schema)
        reserialized = JSON.generate(parsed)
        reparsed = JSON.parse(reserialized)
        expect(reparsed).to eq(parsed)
      end
    end

    it 'includes required fields for OpenAI function calling format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema.keys).to include('name', 'description', 'parameters')
      end
    end

    it 'has string names in OpenAI format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema['name']).to be_a(String)
      end
    end

    it 'has non-empty names in OpenAI format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema['name']).not_to be_empty
      end
    end

    it 'has string descriptions in OpenAI format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema['description']).to be_a(String)
      end
    end

    it 'has non-empty descriptions in OpenAI format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        expect(tool_schema['description']).not_to be_empty
      end
    end

    it 'has object type for parameters in OpenAI format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params['type']).to eq('object')
      end
    end

    it 'has properties key for parameters in OpenAI format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params).to have_key('properties')
      end
    end

    it 'has required key for parameters in OpenAI format' do
      tools_hash = agent.instance_variable_get(:@tools)
      available_tools_array = tools_hash.map { |name, tool| JSON.parse(tool.schema) }
      
      available_tools_array.each do |tool_schema|
        params = tool_schema['parameters']
        expect(params).to have_key('required')
      end
    end

    it 'has correct name for get_todays_date schema' do
      date_schema = JSON.parse(date_tool.schema)
      expect(date_schema['name']).to eq('get_todays_date')
    end

    it 'has empty properties for get_todays_date schema' do
      date_schema = JSON.parse(date_tool.schema)
      expect(date_schema['parameters']['properties']).to be_empty
    end

    it 'has empty required for get_todays_date schema' do
      date_schema = JSON.parse(date_tool.schema)
      expect(date_schema['parameters']['required']).to be_empty
    end

    it 'has correct name for add_numbers schema' do
      add_schema = JSON.parse(add_tool.schema)
      expect(add_schema['name']).to eq('add_numbers')
    end

    it 'has x property for add_numbers schema' do
      add_schema = JSON.parse(add_tool.schema)
      expect(add_schema['parameters']['properties']).to have_key('x')
    end

    it 'has y property for add_numbers schema' do
      add_schema = JSON.parse(add_tool.schema)
      expect(add_schema['parameters']['properties']).to have_key('y')
    end

    it 'has x and y in required for add_numbers schema' do
      add_schema = JSON.parse(add_tool.schema)
      expect(add_schema['parameters']['required']).to include('x', 'y')
    end

    it 'has correct name for calculator schema' do
      calc_schema = JSON.parse(calculator_tool.schema)
      expect(calc_schema['name']).to eq('calculator')
    end

    it 'has operation property for calculator schema' do
      calc_schema = JSON.parse(calculator_tool.schema)
      expect(calc_schema['parameters']['properties']).to have_key('operation')
    end

    it 'has num1 property for calculator schema' do
      calc_schema = JSON.parse(calculator_tool.schema)
      expect(calc_schema['parameters']['properties']).to have_key('num1')
    end

    it 'has num2 property for calculator schema' do
      calc_schema = JSON.parse(calculator_tool.schema)
      expect(calc_schema['parameters']['properties']).to have_key('num2')
    end

    it 'has operation in required for calculator schema' do
      calc_schema = JSON.parse(calculator_tool.schema)
      expect(calc_schema['parameters']['required']).to include('operation')
    end

    it 'has num1 in required for calculator schema' do
      calc_schema = JSON.parse(calculator_tool.schema)
      expect(calc_schema['parameters']['required']).to include('num1')
    end

    it 'has num2 in required for calculator schema' do
      calc_schema = JSON.parse(calculator_tool.schema)
      expect(calc_schema['parameters']['required']).to include('num2')
    end

    it 'does not contain escaped newlines from pretty printing' do
      tools.each do |tool|
        schema_json = tool.schema
        expect(schema_json).not_to include('\\n')
      end
    end

    it 'does not contain literal backslash-n sequences' do
      tools.each do |tool|
        schema_json = tool.schema
        expect(schema_json).not_to include('\n')
      end
    end

    it 'produces proper JSON hash structure without serialization artifacts' do
      tools.each do |tool|
        schema_json = tool.schema
        parsed = JSON.parse(schema_json)
        expect(parsed).to be_a(Hash)
      end
    end

    it 'maintains identity when re-serialized without artifacts' do
      tools.each do |tool|
        schema_json = tool.schema
        parsed = JSON.parse(schema_json)
        reserialized = JSON.generate(parsed)
        expect(reserialized).to eq(schema_json)
      end
    end

    it 'does not contain double backslashes from nested serialization' do
      tools.each do |tool|
        schema_json = tool.schema
        expect(schema_json).not_to match(/\\\\/)
      end
    end
  end
end
