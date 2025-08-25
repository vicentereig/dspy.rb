require 'spec_helper'

RSpec.describe DSPy::LM::Strategies::EnhancedPromptingStrategy do
  # Create a minimal test adapter
  class TypeAliasTestAdapter < DSPy::LM::Adapter
    def call_api(messages, **params)
      DSPy::LM::Response.new(
        content: '{"answer": "test", "confidence": 0.9}',
        role: 'assistant',
        stop_reason: 'end_turn'
      )
    end
  end

  let(:adapter) { TypeAliasTestAdapter.new(model: "test-model", api_key: "test-key") }
  let(:signature_class) { TypeAliasTestSignature }
  let(:strategy) { described_class.new(adapter, signature_class) }

  # Define type aliases for testing
  TestResponse = T.type_alias do
    {
      "answer" => String,
      "confidence" => Float,
      "sources" => T::Array[T::Hash[String, T.untyped]]
    }
  end

  class TypeAliasTestSignature < DSPy::Signature
    description "Test signature for enhanced prompting with type aliases"
    
    input do
      const :question, String
    end
    
    output do
      const :response, T.nilable(TestResponse)
      const :simple_field, String
    end
  end

  describe "#generate_example_value" do
    it "generates proper examples for nested objects" do
      field_schema = {
        type: "object",
        properties: {
          "answer" => { type: "string" },
          "confidence" => { type: "number" },
          "sources" => {
            type: "array",
            items: {
              type: "object",
              propertyNames: { type: "string" },
              additionalProperties: { type: "string" }
            }
          }
        }
      }

      result = strategy.send(:generate_example_value, field_schema)
      
      expect(result).to be_a(Hash)
      expect(result["answer"]).to eq("example string")
      expect(result["confidence"]).to eq(3.14)
      expect(result["sources"]).to be_an(Array)
      expect(result["sources"].first).to be_a(Hash)
    end

    it "generates proper examples for union types with objects" do
      field_schema = {
        type: ["object", "null"],
        properties: {
          "data" => { type: "string" },
          "count" => { type: "integer" }
        }
      }

      result = strategy.send(:generate_example_value, field_schema)
      
      expect(result).to be_a(Hash)
      expect(result["data"]).to eq("example string")
      expect(result["count"]).to eq(42)
    end

    it "generates proper examples for nested arrays" do
      field_schema = {
        type: "array",
        items: {
          type: "object",
          properties: {
            "name" => { type: "string" },
            "value" => { type: "number" }
          }
        }
      }

      result = strategy.send(:generate_example_value, field_schema)
      
      expect(result).to be_an(Array)
      expect(result.first).to be_a(Hash)
      expect(result.first["name"]).to eq("example string")
      expect(result.first["value"]).to eq(3.14)
    end
  end

  describe "#generate_example_from_schema" do
    it "generates complete examples for type alias schemas" do
      schema = TypeAliasTestSignature.output_json_schema
      
      result = strategy.send(:generate_example_from_schema, schema)
      
      expect(result).to have_key("response")
      expect(result).to have_key("simple_field")
      
      # Check the type alias field structure
      response_example = result["response"]
      expect(response_example).to be_a(Hash)
      expect(response_example).to have_key("answer")
      expect(response_example).to have_key("confidence")
      expect(response_example).to have_key("sources")
      
      expect(response_example["answer"]).to eq("example string")
      expect(response_example["confidence"]).to eq(3.14)
      expect(response_example["sources"]).to be_an(Array)
    end
  end

  describe "integration with enhanced prompting" do
    it "creates proper JSON examples in prompts for type aliases" do
      # Create a mock signature with type alias
      allow(TypeAliasTestSignature).to receive(:output_json_schema).and_return(
        TypeAliasTestSignature.output_json_schema
      )

      # Test that enhanced prompting includes proper structured examples
      schema = TypeAliasTestSignature.output_json_schema
      enhanced_prompt = strategy.send(:enhance_prompt_with_json_instructions, "Test prompt", schema)
      
      expect(enhanced_prompt).to include("answer")
      expect(enhanced_prompt).to include("confidence")
      expect(enhanced_prompt).to include("sources")
      expect(enhanced_prompt).to include("example string")
      expect(enhanced_prompt).to include("3.14")
      
      # Verify it's valid JSON structure in the prompt
      json_match = enhanced_prompt.match(/```json\n(.*?)\n```/m)
      expect(json_match).not_to be_nil
      
      parsed_example = JSON.parse(json_match[1])
      expect(parsed_example["response"]).to be_a(Hash)
      expect(parsed_example["response"]["answer"]).to be_a(String)
      expect(parsed_example["response"]["confidence"]).to be_a(Numeric)
    end
  end
end