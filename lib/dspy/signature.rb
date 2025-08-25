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

      sig { returns(T.nilable(T.class_of(T::Struct))) }
      def output_schema
        @output_struct_class
      end

      private

      sig { params(type: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def type_to_json_schema(type)
        # Handle T::Boolean type alias first
        if type == T::Boolean
          return { type: "boolean" }
        end

        # Handle type aliases by resolving to their underlying type
        if type.is_a?(T::Private::Types::TypeAlias)
          return type_to_json_schema(type.aliased_type)
        end

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
          elsif type == Numeric
            { type: "number" }
          elsif [TrueClass, FalseClass].include?(type)
            { type: "boolean" }
          elsif type < T::Struct
            # Handle custom T::Struct classes by generating nested object schema
            generate_struct_schema(type)
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
          when "Numeric"
            { type: "number" }
          when "TrueClass", "FalseClass"
            { type: "boolean" }
          when "T::Boolean"
            { type: "boolean" }
          else
            # Check if it's an enum
            if type.raw_type < T::Enum
              # Get all enum values
              values = type.raw_type.values.map(&:serialize)
              { type: "string", enum: values }
            elsif type.raw_type < T::Struct
              # Handle custom T::Struct classes
              generate_struct_schema(type.raw_type)
            else
              { type: "string" }  # Default fallback
            end
          end
        elsif type.is_a?(T::Types::TypedArray)
          # Handle arrays properly with nested item type
          {
            type: "array",
            items: type_to_json_schema(type.type)
          }
        elsif type.is_a?(T::Types::TypedHash)
          # Handle hashes as objects with additionalProperties
          # TypedHash has keys and values methods to access its key and value types
          key_schema = type_to_json_schema(type.keys)
          value_schema = type_to_json_schema(type.values)
          
          # Create a more descriptive schema for nested structures
          {
            type: "object",
            propertyNames: key_schema,  # Describe key constraints
            additionalProperties: value_schema,
            # Add a more explicit description of the expected structure
            description: "A mapping where keys are #{key_schema[:type]}s and values are #{value_schema[:description] || value_schema[:type]}s"
          }
        elsif type.is_a?(T::Types::FixedHash)
          # Handle fixed hashes (from type aliases like { "key" => Type })
          properties = {}
          required = []
          
          type.types.each do |key, value_type|
            properties[key] = type_to_json_schema(value_type)
            required << key
          end
          
          {
            type: "object",
            properties: properties,
            required: required,
            additionalProperties: false
          }
        elsif type.class.name == "T::Private::Types::SimplePairUnion"
          # Handle T.nilable types (T::Private::Types::SimplePairUnion)
          # This is the actual implementation of T.nilable(SomeType)
          has_nil = type.respond_to?(:types) && type.types.any? do |t| 
            (t.respond_to?(:raw_type) && t.raw_type == NilClass) ||
            (t.respond_to?(:name) && t.name == "NilClass")
          end
          
          if has_nil
            # Find the non-nil type
            non_nil_type = type.types.find do |t|
              !(t.respond_to?(:raw_type) && t.raw_type == NilClass) &&
              !(t.respond_to?(:name) && t.name == "NilClass")
            end
            
            if non_nil_type
              base_schema = type_to_json_schema(non_nil_type)
              if base_schema[:type].is_a?(String)
                # Convert single type to array with null
                { type: [base_schema[:type], "null"] }.merge(base_schema.except(:type))
              else
                # For complex schemas, use anyOf to allow null
                { anyOf: [base_schema, { type: "null" }] }
              end
            else
              { type: "string" } # Fallback
            end
          else
            # Not nilable SimplePairUnion - this is a regular T.any() union
            # Generate oneOf schema for all types
            if type.respond_to?(:types) && type.types.length > 1
              {
                oneOf: type.types.map { |t| type_to_json_schema(t) },
                description: "Union of multiple types"
              }
            else
              # Single type or fallback
              first_type = type.respond_to?(:types) ? type.types.first : type
              type_to_json_schema(first_type)
            end
          end
        elsif type.is_a?(T::Types::Union)
          # Check if this is a nilable type (contains NilClass)
          is_nilable = type.types.any? { |t| t == T::Utils.coerce(NilClass) }
          non_nil_types = type.types.reject { |t| t == T::Utils.coerce(NilClass) }
          
          # Special case: check if we have TrueClass + FalseClass (T.nilable(T::Boolean))
          if non_nil_types.size == 2 && is_nilable
            true_class_type = non_nil_types.find { |t| t.respond_to?(:raw_type) && t.raw_type == TrueClass }
            false_class_type = non_nil_types.find { |t| t.respond_to?(:raw_type) && t.raw_type == FalseClass }
            
            if true_class_type && false_class_type
              # This is T.nilable(T::Boolean) - treat as nilable boolean
              return { type: ["boolean", "null"] }
            end
          end
          
          if non_nil_types.size == 1 && is_nilable
            # This is T.nilable(SomeType) - generate proper schema with null allowed
            base_schema = type_to_json_schema(non_nil_types.first)
            if base_schema[:type].is_a?(String)
              # Convert single type to array with null
              { type: [base_schema[:type], "null"] }.merge(base_schema.except(:type))
            else
              # For complex schemas, use anyOf to allow null
              { anyOf: [base_schema, { type: "null" }] }
            end
          elsif non_nil_types.size == 1
            # Non-nilable single type union (shouldn't happen in practice)
            type_to_json_schema(non_nil_types.first)
          elsif non_nil_types.size > 1
            # Handle complex unions with oneOf for better JSON schema compliance
            base_schema = {
              oneOf: non_nil_types.map { |t| type_to_json_schema(t) },
              description: "Union of multiple types"
            }
            if is_nilable
              # Add null as an option for complex nilable unions
              base_schema[:oneOf] << { type: "null" }
            end
            base_schema
          else
            { type: "string" }  # Fallback for complex unions
          end
        elsif type.is_a?(T::Types::ClassOf)
          # Handle T.class_of() types
          {
            type: "string",
            description: "Class name (T.class_of type)"
          }
        else
          { type: "string" }  # Default fallback
        end
      end

      private

      # Generate JSON schema for custom T::Struct classes
      sig { params(struct_class: T.class_of(T::Struct)).returns(T::Hash[Symbol, T.untyped]) }
      def generate_struct_schema(struct_class)
        return { type: "string", description: "Struct (schema introspection not available)" } unless struct_class.respond_to?(:props)

        properties = {}
        required = []

        # Check if struct already has a _type field
        if struct_class.props.key?(:_type)
          raise DSPy::ValidationError, "_type field conflict: #{struct_class.name} already has a _type field defined. " \
                                       "DSPy uses _type for automatic type detection in union types."
        end

        # Add automatic _type field for type detection
        properties[:_type] = {
          type: "string",
          const: struct_class.name.split('::').last  # Use the simple class name
        }
        required << "_type"

        struct_class.props.each do |prop_name, prop_info|
          prop_type = prop_info[:type_object] || prop_info[:type]
          properties[prop_name] = type_to_json_schema(prop_type)
          
          # A field is required if it's not fully optional
          # fully_optional is true for nilable prop fields
          # immutable const fields are required unless nilable
          unless prop_info[:fully_optional]
            required << prop_name.to_s
          end
        end

        {
          type: "object",
          properties: properties,
          required: required,
          description: "#{struct_class.name} struct"
        }
      end
    end
  end
end
