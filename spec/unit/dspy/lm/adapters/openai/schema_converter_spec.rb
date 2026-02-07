# frozen_string_literal: true

require 'spec_helper'
require 'dspy/openai/lm/schema_converter'

RSpec.describe DSPy::OpenAI::LM::SchemaConverter do
  describe '.to_openai_format' do
    let(:signature_class) do
      Class.new(DSPy::Signature) do
        description "Answer a question"
        
        input do
          const :question, String, description: "User's question"
        end
        
        output do
          const :answer, String, description: "Generated answer"
        end
      end
    end
    
    it 'converts DSPy signature to OpenAI structured output format' do
      result = described_class.to_openai_format(signature_class)
      
      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("json_schema")
      expect(result[:json_schema]).to be_a(Hash)
      expect(result[:json_schema][:strict]).to eq(true)
      expect(result[:json_schema][:schema]).to be_a(Hash)
      expect(result[:json_schema][:schema][:type]).to eq("object")
      expect(result[:json_schema][:schema][:additionalProperties]).to eq(false)
    end
    
    it 'generates a schema name when not provided' do
      result = described_class.to_openai_format(signature_class)
      
      expect(result[:json_schema][:name]).to match(/^dspy_output_\d+$/)
    end
    
    it 'uses provided schema name when given' do
      result = described_class.to_openai_format(signature_class, name: "custom_schema")
      
      expect(result[:json_schema][:name]).to eq("custom_schema")
    end
    
    it 'removes $schema field from DSPy schema' do
      result = described_class.to_openai_format(signature_class)
      
      expect(result[:json_schema][:schema]).not_to have_key(:$schema)
    end
    
    it 'respects strict parameter' do
      result_strict = described_class.to_openai_format(signature_class, strict: true)
      result_non_strict = described_class.to_openai_format(signature_class, strict: false)
      
      expect(result_strict[:json_schema][:strict]).to eq(true)
      expect(result_strict[:json_schema][:schema][:additionalProperties]).to eq(false)
      
      expect(result_non_strict[:json_schema][:strict]).to eq(false)
      expect(result_non_strict[:json_schema][:schema]).not_to have_key(:additionalProperties)
    end
  end
  
  describe '.supports_structured_outputs?' do
    it 'returns true for supported models' do
      expect(described_class.supports_structured_outputs?("openai/gpt-4o")).to eq(true)
      expect(described_class.supports_structured_outputs?("openai/gpt-4o-mini")).to eq(true)
      expect(described_class.supports_structured_outputs?("openai/gpt-4-turbo")).to eq(true)
      expect(described_class.supports_structured_outputs?("openai/gpt-4o-2024-08-06")).to eq(true)
    end
    
    it 'returns false for unsupported models' do
      expect(described_class.supports_structured_outputs?("openai/gpt-3.5-turbo")).to eq(false)
      expect(described_class.supports_structured_outputs?("openai/text-davinci-003")).to eq(false)
    end
    
    it 'handles models without provider prefix' do
      expect(described_class.supports_structured_outputs?("gpt-4o")).to eq(true)
      expect(described_class.supports_structured_outputs?("gpt-3.5-turbo")).to eq(false)
    end
  end
  
  describe '.validate_compatibility' do
    it 'returns empty array for simple schemas' do
      signature_class = Class.new(DSPy::Signature) do
        output do
          const :result, String, description: "Result"
        end
      end
      
      schema = signature_class.output_json_schema
      issues = described_class.validate_compatibility(schema)
      
      expect(issues).to be_empty
    end
    
    it 'detects deeply nested schemas' do
      # Create a deeply nested schema (6 levels)
      schema = {
        type: "object",
        properties: {
          level1: {
            type: "object",
            properties: {
              level2: {
                type: "object",
                properties: {
                  level3: {
                    type: "object",
                    properties: {
                      level4: {
                        type: "object",
                        properties: {
                          level5: {
                            type: "object",
                            properties: {
                              level6: { type: "string" }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      
      issues = described_class.validate_compatibility(schema)
      
      expect(issues).to include("Schema depth (6) exceeds recommended limit of 5 levels")
    end
    
    it 'detects pattern properties' do
      schema = {
        type: "object",
        patternProperties: {
          "^[a-z]+$" => { type: "string" }
        }
      }
      
      issues = described_class.validate_compatibility(schema)
      
      expect(issues).to include("Pattern properties are not supported in OpenAI structured outputs")
    end
    
    it 'detects conditional schemas' do
      schema = {
        type: "object",
        if: { properties: { foo: { const: "bar" } } },
        then: { required: ["baz"] }
      }
      
      issues = described_class.validate_compatibility(schema)
      
      expect(issues).to include("Conditional schemas (if/then/else) are not supported")
    end
  end
  
  describe '.convert_oneof_to_anyof_if_safe' do
    describe 'with discriminated unions' do
      let(:discriminated_union_schema) do
        {
          oneOf: [
            {
              type: "object",
              properties: {
                _type: { type: "string", const: "SpawnTask" },
                description: { type: "string" },
                priority: { type: "string" }
              },
              required: ["_type", "description", "priority"],
              additionalProperties: false
            },
            {
              type: "object",
              properties: {
                _type: { type: "string", const: "CompleteTask" },
                task_id: { type: "string" },
                result: { type: "string" }
              },
              required: ["_type", "task_id", "result"],
              additionalProperties: false
            }
          ]
        }
      end
      
      it 'converts oneOf to anyOf when all schemas have discriminators' do
        result = described_class.convert_oneof_to_anyof_if_safe(discriminated_union_schema)
        
        expect(result).not_to have_key(:oneOf)
        expect(result).to have_key(:anyOf)
        expect(result[:anyOf]).to be_an(Array)
        expect(result[:anyOf].length).to eq(2)
        
        # Verify the schemas are preserved
        spawn_schema = result[:anyOf].find { |s| s[:properties][:_type][:const] == "SpawnTask" }
        complete_schema = result[:anyOf].find { |s| s[:properties][:_type][:const] == "CompleteTask" }
        
        expect(spawn_schema).not_to be_nil
        expect(complete_schema).not_to be_nil
        
        expect(spawn_schema[:properties][:description]).to eq({ type: "string" })
        expect(complete_schema[:properties][:task_id]).to eq({ type: "string" })
      end
      
      it 'recursively converts nested oneOf schemas' do
        nested_schema = {
          type: "object",
          properties: {
            action: discriminated_union_schema,
            metadata: { type: "string" }
          }
        }
        
        result = described_class.convert_oneof_to_anyof_if_safe(nested_schema)
        
        expect(result[:properties][:action]).to have_key(:anyOf)
        expect(result[:properties][:action]).not_to have_key(:oneOf)
      end
      
      it 'converts oneOf in array items' do
        array_schema = {
          type: "array",
          items: discriminated_union_schema
        }
        
        result = described_class.convert_oneof_to_anyof_if_safe(array_schema)
        
        expect(result[:items]).to have_key(:anyOf)
        expect(result[:items]).not_to have_key(:oneOf)
      end
    end
    
    describe 'with non-discriminated unions' do
      let(:non_discriminated_union_schema) do
        {
          oneOf: [
            {
              type: "object",
              properties: {
                name: { type: "string" },
                value: { type: "string" }
              },
              required: ["name", "value"]
            },
            {
              type: "object",
              properties: {
                id: { type: "string" },
                data: { type: "string" }
              },
              required: ["id", "data"]
            }
          ]
        }
      end
      
      it 'raises error for oneOf without discriminators' do
        expect {
          described_class.convert_oneof_to_anyof_if_safe(non_discriminated_union_schema)
        }.to raise_error(DSPy::UnsupportedSchemaError) do |error|
          expect(error.message).to include("oneOf schemas without discriminator fields")
          expect(error.message).to include("enhanced_prompting strategy")
        end
      end
    end
    
    describe 'with mixed discriminated/non-discriminated schemas' do
      let(:mixed_schema) do
        {
          oneOf: [
            {
              type: "object",
              properties: {
                _type: { type: "string", const: "TypeA" },
                data: { type: "string" }
              },
              required: ["_type", "data"]
            },
            {
              type: "object",
              properties: {
                name: { type: "string" },  # No _type field
                value: { type: "string" }
              },
              required: ["name", "value"]
            }
          ]
        }
      end
      
      it 'raises error when not all schemas have discriminators' do
        expect {
          described_class.convert_oneof_to_anyof_if_safe(mixed_schema)
        }.to raise_error(DSPy::UnsupportedSchemaError)
      end
    end
    
    describe 'with non-oneOf schemas' do
      let(:regular_schema) do
        {
          type: "object",
          properties: {
            name: { type: "string" },
            age: { type: "integer" }
          },
          required: ["name", "age"]
        }
      end
      
      it 'returns schema unchanged when no oneOf present' do
        result = described_class.convert_oneof_to_anyof_if_safe(regular_schema)
        
        expect(result).to eq(regular_schema)
      end
    end
  end
  
  describe 'recursive types with $defs' do
    # Define recursive type at module level for proper self-reference
    before(:all) do
      # Create recursive struct class
      Object.send(:remove_const, :RecursiveTreeNode) if defined?(RecursiveTreeNode)
      eval <<-RUBY
        class RecursiveTreeNode < T::Struct
          const :value, String
          const :children, T.nilable(T::Array[RecursiveTreeNode])
        end
      RUBY
    end

    let(:recursive_signature_class) do
      Class.new(DSPy::Signature) do
        description "Process a tree structure"

        input do
          const :prompt, String, description: "Instructions"
        end

        output do
          const :tree, RecursiveTreeNode, description: "A recursive tree structure"
        end
      end
    end

    it 'uses $defs format instead of definitions for recursive references' do
      result = described_class.to_openai_format(recursive_signature_class)
      schema = result[:json_schema][:schema]

      # The schema should have a $defs section at the root
      expect(schema).to have_key(:"$defs")
      expect(schema[:"$defs"]).to have_key(:RecursiveTreeNode)

      # Any $ref should use #/$defs/ format, not #/definitions/
      schema_json = JSON.generate(schema)
      expect(schema_json).not_to include('#/definitions/')
      expect(schema_json).to include('#/$defs/') if schema_json.include?('$ref')
    end

    it 'generates valid schema with recursive $refs resolved' do
      result = described_class.to_openai_format(recursive_signature_class)
      schema = result[:json_schema][:schema]

      # The tree property should reference the $defs
      tree_schema = schema[:properties][:tree]

      # For recursive types, we expect either:
      # 1. Direct $ref to #/$defs/RecursiveTreeNode, or
      # 2. Object with children containing $ref
      if tree_schema[:"$ref"]
        expect(tree_schema[:"$ref"]).to eq("#/$defs/RecursiveTreeNode")
      else
        # Should be an object with children that have $ref
        expect(tree_schema[:type]).to eq("object")
        children_schema = tree_schema[:properties][:children]
        expect(children_schema).to be_a(Hash)
        # Children array items should reference the type
        if children_schema[:items] && children_schema[:items][:"$ref"]
          expect(children_schema[:items][:"$ref"]).to eq("#/$defs/RecursiveTreeNode")
        end
      end
    end
  end

  describe '.all_have_discriminators?' do
    it 'returns true when all schemas have const properties' do
      schemas = [
        {
          type: "object",
          properties: {
            _type: { type: "string", const: "TypeA" },
            data: { type: "string" }
          }
        },
        {
          type: "object",
          properties: {
            _type: { type: "string", const: "TypeB" },
            value: { type: "integer" }
          }
        }
      ]
      
      expect(described_class.all_have_discriminators?(schemas)).to eq(true)
    end
    
    it 'returns false when some schemas lack const properties' do
      schemas = [
        {
          type: "object",
          properties: {
            _type: { type: "string", const: "TypeA" },
            data: { type: "string" }
          }
        },
        {
          type: "object",
          properties: {
            name: { type: "string" },  # No const field
            value: { type: "integer" }
          }
        }
      ]
      
      expect(described_class.all_have_discriminators?(schemas)).to eq(false)
    end
    
    it 'returns false for schemas without properties' do
      schemas = [
        { type: "string" },
        { type: "integer" }
      ]
      
      expect(described_class.all_have_discriminators?(schemas)).to eq(false)
    end
    
    it 'handles different discriminator field names' do
      schemas = [
        {
          type: "object",
          properties: {
            type: { type: "string", const: "user" },
            name: { type: "string" }
          }
        },
        {
          type: "object",
          properties: {
            kind: { type: "string", const: "admin" },
            permissions: { type: "array" }
          }
        }
      ]
      
      expect(described_class.all_have_discriminators?(schemas)).to eq(true)
    end
  end
end
