# typed: strict
# frozen_string_literal: true

module DSPy
  class Prediction
    extend T::Sig
    extend T::Generic
    include T::Props
    include T::Props::Serializable

    # The underlying struct that holds the actual data
    sig { returns(T.untyped) }
    attr_reader :_struct

    # Schema information for type conversion
    sig { returns(T.nilable(T::Class[T::Struct])) }
    attr_reader :_schema

    sig do
      params(
        schema: T.nilable(T.any(T::Class[T::Struct], T::Types::Base)),
        attributes: T.untyped
      ).void
    end
    def initialize(schema = nil, **attributes)
      @_schema = extract_struct_class(schema)
      
      # Convert attributes based on schema if provided
      converted_attributes = if @_schema
        convert_attributes_with_schema(attributes)
      else
        attributes
      end

      # Create a dynamic struct to hold the data
      struct_class = create_dynamic_struct(converted_attributes)
      @_struct = struct_class.new(**converted_attributes)
    end

    # Delegate all method calls to the underlying struct
    sig { params(method: Symbol, args: T.untyped, block: T.untyped).returns(T.untyped) }
    def method_missing(method, *args, &block)
      if @_struct.respond_to?(method)
        @_struct.send(method, *args, &block)
      else
        super
      end
    end

    sig { params(method: Symbol, include_all: T::Boolean).returns(T::Boolean) }
    def respond_to_missing?(method, include_all = false)
      @_struct.respond_to?(method, include_all) || super
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      @_struct.to_h
    end

    private

    sig { params(schema: T.untyped).returns(T.nilable(T::Class[T::Struct])) }
    def extract_struct_class(schema)
      case schema
      when Class
        schema if schema < T::Struct
      when T::Types::Simple
        schema.raw_type if schema.raw_type < T::Struct
      else
        nil
      end
    end

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def convert_attributes_with_schema(attributes)
      return attributes unless @_schema

      converted = {}
      
      # Get discriminator mappings for T.any() fields
      discriminator_mappings = detect_discriminator_fields(@_schema)

      attributes.each do |key, value|
        prop_info = @_schema.props[key]
        
        if prop_info && discriminator_mappings[key]
          # This is a T.any() field with a discriminator
          discriminator_field, type_mapping = discriminator_mappings[key]
          discriminator_value = attributes[discriminator_field]
          prop_type = prop_info[:type_object] || prop_info[:type]
          
          converted[key] = convert_union_type(value, discriminator_value, type_mapping, prop_type)
        elsif prop_info
          prop_type = prop_info[:type_object] || prop_info[:type]
          if is_enum_type?(prop_type) && value.is_a?(String)
            # Convert string to enum
            converted[key] = prop_type.raw_type.deserialize(value)
          elsif value.is_a?(Hash) && needs_struct_conversion?(prop_type)
            # Regular struct field that needs conversion
            converted[key] = convert_to_struct(value, prop_type)
          elsif value.is_a?(Array) && needs_array_conversion?(prop_type)
            # Array field that might contain structs
            converted[key] = convert_array_elements(value, prop_type)
          else
            converted[key] = value
          end
        else
          converted[key] = value
        end
      end

      converted
    end

    sig { params(schema: T::Class[T::Struct]).returns(T::Hash[Symbol, [Symbol, T::Hash[String, T.untyped]]]) }
    def detect_discriminator_fields(schema)
      discriminator_mappings = {}
      props = schema.props.to_a

      props.each_with_index do |(prop_name, prop_info), index|
        prop_type = prop_info[:type_object] || prop_info[:type]
        next unless is_union_type?(prop_type)

        # Look for preceding String or Enum field as potential discriminator
        if index > 0
          prev_prop_name, prev_prop_info = props[index - 1]
          prev_prop_type = prev_prop_info[:type_object] || prev_prop_info[:type]
          if prev_prop_type && (is_string_type?(prev_prop_type) || is_enum_type?(prev_prop_type))
            # This String/Enum field might be a discriminator
            type_mapping = build_type_mapping_from_union(prop_type, prev_prop_type)
            discriminator_mappings[prop_name] = [prev_prop_name, type_mapping]
          end
        end
      end

      discriminator_mappings
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def is_union_type?(type)
      type.is_a?(T::Types::Union) && !is_nilable_type?(type)
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def is_nilable_type?(type)
      type.is_a?(T::Types::Union) && type.types.any? { |t| t == T::Utils.coerce(NilClass) }
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def is_string_type?(type)
      case type
      when T::Types::Simple
        type.raw_type == String
      else
        false
      end
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def is_enum_type?(type)
      return false if type.nil?
      return false unless type.is_a?(T::Types::Simple)
      
      begin
        raw_type = type.raw_type
        return false unless raw_type.is_a?(Class)
        result = raw_type < T::Enum
        return result == true # Force conversion to boolean
      rescue StandardError
        return false
      end
    end

    sig { params(union_type: T::Types::Union, discriminator_type: T.untyped).returns(T::Hash[String, T.untyped]) }
    def build_type_mapping_from_union(union_type, discriminator_type)
      mapping = {}
      
      if is_enum_type?(discriminator_type)
        # For enum discriminators, try to map enum values to struct types
        enum_class = discriminator_type.raw_type
        union_type.types.each do |type|
          next if type == T::Utils.coerce(NilClass)
          
          if type.is_a?(T::Types::Simple) && type.raw_type < T::Struct
            struct_class = type.raw_type
            struct_name = struct_class.name.split("::").last
            
            # Try to find matching enum value by name
            enum_class.values.each do |enum_value|
              enum_name = enum_value.instance_variable_get(:@const_name).to_s
              if enum_name == struct_name
                # Exact match
                mapping[enum_value.serialize] = struct_class
              elsif enum_name.downcase == struct_name.downcase
                # Case-insensitive match
                mapping[enum_value.serialize] = struct_class
              end
            end
            
            # Also add snake_case mapping as fallback
            discriminator_value = struct_name
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
            mapping[discriminator_value] = struct_class
          end
        end
      else
        # String discriminators use snake_case convention
        union_type.types.each do |type|
          next if type == T::Utils.coerce(NilClass)
          
          if type.is_a?(T::Types::Simple) && type.raw_type < T::Struct
            struct_class = type.raw_type
            # Convert class name to snake_case for discriminator value
            discriminator_value = struct_class.name
              .split("::").last
              .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              .gsub(/([a-z\d])([A-Z])/, '\1_\2')
              .downcase
            
            mapping[discriminator_value] = struct_class
          end
        end
      end

      mapping
    end

    sig do
      params(
        value: T.untyped,
        discriminator_value: T.untyped,
        type_mapping: T::Hash[String, T.untyped],
        union_type: T.untyped
      ).returns(T.untyped)
    end
    def convert_union_type(value, discriminator_value, type_mapping, union_type)
      return value unless value.is_a?(Hash)
      
      # Handle enum discriminators
      discriminator_str = case discriminator_value
      when T::Enum
        discriminator_value.serialize
      when String
        discriminator_value
      else
        return value
      end

      struct_class = type_mapping[discriminator_str]
      return value unless struct_class

      # Convert the Hash to the appropriate struct type
      struct_class.new(**value)
    rescue TypeError, ArgumentError
      # If conversion fails, return the original value
      value
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def needs_struct_conversion?(type)
      case type
      when T::Types::Simple
        type.raw_type < T::Struct
      when T::Types::Union
        # Check if any type in the union is a struct
        type.types.any? { |t| needs_struct_conversion?(t) }
      else
        false
      end
    end

    sig { params(value: T::Hash[Symbol, T.untyped], type: T.untyped).returns(T.untyped) }
    def convert_to_struct(value, type)
      case type
      when T::Types::Simple
        type.raw_type.new(**value)
      when T::Types::Union
        # For unions without discriminator, try each type
        type.types.each do |t|
          next if t == T::Utils.coerce(NilClass)
          
          begin
            return convert_to_struct(value, t) if needs_struct_conversion?(t)
          rescue TypeError, ArgumentError
            # Try next type
          end
        end
        value
      else
        value
      end
    rescue TypeError, ArgumentError
      value
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def needs_array_conversion?(type)
      case type
      when T::Types::TypedArray
        needs_struct_conversion?(type.type)
      else
        false
      end
    end

    sig { params(array: T::Array[T.untyped], type: T.untyped).returns(T::Array[T.untyped]) }
    def convert_array_elements(array, type)
      return array unless type.is_a?(T::Types::TypedArray)

      element_type = type.type
      return array unless needs_struct_conversion?(element_type)

      array.map do |element|
        if element.is_a?(Hash)
          # For union types, we need to infer which struct type based on the hash structure
          if is_union_type?(element_type) && !is_nilable_type?(element_type)
            convert_hash_to_union_struct(element, element_type)
          else
            convert_to_struct(element, element_type)
          end
        else
          element
        end
      end
    end

    sig { params(hash: T::Hash[Symbol, T.untyped], union_type: T::Types::Union).returns(T.untyped) }
    def convert_hash_to_union_struct(hash, union_type)
      # Try to match the hash structure to one of the union types
      union_type.types.each do |type|
        next if type == T::Utils.coerce(NilClass)
        
        if type.is_a?(T::Types::Simple) && type.raw_type < T::Struct
          struct_class = type.raw_type
          
          # Check if all required fields of this struct are present in the hash
          required_fields = struct_class.props.reject { |_, info| info[:fully_optional] }.keys
          if required_fields.all? { |field| hash.key?(field) }
            begin
              return struct_class.new(**hash)
            rescue TypeError, ArgumentError
              # This struct didn't match, try the next one
            end
          end
        end
      end
      
      # If no struct matched, return the original hash
      hash
    end

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Class[T::Struct]) }
    def create_dynamic_struct(attributes)
      Class.new(T::Struct) do
        const :_prediction_marker, T::Boolean, default: true
        
        attributes.each do |key, value|
          # Use T.untyped for dynamic properties
          const key, T.untyped
        end
      end
    end
  end
end