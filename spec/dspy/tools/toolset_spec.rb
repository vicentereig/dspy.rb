# frozen_string_literal: true

require 'spec_helper'
require 'dspy/tools/toolset'
require 'dspy/tools/memory_toolset'

RSpec.describe DSPy::Tools::Toolset do
  describe "DSL methods" do
    let(:test_toolset_class) do
      Class.new(DSPy::Tools::Toolset) do
        toolset_name "test"
        
        expose_tool :action_one, description: "First action"
        expose_tool :action_two, tool_name: "custom_action", description: "Second action"
        
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

  describe DSPy::Tools::MemoryToolset do
    let(:memory_toolset) { described_class.new }
    let(:tools) { described_class.to_tools }

    describe "tool generation" do
      it "generates correct number of tools" do
        expect(tools.length).to eq(9)
      end

      it "generates tools with correct names" do
        tool_names = tools.map(&:name)
        expect(tool_names).to include(
          "memory_store",
          "memory_retrieve",
          "memory_search",
          "memory_list",  # custom name
          "memory_update",
          "memory_delete",
          "memory_clear",
          "memory_count",
          "memory_get_metadata"
        )
      end

      it "generates proper JSON schemas" do
        store_tool = tools.find { |t| t.name == "memory_store" }
        schema = JSON.parse(store_tool.schema)
        
        expect(schema["name"]).to eq("memory_store")
        expect(schema["description"]).to eq("Store a key-value pair in memory with optional tags")
        expect(schema["parameters"]["properties"]).to include("key", "value", "tags")
        expect(schema["parameters"]["required"]).to contain_exactly("key", "value")
      end
    end

    describe "memory operations" do
      it "stores and retrieves values" do
        result = memory_toolset.store(key: "test_key", value: "test_value")
        expect(result).to include("successfully")
        
        value = memory_toolset.retrieve(key: "test_key")
        expect(value).to eq("test_value")
      end

      it "supports tags" do
        memory_toolset.store(key: "tagged", value: "value", tags: ["important", "user"])
        metadata = memory_toolset.get_metadata(key: "tagged")
        expect(metadata[:tags]).to eq(["important", "user"])
      end

      it "searches by pattern" do
        memory_toolset.store(key: "user_name", value: "John Doe")
        memory_toolset.store(key: "user_email", value: "john@example.com")
        memory_toolset.store(key: "config_theme", value: "dark")
        
        results = memory_toolset.search(pattern: "user", in_keys: true, in_values: false)
        expect(results.length).to eq(2)
        expect(results.map { |r| r[:key] }).to contain_exactly("user_name", "user_email")
      end

      it "updates existing memories" do
        memory_toolset.store(key: "mutable", value: "original")
        result = memory_toolset.update(key: "mutable", value: "updated")
        expect(result).to include("successfully")
        
        value = memory_toolset.retrieve(key: "mutable")
        expect(value).to eq("updated")
      end

      it "tracks access metadata" do
        memory_toolset.store(key: "tracked", value: "data")
        memory_toolset.retrieve(key: "tracked")
        memory_toolset.retrieve(key: "tracked")
        
        metadata = memory_toolset.get_metadata(key: "tracked")
        expect(metadata[:access_count]).to eq(2)
        expect(metadata[:last_accessed_at]).to be_a(Time)
      end
    end

    describe "tool proxy dynamic_call" do
      let(:store_tool) { tools.find { |t| t.name == "memory_store" } }
      let(:search_tool) { tools.find { |t| t.name == "memory_search" } }

      it "handles JSON string input" do
        result = store_tool.dynamic_call('{"key": "json_test", "value": "json_value"}')
        expect(result).to include("successfully")
      end

      it "handles Hash input" do
        result = store_tool.dynamic_call({ "key" => "hash_test", "value" => "hash_value" })
        expect(result).to include("successfully")
      end

      it "validates required parameters" do
        result = store_tool.dynamic_call('{"key": "missing_value"}')
        expect(result).to include("Error: Missing required parameter: value")
      end

      it "handles optional parameters" do
        result = search_tool.dynamic_call({
          "pattern" => "test",
          "in_keys" => false
        })
        expect(result).to be_an(Array)
      end
    end
  end

  describe "integration with ReAct agent" do
    it "can be used with DSPy::ReAct" do
      memory_tools = DSPy::Tools::MemoryToolset.to_tools
      
      # Simulate what ReAct would do
      tool_schemas = memory_tools.map { |tool| JSON.parse(tool.schema) }
      expect(tool_schemas).to all(include("name", "description", "parameters"))
      
      # Simulate tool execution
      store_tool = memory_tools.find { |t| t.name == "memory_store" }
      result = store_tool.dynamic_call({ "key" => "react_test", "value" => "react_value" })
      expect(result).to include("successfully")
    end
  end
end