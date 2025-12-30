# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'schema_adapters'

module DSPy
  class Signature
    extend T::Sig

    # Container for field type and description
    class FieldDescriptor
      extend T::Sig

      sig { returns(T.untyped) }
      attr_reader :type

      sig { returns(T.nilable(String)) }
      attr_reader :description

      sig { returns(T::Boolean) }
      attr_reader :has_default

      sig { returns(T.untyped) }
      attr_reader :default_value

      sig { params(type: T.untyped, description: T.nilable(String), has_default: T::Boolean, default_value: T.untyped).void }
      def initialize(type, description = nil, has_default = false, default_value = nil)
        @type = type
        @description = description
        @has_default = has_default
        @default_value = default_value
      end
    end

    # DSL helper for building struct classes with field descriptions
    class StructBuilder
      extend T::Sig

      sig { returns(T::Hash[Symbol, FieldDescriptor]) }
      attr_reader :field_descriptors

      sig { void }
      def initialize
        @field_descriptors = {}
      end

      sig { params(name: Symbol, type: T.untyped, kwargs: T.untyped).void }
      def const(name, type, **kwargs)
        description = kwargs[:description]
        has_default = kwargs.key?(:default)
        default_value = kwargs[:default]
        @field_descriptors[name] = FieldDescriptor.new(type, description, has_default, default_value)
      end

      sig { returns(T.class_of(T::Struct)) }
      def build_struct_class
        descriptors = @field_descriptors
        Class.new(T::Struct) do
          extend T::Sig
          descriptors.each do |name, descriptor|
            if descriptor.has_default
              const name, descriptor.type, default: descriptor.default_value
            else
              const name, descriptor.type
            end
          end
        end
      end
    end

    class << self
      extend T::Sig

      sig { returns(T.nilable(String)) }
      attr_reader :desc

      sig { returns(T.nilable(T.class_of(T::Struct))) }
      attr_reader :input_struct_class

      sig { returns(T.nilable(T.class_of(T::Struct))) }
      attr_reader :output_struct_class

      sig { returns(T::Hash[Symbol, FieldDescriptor]) }
      attr_reader :input_field_descriptors

      sig { returns(T::Hash[Symbol, FieldDescriptor]) }
      attr_reader :output_field_descriptors

      sig { params(desc: T.nilable(String)).returns(T.nilable(String)) }
      def description(desc = nil)
        if desc.nil?
          @desc
        else
          @desc = desc
        end
      end

      sig { params(block: T.proc.void).void }
      def input(&block)
        builder = StructBuilder.new

        if block.arity > 0
          block.call(builder)
        else
          # Preferred format
          builder.instance_eval(&block)
        end

        @input_field_descriptors = builder.field_descriptors
        @input_struct_class = builder.build_struct_class
      end

      sig { params(block: T.proc.void).void }
      def output(&block)
        builder = StructBuilder.new

        if block.arity > 0
          block.call(builder)
        else
          # Preferred format
          builder.instance_eval(&block)
        end

        @output_field_descriptors = builder.field_descriptors
        @output_struct_class = builder.build_struct_class
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def input_json_schema
        return {} unless @input_struct_class

        properties = {}
        required = []

        @input_field_descriptors&.each do |name, descriptor|
          schema = DSPy::TypeSystem::SorbetJsonSchema.type_to_json_schema(descriptor.type)
          schema[:description] = descriptor.description if descriptor.description
          properties[name] = schema
          required << name.to_s unless descriptor.has_default
        end

        {
          "$schema": "http://json-schema.org/draft-06/schema#",
          type: "object",
          properties: properties,
          required: required
        }
      end

      sig { returns(T.nilable(T.class_of(T::Struct))) }
      def input_schema
        @input_struct_class
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def output_json_schema
        return {} unless @output_struct_class

        properties = {}
        required = []

        @output_field_descriptors&.each do |name, descriptor|
          schema = DSPy::TypeSystem::SorbetJsonSchema.type_to_json_schema(descriptor.type)
          schema[:description] = descriptor.description if descriptor.description
          properties[name] = schema
          required << name.to_s unless descriptor.has_default
        end

        {
          "$schema": "http://json-schema.org/draft-06/schema#",
          type: "object",
          properties: properties,
          required: required
        }
      end

      # Returns output JSON schema with accumulated $defs for recursive types
      # This is needed for providers like OpenAI and Gemini that require $defs at the root
      sig { returns(DSPy::TypeSystem::SorbetJsonSchema::SchemaResult) }
      def output_json_schema_with_defs
        properties = {}
        required = []
        all_definitions = {}

        @output_field_descriptors&.each do |name, descriptor|
          result = DSPy::TypeSystem::SorbetJsonSchema.type_to_json_schema_with_defs(descriptor.type, nil, all_definitions)
          schema = result.schema
          schema[:description] = descriptor.description if descriptor.description
          properties[name] = schema
          required << name.to_s unless descriptor.has_default
        end

        final_schema = {
          "$schema": "http://json-schema.org/draft-06/schema#",
          type: "object",
          properties: properties,
          required: required
        }

        DSPy::TypeSystem::SorbetJsonSchema::SchemaResult.new(
          schema: final_schema,
          definitions: all_definitions
        )
      end

      sig { returns(T.nilable(T.class_of(T::Struct))) }
      def output_schema
        @output_struct_class
      end
    end
  end
end
