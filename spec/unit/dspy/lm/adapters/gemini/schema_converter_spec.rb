# frozen_string_literal: true

require 'spec_helper'
require 'dspy/gemini/lm/schema_converter'

RSpec.describe DSPy::Gemini::LM::SchemaConverter do
  describe '.to_gemini_format' do
    let(:signature_class) do
      Class.new(DSPy::Signature) do
        description "Answer a question"
        
        input do
          const :question, String, description: "User's question"
        end
        
        output do
          const :answer, String, description: "Generated answer"
          const :confidence, Float, description: "Confidence score"
        end
      end
    end
    
    it 'converts DSPy signature to Gemini format' do
      result = described_class.to_gemini_format(signature_class)
      
      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("object")
      expect(result[:properties]).to be_a(Hash)
      expect(result[:properties][:answer]).to eq({ type: "string", description: "Generated answer" })
      expect(result[:properties][:confidence]).to eq({ type: "number", description: "Confidence score" })
      expect(result[:required]).to contain_exactly("answer", "confidence")
    end
    
    it 'handles complex types correctly' do
      complex_signature = Class.new(DSPy::Signature) do
        output do
          const :items, T::Array[String], description: "List of items"
          const :count, Integer, description: "Total count"
          const :enabled, T::Boolean, description: "Is enabled"
        end
      end
      
      result = described_class.to_gemini_format(complex_signature)
      
      # Test that the schema has the correct structure
      expect(result[:type]).to eq("object")
      expect(result[:properties]).to include(:items, :count, :enabled)
      expect(result[:properties][:items][:type]).to eq("array")
      expect(result[:properties][:items][:items][:type]).to eq("string")
      expect(result[:properties][:count][:type]).to eq("integer")
      expect(result[:properties][:enabled][:type]).to eq("boolean")
      expect(result[:required]).to contain_exactly("items", "count", "enabled")
    end
    
    it 'handles T::Struct types' do
      # Create a named struct class
      stub_const('ItemStruct', Class.new(T::Struct) do
        const :name, String
        const :value, Integer
      end)
      
      struct_signature = Class.new(DSPy::Signature) do
        output do
          const :item, ItemStruct, description: "An item"
        end
      end
      
      result = described_class.to_gemini_format(struct_signature)
      
      # Test the overall structure
      expect(result[:type]).to eq("object")
      expect(result[:properties]).to include(:item)
      
      # Test the nested struct properties
      item_props = result[:properties][:item]
      expect(item_props[:type]).to eq("object")
      expect(item_props[:properties]).to include(:name, :value, :_type)
      expect(item_props[:properties][:name][:type]).to eq("string")
      expect(item_props[:properties][:value][:type]).to eq("integer")
      expect(item_props[:properties][:_type][:type]).to eq("string")
      expect(item_props[:required]).to contain_exactly("name", "value", "_type")
    end
    
    it 'handles T::Enum types' do
      # Define a proper T::Enum class
      module TestModule
        class StatusEnum < T::Enum
          enums do
            Active = new('active')
            Inactive = new('inactive')
          end
        end
      end
      
      enum_signature = Class.new(DSPy::Signature) do
        output do
          const :status, TestModule::StatusEnum, description: "Status"
        end
      end
      
      result = described_class.to_gemini_format(enum_signature)
      
      # Test the overall structure
      expect(result[:type]).to eq("object")
      expect(result[:properties]).to include(:status)
      
      # T::Enum should be converted to string with enum values
      status_props = result[:properties][:status]
      expect(status_props[:type]).to eq("string")
      expect(status_props[:enum]).to contain_exactly("active", "inactive")
    end
    
  end
  
  describe 'nullable JSON Schema conversion' do
    it 'preserves nullable arrays, scalars and array item types' do
      signature = Class.new(DSPy::Signature) do
        output do
          const :choices, T.nilable(T::Array[String]), default: nil
          const :hint, T.nilable(String), default: nil
          const :count, T.nilable(Integer), default: nil
          const :score, T.nilable(Float), default: nil
          const :enabled, T.nilable(T::Boolean), default: nil
          const :items, T::Array[T.nilable(String)]
        end
      end

      properties = described_class.to_gemini_format(signature).fetch(:properties)

      expect(properties[:choices]).to eq(type: ['array', 'null'], items: { type: 'string' })
      expect(properties[:hint]).to eq(type: ['string', 'null'])
      expect(properties[:count]).to eq(type: ['integer', 'null'])
      expect(properties[:score]).to eq(type: ['number', 'null'])
      expect(properties[:enabled]).to eq(type: ['boolean', 'null'])
      expect(properties.dig(:items, :items)).to eq(type: ['string', 'null'])
    end

    it 'preserves nested nullable fields, descriptions and object constraints' do
      stub_const('NullableChoiceCheck', Class.new(T::Struct) do
        const :prompt, String, description: 'Ask the learner a question.'
        const :choices, T.nilable(T::Array[String]), default: nil,
          description: 'Three or four answer options, or null.'
      end)
      signature = Class.new(DSPy::Signature) do
        output do
          const :checks, T::Array[NullableChoiceCheck], description: 'Ordered checks.'
          const :optional_check, T.nilable(NullableChoiceCheck), default: nil
        end
      end

      result = described_class.to_gemini_format(signature)
      check = result.dig(:properties, :checks, :items)
      expect(result.dig(:properties, :checks, :description)).to eq('Ordered checks.')
      expect(check.dig(:properties, :choices)).to eq(
        type: ['array', 'null'], items: { type: 'string' },
        description: 'Three or four answer options, or null.'
      )
      expect(check.dig(:properties, :prompt, :description)).to eq('Ask the learner a question.')
      expect(check[:required]).to contain_exactly('_type', 'prompt')
      expect(check[:additionalProperties]).to be(false)
      expect(check.dig(:properties, :_type)).to eq(type: 'string', enum: ['NullableChoiceCheck'])
      optional_check = result.dig(:properties, :optional_check)
      expect(optional_check[:type]).to eq(['object', 'null'])
      expect(optional_check[:properties]).to eq(check[:properties])
      expect(optional_check[:additionalProperties]).to be(false)
    end

    it 'keeps null branches in unions and schemas for hash values' do
      signature = Class.new(DSPy::Signature) do
        output do
          const :value, T.any(String, Integer, NilClass)
          const :labels, T::Hash[String, T.nilable(String)]
        end
      end

      result = described_class.to_gemini_format(signature)
      expect(result.dig(:properties, :value, :anyOf)).to contain_exactly(
        { type: 'string' }, { type: 'integer' }, { type: 'null' }
      )
      expect(result.dig(:properties, :labels, :additionalProperties)).to eq(type: ['string', 'null'])
    end

    it 'converts constants inside definitions without changing the source schema' do
      source = {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        type: 'object', additionalProperties: false, required: ['item'],
        properties: { item: { '$ref': '#/$defs/Item' } },
        '$defs': {
          Item: {
            type: 'object', additionalProperties: false,
            properties: { enabled: { type: 'boolean', const: false } }
          }
        }
      }
      original = Marshal.load(Marshal.dump(source))
      signature = Class.new(DSPy::Signature)
      allow(signature).to receive(:output_json_schema).and_return(source)

      result = described_class.to_gemini_format(signature)
      expect(result).not_to have_key(:'$schema')
      expect(result[:additionalProperties]).to be(false)
      expect(result.dig(:properties, :item)).to eq('$ref': '#/$defs/Item')
      expect(result.dig(:'$defs', :Item, :properties, :enabled)).to eq(type: 'boolean', enum: [false])
      expect(source).to eq(original)
    end
  end

  describe '.supports_structured_outputs?' do
    it 'returns true for Gemini 2.0 Flash models' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-2.0-flash")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-2.0-flash")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini/gemini-2.0-flash-lite")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-2.0-flash-lite")).to eq(true)
    end

    it 'returns true for Gemini 2.5 models (current)' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-2.5-pro")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-2.5-pro")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini/gemini-2.5-flash")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-2.5-flash")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini/gemini-2.5-flash-lite")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-2.5-flash-lite")).to eq(true)
    end

    it 'returns true for Gemini 3 flash preview models' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-3-flash-preview")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-3-flash-preview")).to eq(true)
    end
    
    it 'returns false for unsupported legacy models' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.0-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.0-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.0-pro-002")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.0-pro-002")).to eq(false)
    end

    it 'returns false for deprecated Gemini 1.5 series (deprecated Oct 2025)' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.5-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.5-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.5-flash")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.5-flash")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.5-flash-8b")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.5-flash-8b")).to eq(false)
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
      
      expect(issues).to include(/Schema depth \(6\) exceeds recommended limit/)
    end
  end
end
