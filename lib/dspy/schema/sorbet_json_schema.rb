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

      # Convert a Sorbet type to JSON Schema format
      sig { params(type: T.untyped, visited: T.nilable(T::Set[T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def self.type_to_json_schema(type, visited = nil)
        visited ||= Set.new
        
        # Handle T::Boolean type alias first
        if type == T::Boolean
          return { type: "boolean" }
        end

        # Handle type aliases by resolving to their underlying type
        if type.is_a?(T::Private::Types::TypeAlias)
          return self.type_to_json_schema(type.aliased_type, visited)
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
              {
                "$ref" => "#/definitions/#{type.name.split('::').last}",
                description: "Recursive reference to #{type.name}"
              }
            else
              self.generate_struct_schema(type, visited)
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
                {
                  "$ref" => "#/definitions/#{type.raw_type.name.split('::').last}",
                  description: "Recursive reference to #{type.raw_type.name}"
                }
              else
                generate_struct_schema(type.raw_type, visited)
              end
            else
              { type: "string" }  # Default fallback
            end
          end
        elsif type.is_a?(T::Types::TypedArray)
          # Handle arrays properly with nested item type
          {
            type: "array",
            items: self.type_to_json_schema(type.type, visited)
          }
        elsif type.is_a?(T::Types::TypedHash)
          # Handle hashes as objects with additionalProperties
          # TypedHash has keys and values methods to access its key and value types
          key_schema = self.type_to_json_schema(type.keys, visited)
          value_schema = self.type_to_json_schema(type.values, visited)
          
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
            properties[key] = self.type_to_json_schema(value_type, visited)
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
              base_schema = self.type_to_json_schema(non_nil_type, visited)
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
                oneOf: type.types.map { |t| self.type_to_json_schema(t, visited) },
                description: "Union of multiple types"
              }
            else
              # Single type or fallback
              first_type = type.respond_to?(:types) ? type.types.first : type
              self.type_to_json_schema(first_type, visited)
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
            base_schema = self.type_to_json_schema(non_nil_types.first, visited)
            if base_schema[:type].is_a?(String)
              # Convert single type to array with null
              { type: [base_schema[:type], "null"] }.merge(base_schema.except(:type))
            else
              # For complex schemas, use anyOf to allow null
              { anyOf: [base_schema, { type: "null" }] }
            end
          elsif non_nil_types.size == 1
            # Non-nilable single type union (shouldn't happen in practice)
            self.type_to_json_schema(non_nil_types.first, visited)
          elsif non_nil_types.size > 1
            # Handle complex unions with oneOf for better JSON schema compliance
            base_schema = {
              oneOf: non_nil_types.map { |t| self.type_to_json_schema(t, visited) },
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

      # Generate JSON schema for custom T::Struct classes
      sig { params(struct_class: T.class_of(T::Struct), visited: T.nilable(T::Set[T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def self.generate_struct_schema(struct_class, visited = nil)
        visited ||= Set.new
        
        return { type: "string", description: "Struct (schema introspection not available)" } unless struct_class.respond_to?(:props)

        # Add this struct to visited set to detect recursion
        visited.add(struct_class)

        properties = {}
        required = []

        # Check if struct already has a _type field
        if struct_class.props.key?(:_type)
          raise DSPy::ValidationError, "_type field conflict: #{struct_class.name} already has a _type field defined. " \
                                       "DSPy uses _type for automatic type detection in union types."
        end

        struct_name = struct_class.name || "Struct#{format('%x', struct_class.object_id)}"
        simple_name = struct_name.split('::').last || struct_name

        # Add automatic _type field for type detection
        properties[:_type] = {
          type: "string",
          const: simple_name  # Use the simple class name
        }
        required << "_type"

        struct_class.props.each do |prop_name, prop_info|
          prop_type = prop_info[:type_object] || prop_info[:type]
          properties[prop_name] = self.type_to_json_schema(prop_type, visited)
          
          # A field is required if it's not fully optional
          # fully_optional is true for nilable prop fields
          # immutable const fields are required unless nilable
          unless prop_info[:fully_optional]
            required << prop_name.to_s
          end
        end

        # Remove this struct from visited set after processing
        visited.delete(struct_class)

        {
          type: "object",
          properties: properties,
          required: required,
          description: "#{struct_name} struct"
        }
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
