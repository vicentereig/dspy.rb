# frozen_string_literal: true

require 'spec_helper'
require 'dspy/lm/adapters/gemini/schema_converter'

RSpec.describe DSPy::LM::Adapters::Gemini::SchemaConverter do
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
      expect(result[:properties][:answer]).to eq({ type: "string" })
      expect(result[:properties][:confidence]).to eq({ type: "number" })
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
  
  describe '.supports_structured_outputs?' do
    it 'returns true for models with full schema support' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.5-pro")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-1.5-pro")).to eq(true)
    end
    
    it 'returns false for JSON-only models (no schema support)' do
      # Based on official gemini-ai gem documentation: gemini-1.5-flash is JSON-only, not schema
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.5-flash")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.5-flash")).to eq(false)
    end
    
    it 'returns false for unsupported models' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.0-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.0-pro")).to eq(false)
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