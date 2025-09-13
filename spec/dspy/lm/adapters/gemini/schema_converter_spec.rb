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
      
      expect(result[:properties][:items]).to eq({
        type: "array",
        items: { type: "string" }
      })
      expect(result[:properties][:count]).to eq({ type: "integer" })
      expect(result[:properties][:enabled]).to eq({ type: "boolean" })
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
      
      expect(result[:properties][:item]).to eq({
        type: "object",
        properties: {
          name: { type: "string" },
          value: { type: "integer" },
          _type: { type: "string", const: "ItemStruct" }
        },
        required: ["name", "value", "_type"]
      })
    end
    
    it 'handles T::Enum types' do
      stub_const('StatusEnum', Class.new(T::Enum) do
        enums do
          Active = new('active')
          Inactive = new('inactive')
        end
      end)
      
      enum_signature = Class.new(DSPy::Signature) do
        output do
          const :status, StatusEnum, description: "Status"
        end
      end
      
      result = described_class.to_gemini_format(enum_signature)
      
      # T::Enum should be converted to string with enum values
      expect(result[:properties][:status]).to eq({
        type: "string",
        enum: ["active", "inactive"]
      })
    end
    
    it 'caches converted schemas' do
      # First call
      result1 = described_class.to_gemini_format(signature_class)
      
      # Second call should return cached result
      expect(DSPy::LM.cache_manager).to receive(:get_schema)
        .with(signature_class, "gemini", {})
        .and_return(result1)
      
      result2 = described_class.to_gemini_format(signature_class)
      expect(result2).to eq(result1)
    end
  end
  
  describe '.supports_structured_outputs?' do
    it 'returns true for supported models' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.5-pro")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.5-flash")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-1.5-pro")).to eq(true)
      expect(described_class.supports_structured_outputs?("gemini-1.5-flash")).to eq(true)
    end
    
    it 'returns false for unsupported models' do
      expect(described_class.supports_structured_outputs?("gemini/gemini-1.0-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-pro")).to eq(false)
      expect(described_class.supports_structured_outputs?("gemini-1.0-pro")).to eq(false)
    end
    
    it 'caches model support checks' do
      model = "gemini-1.5-pro"
      
      # First call
      result1 = described_class.supports_structured_outputs?(model)
      
      # Second call should use cache
      expect(DSPy::LM.cache_manager).to receive(:get_capability)
        .with(model, "structured_outputs")
        .and_return(result1)
      
      result2 = described_class.supports_structured_outputs?(model)
      expect(result2).to eq(result1)
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