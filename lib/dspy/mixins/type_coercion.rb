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
        when ->(type) { enum_type?(type) }
          extract_enum_class(prop_type).deserialize(value)
        when Float, ->(type) { simple_type_match?(type, Float) }
          value.to_f
        when Integer, ->(type) { simple_type_match?(type, Integer) }
          value.to_i
        else
          value
        end
      end

      # Checks if a type is an enum type
      sig { params(type: T.untyped).returns(T::Boolean) }
      def enum_type?(type)
        (type.is_a?(Class) && type < T::Enum) ||
          (type.is_a?(T::Types::Simple) && type.raw_type < T::Enum)
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
    end
  end
end