# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  class SorbetSignature
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

      sig { params(type: T.untyped, description: T.nilable(String), has_default: T::Boolean).void }
      def initialize(type, description = nil, has_default = false)
        @type = type
        @description = description
        @has_default = has_default
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
        @field_descriptors[name] = FieldDescriptor.new(type, description, has_default)
        # Store default for future use if needed
      end

      sig { returns(T.class_of(T::Struct)) }
      def build_struct_class
        descriptors = @field_descriptors
        Class.new(T::Struct) do
          extend T::Sig
          descriptors.each do |name, descriptor|
            const name, descriptor.type
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
          schema = type_to_json_schema(descriptor.type)
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

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def output_json_schema
        return {} unless @output_struct_class

        properties = {}
        required = []

        @output_field_descriptors&.each do |name, descriptor|
          schema = type_to_json_schema(descriptor.type)
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

      private

      sig { params(type: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def type_to_json_schema(type)
        # Handle raw class types first
        if type.is_a?(Class)
          if type < T::Enum
            # Get all enum values
            values = type.values.map(&:serialize)
            { type: "string", enum: values }
          elsif type == String
            { type: "string" }
          elsif type == Integer
            { type: "integer" }
          elsif type == Float
            { type: "number" }
          elsif [TrueClass, FalseClass].include?(type)
            { type: "boolean" }
          else
            { type: "string" }  # Default fallback
          end
        elsif type.is_a?(T::Types::Simple)
          case type.raw_type.to_s
          when "String"
            { type: "string" }
          when "Integer"
            { type: "integer" }
          when "Float"
            { type: "number" }
          when "TrueClass", "FalseClass"
            { type: "boolean" }
          else
            # Check if it's an enum
            if type.raw_type < T::Enum
              # Get all enum values
              values = type.raw_type.values.map(&:serialize)
              { type: "string", enum: values }
            else
              { type: "string" }  # Default fallback
            end
          end
        elsif type.is_a?(T::Types::Union)
          # For optional types (T.nilable), just use the non-nil type
          non_nil_types = type.types.reject { |t| t == T::Utils.coerce(NilClass) }
          if non_nil_types.size == 1
            type_to_json_schema(non_nil_types.first)
          else
            { type: "string" }  # Fallback for complex unions
          end
        else
          { type: "string" }  # Default fallback
        end
      end
    end
  end
end
