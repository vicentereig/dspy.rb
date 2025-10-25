# typed: strict
# frozen_string_literal: true

require 'date'
require 'json'
require 'set'
require 'sorbet-runtime'

module DSPy
  module TypeSystem
    module SorbetJsonSchema
      extend T::Sig
      extend T::Helpers

      sig { params(type: T.untyped, visited: T.nilable(T::Set[T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def self.type_to_json_schema(type, visited = nil)
        visited ||= Set.new

        if type == T::Boolean
          return { type: "boolean" }
        end

        if type.is_a?(T::Private::Types::TypeAlias)
          return self.type_to_json_schema(type.aliased_type, visited)
        end

        if type.is_a?(Class)
          if type < T::Enum
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
            if visited.include?(type)
              {
                "$ref" => "#/definitions/#{type.name.split('::').last}",
                description: "Recursive reference to #{type.name}"
              }
            else
              self.generate_struct_schema(type, visited)
            end
          else
            { type: "string" }
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
            if type.raw_type < T::Enum
              values = type.raw_type.values.map(&:serialize)
              { type: "string", enum: values }
            elsif type.raw_type < T::Struct
              if visited.include?(type.raw_type)
                {
                  "$ref" => "#/definitions/#{type.raw_type.name.split('::').last}",
                  description: "Recursive reference to #{type.raw_type.name}"
                }
              else
                generate_struct_schema(type.raw_type, visited)
              end
            else
              { type: "string" }
            end
          end
        elsif type.is_a?(T::Types::TypedArray)
          {
            type: "array",
            items: self.type_to_json_schema(type.type, visited)
          }
        elsif type.is_a?(T::Types::TypedHash)
          key_schema = self.type_to_json_schema(type.keys, visited)
          value_schema = self.type_to_json_schema(type.values, visited)

          {
            type: "object",
            propertyNames: key_schema,
            additionalProperties: value_schema,
            description: "A mapping where keys are #{key_schema[:type]}s and values are #{value_schema[:description] || value_schema[:type]}s"
          }
        elsif type.is_a?(T::Types::FixedHash)
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
          has_nil = type.respond_to?(:types) && type.types.any? do |t|
            (t.respond_to?(:raw_type) && t.raw_type == NilClass) ||
            (t.respond_to?(:name) && t.name == "NilClass")
          end

          if has_nil
            non_nil_type = type.types.find do |t|
              !(t.respond_to?(:raw_type) && t.raw_type == NilClass) &&
              !(t.respond_to?(:name) && t.name == "NilClass")
            end

            if non_nil_type
              base_schema = self.type_to_json_schema(non_nil_type, visited)
              if base_schema[:type].is_a?(String)
                { type: [base_schema[:type], "null"] }.merge(base_schema.except(:type))
              else
                { anyOf: [base_schema, { type: "null" }] }
              end
            else
              { type: "string" }
            end
          else
            if type.respond_to?(:types) && type.types.length > 1
              {
                oneOf: type.types.map { |t| self.type_to_json_schema(t, visited) },
                description: "Union of multiple types"
              }
            else
              first_type = type.respond_to?(:types) ? type.types.first : type
              self.type_to_json_schema(first_type, visited)
            end
          end
        elsif type.is_a?(T::Types::Union)
          is_nilable = type.types.any? { |t| t == T::Utils.coerce(NilClass) }
          non_nil_types = type.types.reject { |t| t == T::Utils.coerce(NilClass) }

          if non_nil_types.size == 2 && is_nilable
            true_class_type = non_nil_types.find { |t| t.respond_to?(:raw_type) && t.raw_type == TrueClass }
            false_class_type = non_nil_types.find { |t| t.respond_to?(:raw_type) && t.raw_type == FalseClass }

            if true_class_type && false_class_type
              return { type: ["boolean", "null"] }
            end
          end

          if non_nil_types.size == 1 && is_nilable
            base_schema = self.type_to_json_schema(non_nil_types.first, visited)
            if base_schema[:type].is_a?(String)
              { type: [base_schema[:type], "null"] }.merge(base_schema.except(:type))
            else
              { anyOf: [base_schema, { type: "null" }] }
            end
          elsif non_nil_types.size == 1
            self.type_to_json_schema(non_nil_types.first, visited)
          elsif non_nil_types.size > 1
            base_schema = {
              oneOf: non_nil_types.map { |t| self.type_to_json_schema(t, visited) },
              description: "Union of multiple types"
            }
            if is_nilable
              base_schema[:oneOf] << { type: "null" }
            end
            base_schema
          else
            { type: "string" }
          end
        elsif type.is_a?(T::Types::TypedSet)
          {
            type: "array",
            uniqueItems: true,
            items: self.type_to_json_schema(type.type, visited)
          }
        elsif type.is_a?(T::Types::TypedClass)
          { type: "string", description: "Class reference: #{type.type}" }
        elsif type.is_a?(T::Types::FixedArray)
          {
            type: "array",
            items: type.types.map { |t| self.type_to_json_schema(t, visited) },
            minItems: type.types.length,
            maxItems: type.types.length
          }
        else
          { type: "string" }
        end
      end

      sig { params(struct_class: T.class_of(T::Struct), visited: T::Set[T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def self.generate_struct_schema(struct_class, visited)
        visited.add(struct_class)

        properties = {}
        required = []
        definitions = {}

        struct_class.props.each do |name, prop_def|
          prop_type = prop_def.type
          next unless prop_type

          schema = self.type_to_json_schema(prop_type, visited)

          if schema["$ref"]
            ref_name = schema["$ref"].split('/').last
            referenced_class = prop_type.respond_to?(:raw_type) ? prop_type.raw_type : prop_type
            unless definitions[ref_name]
              definitions[ref_name] = self.generate_struct_schema(referenced_class, visited)
            end
          end

          properties[name] = schema
          required << name.to_s unless prop_def.optional
        end

        schema = {
          type: "object",
          properties: properties,
          required: required,
          additionalProperties: false
        }

        schema[:definitions] = definitions unless definitions.empty?

        schema
      ensure
        visited.delete(struct_class)
      end
    end
  end
end
