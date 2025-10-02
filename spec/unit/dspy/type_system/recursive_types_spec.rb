# typed: strict
# frozen_string_literal: true

require 'spec_helper'

# Define test classes at the top level so they can reference themselves
class MindMapNode < T::Struct
  const :id, String
  const :topic, String
  const :summary, String
  const :chunk_ids, T::Array[T.any(String, Integer)]
  const :children, T.nilable(T::Array[MindMapNode])
end

class TreeNode < T::Struct
  const :value, String
  const :left, T.nilable(TreeNode)
  const :right, T.nilable(TreeNode)
end

RSpec.describe "Recursive Type Support" do
  describe "MindMapNode example" do
    it "handles recursive types without infinite loops" do
      # This should not cause a stack overflow or infinite loop
      expect {
        DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(MindMapNode)
      }.not_to raise_error
    end

    it "generates proper JSON schema for recursive types" do
      schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(MindMapNode)
      
      expect(schema[:type]).to eq("object")
      expect(schema[:properties]).to be_a(Hash)
      expect(schema[:properties][:children]).to be_a(Hash)
      
      # The children field should be present and properly typed as nullable array
      children_schema = schema[:properties][:children]
      expect(children_schema[:type]).to eq(["array", "null"])
      
      # For recursive types, we expect a reference or simplified schema to avoid infinite recursion
      expect(children_schema[:items]).to be_a(Hash)
      expect(children_schema[:items]).to have_key("$ref").or have_key(:type)
    end
  end

  describe "TreeNode example" do
    it "handles self-referencing optional children" do
      expect {
        DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(TreeNode)
      }.not_to raise_error
    end

    it "generates schema with proper nullable references" do
      schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(TreeNode)
      
      # For T.nilable references to the same type, we expect anyOf with reference and null
      left_schema = schema[:properties][:left]
      right_schema = schema[:properties][:right]
      
      expect(left_schema).to have_key(:anyOf)
      expect(right_schema).to have_key(:anyOf)
      
      # Should have [reference, null] in anyOf
      expect(left_schema[:anyOf]).to be_an(Array)
      expect(left_schema[:anyOf].length).to eq(2)
      expect(left_schema[:anyOf]).to include({ type: "null" })
      expect(left_schema[:anyOf][0]).to have_key("$ref")
      
      expect(right_schema[:anyOf]).to be_an(Array)
      expect(right_schema[:anyOf].length).to eq(2)
      expect(right_schema[:anyOf]).to include({ type: "null" })
      expect(right_schema[:anyOf][0]).to have_key("$ref")
    end
  end
end