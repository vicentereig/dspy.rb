# frozen_string_literal: true

require 'spec_helper'
require 'dspy/lm/adapters/openai/schema_converter'

RSpec.describe DSPy::LM::Adapters::OpenAI::SchemaConverter do
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
end