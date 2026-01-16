# frozen_string_literal: true

require 'spec_helper'
require 'dspy/tools/toolset'

RSpec.describe DSPy::Tools::Toolset do
  describe "DSL methods" do
    let(:test_toolset_class) do
      Class.new(DSPy::Tools::Toolset) do
        toolset_name "test"
        
        tool :action_one, description: "First action"
        tool :action_two, tool_name: "custom_action", description: "Second action"
        
        def action_one(input:)
          "Action one: #{input}"
        end
        
        def action_two(value:, optional: nil)
          "Action two: #{value}, #{optional}"
        end
      end
    end

    it "sets toolset name" do
      expect(test_toolset_class.toolset_name).to eq("test")
    end

    it "tracks exposed tools" do
      expect(test_toolset_class.exposed_tools).to include(
        action_one: { tool_name: "test_action_one", description: "First action" },
        action_two: { tool_name: "custom_action", description: "Second action" }
      )
    end

    it "generates tool instances with to_tools" do
      tools = test_toolset_class.to_tools
      expect(tools).to be_an(Array)
      expect(tools.length).to eq(2)
      
      expect(tools[0].name).to eq("test_action_one")
      expect(tools[0].description).to eq("First action")
      
      expect(tools[1].name).to eq("custom_action")
      expect(tools[1].description).to eq("Second action")
    end

    it "defaults toolset name from class name" do
      unnamed_class = Class.new(DSPy::Tools::Toolset)
      stub_const("MyCustomToolset", unnamed_class)
      expect(unnamed_class.toolset_name).to eq("mycustom")
    end
  end
end