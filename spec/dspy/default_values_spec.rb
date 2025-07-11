# frozen_string_literal: true

require 'spec_helper'
require 'dspy'

RSpec.describe 'Default values in signatures', :aggregate_failures do
  # Define a test signature with defaults
  class TestSignatureWithDefaults < DSPy::Signature
    description "Test signature with default values"
    
    input do
      const :query, String
      const :language, String, default: "English"
      const :max_items, Integer, default: 10
    end
    
    output do
      const :result, String
      const :confidence, Float, default: 1.0
      const :metadata, T::Hash[Symbol, T.untyped], default: {}
    end
  end

  describe 'input defaults' do
    it 'creates struct with default values' do
      # Create struct with only required field
      input_struct = TestSignatureWithDefaults.input_struct_class.new(query: "test")
      
      expect(input_struct.query).to eq("test")
      expect(input_struct.language).to eq("English")
      expect(input_struct.max_items).to eq(10)
    end
    
    it 'allows overriding default values' do
      input_struct = TestSignatureWithDefaults.input_struct_class.new(
        query: "test",
        language: "Spanish",
        max_items: 5
      )
      
      expect(input_struct.language).to eq("Spanish")
      expect(input_struct.max_items).to eq(5)
    end
  end

  describe 'output defaults' do
    it 'creates struct with default values' do
      # Create struct with only required field
      output_struct = TestSignatureWithDefaults.output_struct_class.new(result: "answer")
      
      expect(output_struct.result).to eq("answer")
      expect(output_struct.confidence).to eq(1.0)
      expect(output_struct.metadata).to eq({})
    end
  end

  describe 'default value handling in structs' do
    it 'constructs input struct with partial values and applies defaults' do
      # When we create a struct with only required values
      input_data = { query: "test query" }
      
      # The struct should have default values applied
      input_struct = TestSignatureWithDefaults.input_struct_class.new(**input_data)
      
      expect(input_struct.query).to eq("test query")
      expect(input_struct.language).to eq("English")  # Default applied
      expect(input_struct.max_items).to eq(10)        # Default applied
    end
    
    it 'constructs output struct with partial values and applies defaults' do
      # When we create a struct with only required values
      output_data = { result: "answer text" }
      
      # The struct should have default values applied
      output_struct = TestSignatureWithDefaults.output_struct_class.new(**output_data)
      
      expect(output_struct.result).to eq("answer text")
      expect(output_struct.confidence).to eq(1.0)     # Default applied
      expect(output_struct.metadata).to eq({})        # Default applied
    end
  end

  describe 'field descriptors' do
    it 'stores default values in field descriptors' do
      descriptors = TestSignatureWithDefaults.output_field_descriptors
      
      confidence_desc = descriptors[:confidence]
      expect(confidence_desc.has_default).to be true
      expect(confidence_desc.default_value).to eq(1.0)
      
      metadata_desc = descriptors[:metadata]
      expect(metadata_desc.has_default).to be true
      expect(metadata_desc.default_value).to eq({})
    end
  end
end