54 # typed: strict
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
        when ->(type) { union_type?(type) }
          coerce_union_value(value, prop_type)
        when ->(type) { array_type?(type) }
          coerce_array_value(value, prop_type)
        when ->(type) { hash_type?(type) }
          coerce_hash_value(value, prop_type)
        when ->(type) { type == String || simple_type_match?(type, String) }
          coerce_to_string(value)
        when ->(type) { enum_type?(type) }
          coerce_enum_value(value, prop_type)
        when ->(type) { type == Float || simple_type_match?(type, Float) }
          value.to_f
        when ->(type) { type == Integer || simple_type_match?(type, Integer) }
          value.to_i
        when ->(type) { type == Date || simple_type_match?(type, Date) }
          coerce_date_value(value)
        when ->(type) { type == DateTime || simple_type_match?(type, DateTime) }
          coerce_datetime_value(value)
        when ->(type) { type == Time || simple_type_match?(type, Time) }
          coerce_time_value(value)
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

      # Checks if a type is a hash type
      sig { params(type: T.untyped).returns(T::Boolean) }
      def hash_type?(type)
        type.is_a?(T::Types::TypedHash)
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

      # Checks if a type is a union type (T.any)
      sig { params(type: T.untyped).returns(T::Boolean) }
      def union_type?(type)
        type.is_a?(T::Types::Union) && !is_nilable_type?(type)
      end

      # Checks if a type is nilable (contains NilClass)
      sig { params(type: T.untyped).returns(T::Boolean) }
      def is_nilable_type?(type)
        type.is_a?(T::Types::Union) && type.types.any? { |t| t == T::Utils.coerce(NilClass) }
      end

      # Checks if a type is a scalar (primitives that don't need special serialization)
      sig { params(type_object: T.untyped).returns(T::Boolean) }
      def scalar_type?(type_object)
        case type_object
        when T::Types::Simple
          scalar_classes = [String, Integer, Float, Numeric, TrueClass, FalseClass]
          scalar_classes.any? { |klass| type_object.raw_type == klass || type_object.raw_type <= klass }
        when T::Types::Union
          # Union is scalar if all its types are scalars
          type_object.types.all? { |t| scalar_type?(t) }
        else
          false
        end
      end

      # Checks if a type is structured (arrays, hashes, structs that need type preservation)
      sig { params(type_object: T.untyped).returns(T::Boolean) }
      def structured_type?(type_object)
        return true if type_object.is_a?(T::Types::TypedArray)
        return true if type_object.is_a?(T::Types::TypedHash)

        if type_object.is_a?(T::Types::Simple)
          raw_type = type_object.raw_type
          return true if raw_type.respond_to?(:<=) && raw_type <= T::Struct
        end

        # For union types (like T.nilable(T::Array[...])), check if any non-nil type is structured
        if type_object.is_a?(T::Types::Union)
          non_nil_types = type_object.types.reject { |t| t.is_a?(T::Types::Simple) && t.raw_type == NilClass }
          return non_nil_types.any? { |t| structured_type?(t) }
        end

        false
      end

      # Checks if a type is String or compatible with String (e.g., T.any(String, ...) or T.nilable(String))
      sig { params(type_object: T.untyped).returns(T::Boolean) }
      def string_type?(type_object)
        case type_object
        when T::Types::Simple
          type_object.raw_type == String
        when T::Types::Union
          # Check if any of the union types is String
          type_object.types.any? { |t| t.is_a?(T::Types::Simple) && t.raw_type == String }
        else
          false
        end
      end

      # Get a readable type name from a Sorbet type object
      sig { params(type_object: T.untyped).returns(String) }
      def type_name(type_object)
        case type_object
        when T::Types::TypedArray
          element_type = type_object.type
          "T::Array[#{type_name(element_type)}]"
        when T::Types::TypedHash
          "T::Hash"
        when T::Types::Simple
          type_object.raw_type.to_s
        when T::Types::Union
          types_str = type_object.types.map { |t| type_name(t) }.join(', ')
          "T.any(#{types_str})"
        else
          type_object.to_s
        end
      end

      # Returns an appropriate default value for a given Sorbet type
      # This is used when max iterations is reached without a successful completion
      sig { params(type_object: T.untyped).returns(T.untyped) }
      def default_value_for_type(type_object)
        # Handle TypedArray (T::Array[...])
        return [] if type_object.is_a?(T::Types::TypedArray)

        # Handle TypedHash (T::Hash[...])
        return {} if type_object.is_a?(T::Types::TypedHash)

        # Handle simple types
        case type_object
        when T::Types::Simple
          raw_type = type_object.raw_type
          case raw_type.to_s
          when 'String' then ''
          when 'Integer' then 0
          when 'Float' then 0.0
          when 'TrueClass', 'FalseClass' then false
          else
            # For T::Struct types, return nil as fallback
            nil
          end
        when T::Types::Union
          # For unions, return nil (assuming it's nilable) or first non-nil default
          nil
        else
          # Default fallback for unknown types
          nil
        end
      end

      # Coerces an array value, converting each element as needed
      sig { params(value: T.untyped, prop_type: T.untyped).returns(T.untyped) }
      def coerce_array_value(value, prop_type)
        return value unless value.is_a?(Array)
        return value unless prop_type.is_a?(T::Types::TypedArray)

        element_type = prop_type.type
        value.map { |element| coerce_value_to_type(element, element_type) }
      end

      # Coerces a hash value, converting keys and values as needed
      sig { params(value: T.untyped, prop_type: T.untyped).returns(T.untyped) }
      def coerce_hash_value(value, prop_type)
        return value unless value.is_a?(Hash)
        return value unless prop_type.is_a?(T::Types::TypedHash)
        
        key_type = prop_type.keys
        value_type = prop_type.values
        
        # Convert string keys to enum instances if key_type is an enum
        result = if enum_type?(key_type)
          enum_class = extract_enum_class(key_type)
          value.transform_keys { |k| enum_class.deserialize(k.to_s) }
        else
          # For non-enum keys, coerce them to the expected type
          value.transform_keys { |k| coerce_value_to_type(k, key_type) }
        end
        
        # Coerce values to their expected types
        result.transform_values { |v| coerce_value_to_type(v, value_type) }
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
        
        # Get struct properties to understand what fields are expected
        struct_props = struct_class.props
        
        # Remove the _type field that DSPy adds for discriminating structs,
        # but only if it's NOT a legitimate field in the struct definition
        if !struct_props.key?(:_type) && symbolized_hash.key?(:_type)
          symbolized_hash = symbolized_hash.except(:_type)
        end
        
        # Recursively coerce nested struct fields
        coerced_hash = symbolized_hash.map do |key, val|
          prop_info = struct_props[key]
          if prop_info && prop_info[:type]
            coerced_value = coerce_value_to_type(val, prop_info[:type])
            [key, coerced_value]
          else
            [key, val]
          end
        end.to_h
        
        # Create the struct instance
        struct_class.new(**coerced_hash)
      rescue ArgumentError => e
        # If struct creation fails, return the original value
        DSPy.logger.debug("Failed to coerce to struct #{struct_class}: #{e.message}")
        value
      end

      # Coerces a union value by using _type discriminator
      sig { params(value: T.untyped, union_type: T.untyped).returns(T.untyped) }
      def coerce_union_value(value, union_type)
        return value unless value.is_a?(Hash)

        # Check for _type discriminator field
        type_name = value[:_type] || value["_type"]
        return value unless type_name

        # Find matching struct type in the union
        union_type.types.each do |type|
          next if type == T::Utils.coerce(NilClass)

          if type.is_a?(T::Types::Simple) && type.raw_type < T::Struct
            struct_name = type.raw_type.name.split('::').last
            if struct_name == type_name
              # Convert string keys to symbols and remove _type
              symbolized_hash = value.transform_keys(&:to_sym)
              symbolized_hash.delete(:_type)

              # Coerce struct field values based on their types
              struct_class = type.raw_type
              struct_props = struct_class.props

              # ONLY include fields that exist in the struct
              coerced_hash = {}
              struct_props.each_key do |key|
                if symbolized_hash.key?(key)
                  prop_type = struct_props[key][:type_object] || struct_props[key][:type]
                  coerced_hash[key] = coerce_value_to_type(symbolized_hash[key], prop_type)
                end
              end

              # Create the struct instance with coerced values
              return struct_class.new(**coerced_hash)
            end
          end
        end

        # If no matching type found, return original value
        value
      rescue ArgumentError => e
        # If struct creation fails, return the original value
        DSPy.logger.debug("Failed to coerce union type: #{e.message}")
        value
      end

      # Coerces a date value from string using ISO 8601 format
      sig { params(value: T.untyped).returns(T.nilable(Date)) }
      def coerce_date_value(value)
        return value if value.is_a?(Date)
        return nil if value.nil? || value.to_s.strip.empty?
        
        # Support ISO 8601 format (YYYY-MM-DD) like ActiveRecord
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        # Return nil for invalid dates rather than crashing
        DSPy.logger.debug("Failed to coerce to Date: #{value}")
        nil
      end

      # Coerces a datetime value from string using ISO 8601 format with timezone
      sig { params(value: T.untyped).returns(T.nilable(DateTime)) }
      def coerce_datetime_value(value)
        return value if value.is_a?(DateTime)
        return nil if value.nil? || value.to_s.strip.empty?
        
        # Parse ISO 8601 with timezone like ActiveRecord
        # Formats: 2024-01-15T10:30:45Z, 2024-01-15T10:30:45+00:00, 2024-01-15 10:30:45
        DateTime.parse(value.to_s)
      rescue ArgumentError, TypeError
        DSPy.logger.debug("Failed to coerce to DateTime: #{value}")
        nil
      end

      # Coerces a time value from string, converting to UTC like ActiveRecord
      sig { params(value: T.untyped).returns(T.nilable(Time)) }
      def coerce_time_value(value)
        return value if value.is_a?(Time)
        return nil if value.nil? || value.to_s.strip.empty?
        
        # Parse and convert to UTC (like ActiveRecord with time_zone_aware_attributes)
        # This ensures consistent timezone handling across the system
        Time.parse(value.to_s).utc
      rescue ArgumentError, TypeError
        DSPy.logger.debug("Failed to coerce to Time: #{value}")
        nil
      end

      # Coerces a value to String with strict type checking
      # Only allows String (passthrough) and Symbol (to_s) - rejects other types
      sig { params(value: T.untyped).returns(String) }
      def coerce_to_string(value)
        case value
        when String then value
        when Symbol then value.to_s
        else
          raise TypeError, "Cannot coerce #{value.class} to String - expected String or Symbol"
        end
      end

      # Coerces a value to an enum, handling both strings and existing enum instances
      sig { params(value: T.untyped, prop_type: T.untyped).returns(T.untyped) }
      def coerce_enum_value(value, prop_type)
        enum_class = extract_enum_class(prop_type)
        
        # If value is already an instance of the enum class, return it as-is
        return value if value.is_a?(enum_class)
        
        # Otherwise, try to deserialize from string
        enum_class.deserialize(value.to_s)
      rescue ArgumentError, KeyError => e
        DSPy.logger.debug("Failed to coerce to enum #{enum_class}: #{e.message}")
        value
      end
    end
  end
end
