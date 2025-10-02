require 'spec_helper'
require 'dspy/signature'

# Define test type aliases
SimpleResponse = T.type_alias { T::Hash[String, String] }

ComplexResponse = T.type_alias do
  {
    "answer" => String,
    "confidence" => Float,
    "metadata" => T::Hash[String, T.untyped]
  }
end

NestedResponse = T.type_alias do
  {
    "result" => String,
    "details" => T::Array[T::Hash[String, String]],
    "summary" => {
      "total" => Integer,
      "success" => T::Boolean
    }
  }
end

# Define test signatures using type aliases
class SimpleTypeAliasSignature < DSPy::Signature
  description "Test signature with simple type alias"
  
  input do
    const :query, String
  end
  
  output do
    const :response, SimpleResponse
  end
end

class ComplexTypeAliasSignature < DSPy::Signature
  description "Test signature with complex type alias"
  
  input do
    const :question, String
  end
  
  output do
    const :result, T.nilable(ComplexResponse)
  end
end

class NestedTypeAliasSignature < DSPy::Signature
  description "Test signature with nested type alias"
  
  input do
    const :data, String
  end
  
  output do
    const :analysis, NestedResponse
  end
end

RSpec.describe "Type Alias Support" do
  describe "simple type alias schema generation" do
    it "generates correct schema for simple hash type alias" do
      schema = SimpleTypeAliasSignature.output_json_schema
      
      expect(schema[:properties][:response]).to eq({
        type: "object",
        propertyNames: { type: "string" },
        additionalProperties: { type: "string" },
        description: "A mapping where keys are strings and values are strings"
      })
    end
  end

  describe "complex type alias schema generation" do
    it "generates correct schema for structured type alias" do
      schema = ComplexTypeAliasSignature.output_json_schema
      
      expect(schema[:properties][:result]).to eq({
        type: ["object", "null"],
        properties: {
          "answer" => { type: "string" },
          "confidence" => { type: "number" },
          "metadata" => {
            type: "object",
            propertyNames: { type: "string" },
            additionalProperties: { type: "string" },
            description: "A mapping where keys are strings and values are strings"
          }
        },
        required: ["answer", "confidence", "metadata"],
        additionalProperties: false
      })
    end
  end

  describe "nested type alias schema generation" do
    it "generates correct schema for deeply nested structures" do
      schema = NestedTypeAliasSignature.output_json_schema
      
      expect(schema[:properties][:analysis]).to eq({
        type: "object",
        properties: {
          "result" => { type: "string" },
          "details" => {
            type: "array",
            items: {
              type: "object",
              propertyNames: { type: "string" },
              additionalProperties: { type: "string" },
              description: "A mapping where keys are strings and values are strings"
            }
          },
          "summary" => {
            type: "object",
            properties: {
              "total" => { type: "integer" },
              "success" => { type: "boolean" }
            },
            required: ["total", "success"],
            additionalProperties: false
          }
        },
        required: ["result", "details", "summary"],
        additionalProperties: false
      })
    end
  end

  describe "type alias resolution" do
    it "resolves type aliases to their underlying types" do
      # Test that the framework recognizes type aliases
      expect(ComplexResponse).to be_a(T::Private::Types::TypeAlias)
      expect(ComplexResponse.aliased_type).to be_a(T::Types::FixedHash)
      expect(ComplexResponse.aliased_type.types.keys).to include("answer", "confidence", "metadata")
    end
  end
end