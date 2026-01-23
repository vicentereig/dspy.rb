# frozen_string_literal: true

require 'spec_helper'
require 'dspy/anthropic/lm/schema_converter'

RSpec.describe DSPy::Anthropic::LM::SchemaConverter do
  describe '.to_beta_format' do
    context 'when converting a simple signature schema' do
      let(:signature_class) do
        Class.new(DSPy::Signature) do
          input do
            const :question, String, description: 'The question to answer'
          end
          output do
            const :answer, String, description: 'The answer'
            const :confidence, Float, description: 'Confidence score'
          end
        end
      end

      it 'removes the $schema field' do
        result = described_class.to_beta_format(signature_class)

        expect(result).not_to have_key(:$schema)
        expect(result).not_to have_key('$schema')
      end

      it 'adds additionalProperties: false to the top-level object' do
        result = described_class.to_beta_format(signature_class)

        expect(result[:type]).to eq('object')
        expect(result[:additionalProperties]).to eq(false)
      end

      it 'preserves the properties from the original schema' do
        result = described_class.to_beta_format(signature_class)

        expect(result[:properties]).to have_key(:answer)
        expect(result[:properties]).to have_key(:confidence)
      end
    end

    context 'when handling nested objects' do
      let(:person_class) do
        Class.new(T::Struct) do
          const :name, String
          const :age, Integer
        end
      end
      let(:signature_class) do
        person = person_class
        Class.new(DSPy::Signature) do
          output do
            const :result, person
          end
        end
      end

      it 'adds additionalProperties: false to nested objects recursively' do
        result = described_class.to_beta_format(signature_class)

        # Check that nested object has additionalProperties: false
        nested_object = result[:properties][:result]
        expect(nested_object[:type]).to eq('object')
        expect(nested_object[:additionalProperties]).to eq(false)
      end
    end

    context 'when handling arrays with object items' do
      let(:item_class) do
        Class.new(T::Struct) do
          const :id, String
          const :name, String
        end
      end
      let(:signature_class) do
        item = item_class
        Class.new(DSPy::Signature) do
          output do
            const :items, T::Array[item]
          end
        end
      end

      it 'adds additionalProperties: false to object items in arrays' do
        result = described_class.to_beta_format(signature_class)

        array_property = result[:properties][:items]
        expect(array_property[:type]).to eq('array')

        item_schema = array_property[:items]
        expect(item_schema[:type]).to eq('object')
        expect(item_schema[:additionalProperties]).to eq(false)
      end
    end

    context 'when handling union types (oneOf)' do
      # Define named classes so sorbet-schema generates oneOf properly
      before(:all) do
        unless defined?(TestEmail)
          TestEmail = Class.new(T::Struct) do
            const :address, String
            const :verified, T::Boolean
          end
        end
        unless defined?(TestPhone)
          TestPhone = Class.new(T::Struct) do
            const :number, String
            const :country_code, String
          end
        end
      end

      let(:signature_class) do
        Class.new(DSPy::Signature) do
          output do
            const :contact, T.any(TestEmail, TestPhone)
          end
        end
      end

      it 'adds additionalProperties: false to all objects in oneOf' do
        result = described_class.to_beta_format(signature_class)

        # Check top level
        expect(result[:additionalProperties]).to eq(false)

        # Check that oneOf is present
        contact_property = result[:properties][:contact]
        expect(contact_property).to have_key(:oneOf)

        # Check each option in the union
        contact_property[:oneOf].each do |option|
          expect(option[:type]).to eq('object')
          expect(option[:additionalProperties]).to eq(false)
        end
      end
    end

    context 'when handling deeply nested structures' do
      let(:user_class) do
        Class.new(T::Struct) do
          const :name, String
          const :email, String
        end
      end
      let(:metadata_class) do
        Class.new(T::Struct) do
          const :created_at, String
          const :updated_at, String
        end
      end
      let(:data_class) do
        user = user_class
        metadata = metadata_class
        Class.new(T::Struct) do
          const :user, user
          const :metadata, metadata
        end
      end
      let(:signature_class) do
        data = data_class
        Class.new(DSPy::Signature) do
          output do
            const :data, data
          end
        end
      end

      it 'adds additionalProperties: false at all nesting levels' do
        result = described_class.to_beta_format(signature_class)

        # Top level
        expect(result[:additionalProperties]).to eq(false)

        # First nested level
        data_object = result[:properties][:data]
        expect(data_object[:additionalProperties]).to eq(false)

        # Check nested properties (user and metadata)
        if data_object[:properties]
          data_object[:properties].each_value do |prop|
            if prop.is_a?(Hash) && prop[:type] == 'object'
              expect(prop[:additionalProperties]).to eq(false)
            end
          end
        end
      end
    end
  end

  describe '.add_additional_properties_false' do
    it 'adds additionalProperties: false to an object schema' do
      schema = { type: 'object', properties: { name: { type: 'string' } } }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:additionalProperties]).to eq(false)
    end

    it 'does not add additionalProperties to non-object types' do
      schema = { type: 'string' }

      result = described_class.add_additional_properties_false(schema)

      expect(result).not_to have_key(:additionalProperties)
    end

    it 'processes nested properties recursively' do
      schema = {
        type: 'object',
        properties: {
          user: {
            type: 'object',
            properties: {
              name: { type: 'string' }
            }
          }
        }
      }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:additionalProperties]).to eq(false)
      expect(result[:properties][:user][:additionalProperties]).to eq(false)
    end

    it 'processes array items recursively' do
      schema = {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string' }
          }
        }
      }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:items][:additionalProperties]).to eq(false)
    end

    it 'processes oneOf schemas recursively' do
      schema = {
        type: 'object',
        properties: {
          contact: {
            oneOf: [
              {
                type: 'object',
                properties: { email: { type: 'string' } }
              },
              {
                type: 'object',
                properties: { phone: { type: 'string' } }
              }
            ]
          }
        }
      }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:additionalProperties]).to eq(false)
      expect(result[:properties][:contact][:oneOf][0][:additionalProperties]).to eq(false)
      expect(result[:properties][:contact][:oneOf][1][:additionalProperties]).to eq(false)
    end

    it 'processes anyOf schemas recursively' do
      schema = {
        type: 'object',
        anyOf: [
          {
            type: 'object',
            properties: { foo: { type: 'string' } }
          },
          {
            type: 'object',
            properties: { bar: { type: 'number' } }
          }
        ]
      }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:anyOf][0][:additionalProperties]).to eq(false)
      expect(result[:anyOf][1][:additionalProperties]).to eq(false)
    end

    it 'processes allOf schemas recursively' do
      schema = {
        type: 'object',
        allOf: [
          {
            type: 'object',
            properties: { id: { type: 'string' } }
          },
          {
            type: 'object',
            properties: { name: { type: 'string' } }
          }
        ]
      }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:allOf][0][:additionalProperties]).to eq(false)
      expect(result[:allOf][1][:additionalProperties]).to eq(false)
    end

    it 'processes definitions recursively' do
      schema = {
        type: 'object',
        properties: { user: { '$ref': '#/definitions/User' } },
        definitions: {
          User: {
            type: 'object',
            properties: { name: { type: 'string' } }
          }
        }
      }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:definitions][:User][:additionalProperties]).to eq(false)
    end

    it 'processes $defs recursively' do
      schema = {
        type: 'object',
        properties: { user: { '$ref': '#/$defs/User' } },
        '$defs': {
          User: {
            type: 'object',
            properties: { name: { type: 'string' } }
          }
        }
      }

      result = described_class.add_additional_properties_false(schema)

      expect(result[:'$defs'][:User][:additionalProperties]).to eq(false)
    end
  end
end
