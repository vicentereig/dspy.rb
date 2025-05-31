# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  class SorbetSignature
    extend T::Sig
    
    class << self
      extend T::Sig
      
      sig { returns(T.nilable(String)) }
      attr_reader :desc
      
      sig { returns(T.nilable(T.class_of(T::Struct))) }
      attr_reader :input_struct_class
      
      sig { returns(T.nilable(T.class_of(T::Struct))) }
      attr_reader :output_struct_class
      
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
        @input_struct_class = Class.new(T::Struct) do
          extend T::Sig
          class_eval(&block)
        end
      end
      
      sig { params(block: T.proc.void).void }
      def output(&block)
        @output_struct_class = Class.new(T::Struct) do
          extend T::Sig
          class_eval(&block)
        end
      end
      
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def input_json_schema
        return {} unless @input_struct_class
        
        properties = {}
        required = []
        
        @input_struct_class.props.each do |name, prop|
          properties[name] = type_to_json_schema(prop[:type])
          required << name.to_s unless prop.key?(:default)
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
        
        @output_struct_class.props.each do |name, prop|
          properties[name] = type_to_json_schema(prop[:type])
          required << name.to_s unless prop.key?(:default)
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
