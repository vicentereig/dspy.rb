# typed: strict
# frozen_string_literal: true

require 'spec_helper'

# Test the examples from the getting-started documentation
RSpec.describe "Getting Started Examples" do
  describe "EmailClassifier with T::Enum" do
    class EmailCategory < T::Enum
      enums do
        Technical = new('technical')
        Billing = new('billing')
        General = new('general')
      end
    end

    class EmailClassifier < DSPy::Signature
      input do
        const :subject, String
        const :body, String
      end
      
      output do
        const :category, EmailCategory
        const :confidence, Float
      end
    end

    it "correctly generates JSON schema for T::Enum output" do
      schema = EmailClassifier.output_json_schema
      category_schema = schema[:properties][:category]
      
      expect(category_schema).to eq({
        type: "string",
        enum: ["technical", "billing", "general"]
      })
    end

    it "generates correct input JSON schema" do
      schema = EmailClassifier.input_json_schema
      
      expect(schema[:properties][:subject]).to eq({ type: "string" })
      expect(schema[:properties][:body]).to eq({ type: "string" })
    end
  end
end