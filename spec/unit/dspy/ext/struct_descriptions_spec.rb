# frozen_string_literal: true

require 'spec_helper'

# Test structs defined at top level for spec
module StructDescriptionsSpec
  class TestNode < T::Struct
    const :node_type, String, description: 'The type of node (heading, paragraph, etc.)'
    const :text, String, default: "", description: 'Text content of the node'
    const :level, Integer, default: 0
    const :children, T::Array[T.untyped], default: []
  end

  class PlainStruct < T::Struct
    const :name, String
    const :value, Integer
  end
end

RSpec.describe DSPy::Ext::StructDescriptions do
  describe '.field_descriptions' do
    it 'stores field descriptions for const with description:' do
      expect(StructDescriptionsSpec::TestNode.field_descriptions[:node_type]).to eq('The type of node (heading, paragraph, etc.)')
      expect(StructDescriptionsSpec::TestNode.field_descriptions[:text]).to eq('Text content of the node')
    end

    it 'does not store descriptions for fields without description:' do
      expect(StructDescriptionsSpec::TestNode.field_descriptions[:level]).to be_nil
      expect(StructDescriptionsSpec::TestNode.field_descriptions[:children]).to be_nil
    end

    it 'returns empty hash for structs without descriptions' do
      expect(StructDescriptionsSpec::PlainStruct.field_descriptions).to eq({})
    end
  end

  describe 'T::Struct compatibility' do
    it 'preserves normal const behavior' do
      node = StructDescriptionsSpec::TestNode.new(node_type: 'heading', text: 'Hello', level: 1, children: [])

      expect(node.node_type).to eq('heading')
      expect(node.text).to eq('Hello')
      expect(node.level).to eq(1)
      expect(node.children).to eq([])
    end

    it 'preserves default values' do
      node = StructDescriptionsSpec::TestNode.new(node_type: 'paragraph')

      expect(node.text).to eq("")
      expect(node.level).to eq(0)
      expect(node.children).to eq([])
    end

    it 'preserves props metadata' do
      props = StructDescriptionsSpec::TestNode.props

      expect(props[:node_type]).to be_a(Hash)
      expect(props[:text]).to be_a(Hash)
      expect(props[:level]).to be_a(Hash)
    end
  end

  describe 'JSON schema generation' do
    it 'includes field descriptions in generated schema' do
      schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(StructDescriptionsSpec::TestNode)

      expect(schema[:properties][:node_type][:description]).to eq('The type of node (heading, paragraph, etc.)')
      expect(schema[:properties][:text][:description]).to eq('Text content of the node')
    end

    it 'does not add description for fields without description:' do
      schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(StructDescriptionsSpec::TestNode)

      # level has no description, so shouldn't have :description key
      expect(schema[:properties][:level]).not_to have_key(:description)
    end

    it 'works with structs without any descriptions' do
      schema = DSPy::TypeSystem::SorbetJsonSchema.generate_struct_schema(StructDescriptionsSpec::PlainStruct)

      expect(schema[:properties][:name]).not_to have_key(:description)
      expect(schema[:properties][:value]).not_to have_key(:description)
    end
  end
end
