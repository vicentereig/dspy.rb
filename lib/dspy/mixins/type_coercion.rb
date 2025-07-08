# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Mixins
    # Shared module for type coercion logic across DSPy modules
    module TypeCoercion
      extend T::Sig

      private

      # Coerces output attributes to match their expected types
      sig { params(output_attributes: T::Hash[Symbol, T.untyped], output_props: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def coerce_output_attributes(output_attributes, output_props)
        output_attributes.map do |key, value|
          prop_type = output_props[key]&.dig(:type)
          coerced_value = coerce_value_to_type(value, prop_type)
          [key, coerced_value]
        end.to_h
      end

      # Coerces a single value to match its expected type
      sig { params(value: T.untyped, prop_type: T.untyped).returns(T.untyped) }
      def coerce_value_to_type(value, prop_type)
        return value unless prop_type
        
        # If value is nil, return it as-is for nilable types
        return value if value.nil?

        case prop_type
        when ->(type) { array_type?(type) }
          coerce_array_value(value, prop_type)
        when ->(type) { enum_type?(type) }
          extract_enum_class(prop_type).deserialize(value)
        when Float, ->(type) { simple_type_match?(type, Float) }
          value.to_f
        when Integer, ->(type) { simple_type_match?(type, Integer) }
          value.to_i
        when ->(type) { struct_type?(type) }
          coerce_struct_value(value, prop_type)
        else
          value
        end
      end

      # Checks if a type is an enum type
      sig { params(type: T.untyped).returns(T::Boolean) }
      def enum_type?(type)
        return false unless type
        
        if type.is_a?(Class)
          !!(type < T::Enum)
        elsif type.is_a?(T::Types::Simple)
          !!(type.raw_type < T::Enum)
        else
          false
        end
      rescue StandardError
        false
      end

      # Extracts the enum class from a type
      sig { params(prop_type: T.untyped).returns(T.class_of(T::Enum)) }
      def extract_enum_class(prop_type)
        if prop_type.is_a?(Class) && prop_type < T::Enum
          prop_type
        elsif prop_type.is_a?(T::Types::Simple) && prop_type.raw_type < T::Enum
          prop_type.raw_type
        else
          T.cast(prop_type, T.class_of(T::Enum))
        end
      end

      # Checks if a type matches a simple type (like Float, Integer)
      sig { params(type: T.untyped, target_type: T.untyped).returns(T::Boolean) }
      def simple_type_match?(type, target_type)
        type.is_a?(T::Types::Simple) && type.raw_type == target_type
      end

      # Checks if a type is an array type
      sig { params(type: T.untyped).returns(T::Boolean) }
      def array_type?(type)
        return false unless type.is_a?(T::Types::TypedArray)
        true
      end

      # Checks if a type is a struct type
      sig { params(type: T.untyped).returns(T::Boolean) }
      def struct_type?(type)
        if type.is_a?(Class)
          !!(type < T::Struct)
        elsif type.is_a?(T::Types::Simple)
          !!(type.raw_type < T::Struct)
        else
          false
        end
      rescue StandardError
        false
      end

      # Coerces an array value, converting each element as needed
      sig { params(value: T.untyped, prop_type: T.untyped).returns(T.untyped) }
      def coerce_array_value(value, prop_type)
        return value unless value.is_a?(Array)
        return value unless prop_type.is_a?(T::Types::TypedArray)

        element_type = prop_type.type
        value.map { |element| coerce_value_to_type(element, element_type) }
      end

      # Coerces a struct value from a hash
      sig { params(value: T.untyped, prop_type: T.untyped).returns(T.untyped) }
      def coerce_struct_value(value, prop_type)
        return value unless value.is_a?(Hash)

        struct_class = if prop_type.is_a?(Class)
                         prop_type
                       elsif prop_type.is_a?(T::Types::Simple)
                         prop_type.raw_type
                       else
                         return value
                       end

        # Convert string keys to symbols
        symbolized_hash = value.transform_keys(&:to_sym)
        
        # Create the struct instance
        struct_class.new(**symbolized_hash)
      rescue ArgumentError => e
        # If struct creation fails, return the original value
        DSPy.logger.debug("Failed to coerce to struct #{struct_class}: #{e.message}")
        value
      end
    end
  end
end