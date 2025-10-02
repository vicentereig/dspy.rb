# frozen_string_literal: true

require 'spec_helper'
require 'dspy/re_act'
require 'dspy/tools/github_cli_toolset'

class TestSignature < DSPy::Signature
  description "Test signature for ReAct field descriptions"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

RSpec.describe 'ReAct Field Descriptions', type: :unit do
  let(:tools) { DSPy::Tools::GitHubCLIToolset.to_tools.first(3) }
  let(:agent) { DSPy::ReAct.new(TestSignature, tools: tools) }
  
  describe 'thought signature field descriptions' do
    let(:thought_generator) { agent.instance_variable_get(:@thought_generator) }
    let(:thought_signature) { thought_generator.signature_class }
    let(:output_schema) { thought_signature.output_json_schema }
    
    it 'includes description for thought field' do
      thought_description = output_schema.dig(:properties, :thought, :description)
      expect(thought_description).to be_a(String)
      expect(thought_description).to include('Reasoning')
    end
    
    it 'includes description for action field with tool instruction' do
      action_description = output_schema.dig(:properties, :action, :description)
      expect(action_description).to be_a(String)
      expect(action_description).to include('MUST be one of the tool names')
      expect(action_description).to include('finish')
    end
    
    it 'includes description for action_input field' do
      action_input_description = output_schema.dig(:properties, :action_input, :description)
      expect(action_input_description).to be_a(String)
      expect(action_input_description).to include('JSON object')
      expect(action_input_description).to include('finish')
    end
    
    it 'includes description for input_context field' do
      input_schema = thought_signature.input_json_schema
      input_context_description = input_schema.dig(:properties, :input_context, :description)
      expect(input_context_description).to be_a(String)
      expect(input_context_description).to include('Serialized representation')
    end
    
    it 'includes description for history field' do
      input_schema = thought_signature.input_json_schema
      history_description = input_schema.dig(:properties, :history, :description)
      expect(history_description).to be_a(String)
      expect(history_description).to include('Previous thoughts and actions')
    end
    
    it 'includes description for available_tools field' do
      input_schema = thought_signature.input_json_schema
      tools_description = input_schema.dig(:properties, :available_tools, :description)
      expect(tools_description).to be_a(String)
      expect(tools_description).to include('Array of available tools')
    end
  end
  
  describe 'observation signature field descriptions' do
    let(:observation_processor) { agent.instance_variable_get(:@observation_processor) }
    let(:observation_signature) { observation_processor.signature_class }
    let(:output_schema) { observation_signature.output_json_schema }
    
    it 'includes description for interpretation field' do
      interpretation_description = output_schema.dig(:properties, :interpretation, :description)
      expect(interpretation_description).to be_a(String)
      expect(interpretation_description).to include('Interpretation')
    end
    
    it 'includes description for next_step field' do
      next_step_description = output_schema.dig(:properties, :next_step, :description)
      expect(next_step_description).to be_a(String)
      expect(next_step_description).to include('What to do next')
      expect(next_step_description).to include('Continue')
      expect(next_step_description).to include('Finish')
    end
  end

  describe 'AvailableTool struct' do
    let(:tool_name) { 'github_list_prs' }
    let(:tool_description) { 'List GitHub pull requests with optional filters' }
    let(:tool_schema) { { type: 'object', properties: { repo: { type: 'string' } } } }
    
    it 'creates AvailableTool instances from tool data' do
      # This test will fail until we implement AvailableTool
      available_tool = DSPy::ReAct::AvailableTool.new(
        name: tool_name,
        description: tool_description,
        schema: tool_schema
      )
      
      expect(available_tool.name).to eq(tool_name)
      expect(available_tool.description).to eq(tool_description)
      expect(available_tool.schema).to eq(tool_schema)
    end

    it 'uses AvailableTool structs instead of raw hashes in available_tools field' do
      input_schema = agent.instance_variable_get(:@thought_generator).signature_class.input_json_schema
      available_tools_property = input_schema.dig(:properties, :available_tools)
      
      # Should have proper AvailableTool schema, not just generic hash
      expect(available_tools_property[:items][:properties]).to have_key(:name)
      expect(available_tools_property[:items][:properties]).to have_key(:description)
      expect(available_tools_property[:items][:properties]).to have_key(:schema)
      expect(available_tools_property[:items][:description]).to include('AvailableTool')
    end
  end

  describe 'Dynamic ActionEnum for tools' do
    it 'creates ActionEnum class with tool names and finish' do
      # This test will fail until we implement dynamic ActionEnum generation
      action_enum_class = agent.instance_variable_get(:@action_enum_class)
      
      expect(action_enum_class).to be < T::Enum
      expect(action_enum_class.values.map(&:serialize)).to include('finish')
      expect(action_enum_class.values.map(&:serialize)).to include('github_get_issue')
      expect(action_enum_class.values.map(&:serialize)).to include('github_list_issues')
    end

    it 'uses ActionEnum instead of String type for action field' do
      output_schema = agent.instance_variable_get(:@thought_generator).signature_class.output_json_schema
      action_property = output_schema.dig(:properties, :action)
      
      # Should have enum constraint with actual tool names
      expect(action_property).to have_key(:enum)
      expect(action_property[:enum]).to include('finish')
      expect(action_property[:enum]).to include('github_get_issue')
      expect(action_property[:enum]).to include('github_list_issues')
    end
  end
end