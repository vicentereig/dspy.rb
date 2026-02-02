# typed: strict
# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'

module DSPy
  module TypeSystem
    # Unified module for converting Sorbet types to JSON Schema
    # Extracted from Signature class to ensure consistency across Tools, Toolsets, and Signatures
    module SorbetJsonSchema
      extend T::Sig
      extend T::Helpers

      # Result type that includes both schema and any accumulated definitions
      class SchemaResult < T::Struct
        const :schema, T::Hash[Symbol, T.untyped]
        const :definitions, T::Hash[String, T::Hash[Symbol, T.untyped]], default: {}
      end

      # Convert a Sorbet type to JSON Schema format with definitions tracking
      # Returns a SchemaResult with the schema and any $defs needed
      sig { params(type: T.untyped, visited: T.nilable(T::Set[T.untyped]), definitions: T.nilable(T::Hash[String, T::Hash[Symbol, T.untyped]])).returns(SchemaResult) }
      def self.type_to_json_schema_with_defs(type, visited = nil, definitions = nil)
        visited ||= Set.new
        definitions ||= {}
        schema = type_to_json_schema_internal(type, visited, definitions)
        SchemaResult.new(schema: schema, definitions: definitions)
      end

      # Convert a Sorbet type to JSON Schema format
      # For backward compatibility, this method returns just the schema hash
      sig { params(type: T.untyped, visited: T.nilable(T::Set[T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def self.type_to_json_schema(type, visited = nil)
        visited ||= Set.new
        type_to_json_schema_internal(type, visited, {})
      end

      # Internal implementation that tracks definitions
      sig { params(type: T.untyped, visited: T::Set[T.untyped], definitions: T::Hash[String, T::Hash[Symbol, T.untyped]]).returns(T::Hash[Symbol, T.untyped]) }
      def self.type_to_json_schema_internal(type, visited, definitions)
        
        # Handle T::Boolean type alias first
        if type == T::Boolean
          return { type: "boolean" }
        end

        # Handle type aliases by resolving to their underlying type
        if type.is_a?(T::Private::Types::TypeAlias)
          return type_to_json_schema_internal(type.aliased_type, visited, definitions)
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
          elsif type == Date
            { type: "string", format: "date" }
          elsif type == DateTime
            { type: "string", format: "date-time" }
          elsif type == Time
            { type: "string", format: "date-time" }
          elsif [TrueClass, FalseClass].include?(type)
            { type: "boolean" }
          elsif type < T::Struct
            # Handle custom T::Struct classes by generating nested object schema
            # Check for recursion
            if visited.include?(type)
              # Return a reference to avoid infinite recursion
              # Use #/$defs/ format for OpenAI/Gemini compatibility
              simple_name = type.name.split('::').last
              {
                "$ref" => "#/$defs/#{simple_name}"
              }
            else
              generate_struct_schema_internal(type, visited, definitions)
            end
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
          when "Date"
            { type: "string", format: "date" }
          when "DateTime"
            { type: "string", format: "date-time" }
          when "Time"
            { type: "string", format: "date-time" }
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
              if visited.include?(type.raw_type)
                # Use #/$defs/ format for OpenAI/Gemini compatibility
                simple_name = type.raw_type.name.split('::').last
                {
                  "$ref" => "#/$defs/#{simple_name}"
                }
              else
                generate_struct_schema_internal(type.raw_type, visited, definitions)
              end
            else
              { type: "string" }  # Default fallback
            end
          end
        elsif type.is_a?(T::Types::TypedArray)
          # Handle arrays properly with nested item type
          {
            type: "array",
            items: type_to_json_schema_internal(type.type, visited, definitions)
          }
        elsif type.is_a?(T::Types::TypedHash)
          # Handle hashes as objects with additionalProperties
          # TypedHash has keys and values methods to access its key and value types
          # Note: propertyNames is NOT supported by OpenAI structured outputs, so we omit it
          value_schema = type_to_json_schema_internal(type.values, visited, definitions)
          key_type_desc = type.keys.respond_to?(:raw_type) ? type.keys.raw_type.to_s : "string"
          value_type_desc = value_schema[:description] || value_schema[:type].to_s

          # Create a schema compatible with OpenAI structured outputs
          {
            type: "object",
            additionalProperties: value_schema,
            # Description explains the expected structure without using propertyNames
            description: "A mapping where keys are #{key_type_desc}s and values are #{value_type_desc}s"
          }
        elsif type.is_a?(T::Types::FixedHash)
          # Handle fixed hashes (from type aliases like { "key" => Type })
          properties = {}
          required = []

          type.types.each do |key, value_type|
            properties[key] = type_to_json_schema_internal(value_type, visited, definitions)
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
              base_schema = type_to_json_schema_internal(non_nil_type, visited, definitions)
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
            # Generate anyOf schema for all types (oneOf not supported by Anthropic strict mode)
            if type.respond_to?(:types) && type.types.length > 1
              {
                anyOf: type.types.map { |t| type_to_json_schema_internal(t, visited, definitions) },
                description: "Union of multiple types"
              }
            else
              # Single type or fallback
              first_type = type.respond_to?(:types) ? type.types.first : type
              type_to_json_schema_internal(first_type, visited, definitions)
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
            base_schema = type_to_json_schema_internal(non_nil_types.first, visited, definitions)
            if base_schema[:type].is_a?(String)
              # Convert single type to array with null
              { type: [base_schema[:type], "null"] }.merge(base_schema.except(:type))
            else
              # For complex schemas, use anyOf to allow null
              { anyOf: [base_schema, { type: "null" }] }
            end
          elsif non_nil_types.size == 1
            # Non-nilable single type union (shouldn't happen in practice)
            type_to_json_schema_internal(non_nil_types.first, visited, definitions)
          elsif non_nil_types.size > 1
            # Handle complex unions with anyOf (oneOf not supported by Anthropic strict mode)
            base_schema = {
              anyOf: non_nil_types.map { |t| type_to_json_schema_internal(t, visited, definitions) },
              description: "Union of multiple types"
            }
            if is_nilable
              # Add null as an option for complex nilable unions
              base_schema[:anyOf] << { type: "null" }
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

      # Generate JSON schema for custom T::Struct classes
      # For backward compatibility, this returns just the schema hash
      sig { params(struct_class: T.class_of(T::Struct), visited: T.nilable(T::Set[T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def self.generate_struct_schema(struct_class, visited = nil)
        visited ||= Set.new
        generate_struct_schema_internal(struct_class, visited, {})
      end

      # Generate JSON schema with $defs tracking
      # Returns a SchemaResult with schema and accumulated definitions
      sig { params(struct_class: T.class_of(T::Struct), visited: T.nilable(T::Set[T.untyped]), definitions: T.nilable(T::Hash[String, T::Hash[Symbol, T.untyped]])).returns(SchemaResult) }
      def self.generate_struct_schema_with_defs(struct_class, visited = nil, definitions = nil)
        visited ||= Set.new
        definitions ||= {}
        schema = generate_struct_schema_internal(struct_class, visited, definitions)
        SchemaResult.new(schema: schema, definitions: definitions)
      end

      # Internal implementation that tracks definitions for $defs
      sig { params(struct_class: T.class_of(T::Struct), visited: T::Set[T.untyped], definitions: T::Hash[String, T::Hash[Symbol, T.untyped]]).returns(T::Hash[Symbol, T.untyped]) }
      def self.generate_struct_schema_internal(struct_class, visited, definitions)
        return { type: "string", description: "Struct (schema introspection not available)" } unless struct_class.respond_to?(:props)

        struct_name = struct_class.name || "Struct#{format('%x', struct_class.object_id)}"
        simple_name = struct_name.split('::').last || struct_name

        # Add this struct to visited set to detect recursion
        visited.add(struct_class)

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
          const: simple_name  # Use the simple class name
        }
        required << "_type"

        # Get field descriptions if the struct supports them (via DSPy::Ext::StructDescriptions)
        field_descs = struct_class.respond_to?(:field_descriptions) ? struct_class.field_descriptions : {}

        struct_class.props.each do |prop_name, prop_info|
          prop_type = prop_info[:type_object] || prop_info[:type]
          prop_schema = type_to_json_schema_internal(prop_type, visited, definitions)

          # Add field description if available
          if field_descs[prop_name]
            prop_schema[:description] = field_descs[prop_name]
          end

          properties[prop_name] = prop_schema

          # A field is required if it's not fully optional
          # fully_optional is true for nilable prop fields
          # immutable const fields are required unless nilable
          unless prop_info[:fully_optional]
            required << prop_name.to_s
          end
        end

        # Remove this struct from visited set after processing
        visited.delete(struct_class)

        schema = {
          type: "object",
          properties: properties,
          required: required,
          description: "#{struct_name} struct",
          additionalProperties: false
        }

        # Add this struct's schema to definitions for $defs
        # This allows recursive references to be resolved
        definitions[simple_name] = schema

        schema
      end

      private

      # Extensions to Hash for Rails-like except method if not available
      # This ensures compatibility with the original code
      unless Hash.method_defined?(:except)
        Hash.class_eval do
          def except(*keys)
            dup.tap do |hash|
              keys.each { |key| hash.delete(key) }
            end
          end
        end
      end
    end
  end
end
