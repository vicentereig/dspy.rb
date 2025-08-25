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

      # First, add all the fields from the schema with defaults if not provided
      @_schema.props.each do |field_name, prop_info|
        # Skip if attribute was provided
        next if attributes.key?(field_name)
        
        # Apply default value if available
        default_value = prop_info[:default]
        if !default_value.nil?
          if default_value.is_a?(Proc)
            converted[field_name] = default_value.call
          else
            converted[field_name] = default_value
          end
        elsif prop_info[:fully_optional]
          # For optional fields without defaults, set to nil
          converted[field_name] = nil
        end
      end

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
          
          # Handle nil values explicitly
          if value.nil?
            # Check if there's a default value
            default_value = prop_info[:default]
            if !default_value.nil?
              converted[key] = default_value.is_a?(Proc) ? default_value.call : default_value
            else
              converted[key] = nil
            end
          elsif is_enum_type?(prop_type) && value.is_a?(String)
            # Convert string to enum
            enum_class = extract_enum_class(prop_type)
            converted[key] = enum_class.deserialize(value)
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
      
      case type
      when T::Types::Simple
        # Handle regular enum types
        begin
          raw_type = type.raw_type
          return false unless raw_type.is_a?(Class)
          result = raw_type < T::Enum
          return result == true # Force conversion to boolean
        rescue StandardError
          return false
        end
      when T::Private::Types::SimplePairUnion, T::Types::Union
        # Handle T.nilable enum types
        # Find the non-nil type and check if it's an enum
        non_nil_types = if type.respond_to?(:types)
          type.types.reject { |t| t.respond_to?(:raw_type) && t.raw_type == NilClass }
        else
          []
        end
        
        # For nilable types, we expect exactly one non-nil type
        return false unless non_nil_types.size == 1
        
        non_nil_type = non_nil_types.first
        return is_enum_type?(non_nil_type) # Recursively check
      else
        return false
      end
    end

    sig { params(type: T.untyped).returns(T.untyped) }
    def extract_enum_class(type)
      case type
      when T::Types::Simple
        # Regular enum type
        type.raw_type
      when T::Private::Types::SimplePairUnion, T::Types::Union
        # Nilable enum type - find the non-nil type
        non_nil_types = if type.respond_to?(:types)
          type.types.reject { |t| t.respond_to?(:raw_type) && t.raw_type == NilClass }
        else
          []
        end
        
        if non_nil_types.size == 1
          extract_enum_class(non_nil_types.first)
        else
          raise ArgumentError, "Unable to extract enum class from complex union type: #{type.inspect}"
        end
      else
        raise ArgumentError, "Not an enum type: #{type.inspect}"
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

      # Filter to only include fields defined in the struct
      struct_props = struct_class.props
      filtered_hash = {}
      
      value.each do |k, v|
        # Skip _type field and any fields not defined in the struct
        next if k == :_type || k == "_type"
        next unless struct_props.key?(k.to_sym)
        
        filtered_hash[k.to_sym] = v
      end
      
      # Convert the filtered Hash to the appropriate struct type
      struct_class.new(**filtered_hash)
    rescue TypeError, ArgumentError
      # If conversion fails, return the original value
      value
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def needs_struct_conversion?(type)
      case type
      when T::Types::Simple
        # Use !! to convert nil result of < comparison to false
        begin
          !!(type.raw_type < T::Struct)
        rescue
          false
        end
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
        struct_class = type.raw_type
        # Convert nested hash values to structs if needed
        converted_hash = {}
        
        # First, apply defaults for missing fields
        struct_class.props.each do |field_name, prop_info|
          next if value.key?(field_name)
          
          default_value = prop_info[:default]
          if !default_value.nil?
            converted_hash[field_name] = default_value.is_a?(Proc) ? default_value.call : default_value
          end
        end
        
        value.each do |k, v|
          # Skip _type field from being added to the struct (it's not a real field)
          next if k == :_type || k == "_type"
          
          prop_info = struct_class.props[k]
          if prop_info
            prop_type = prop_info[:type_object] || prop_info[:type]
            if v.is_a?(String) && is_enum_type?(prop_type)
              # Convert string to enum
              converted_hash[k] = prop_type.raw_type.deserialize(v)
            elsif v.is_a?(Hash) && needs_struct_conversion?(prop_type)
              converted_hash[k] = convert_to_struct(v, prop_type)
            elsif v.is_a?(Array) && needs_array_conversion?(prop_type)
              converted_hash[k] = convert_array_elements(v, prop_type)
            else
              converted_hash[k] = v
            end
          end
          # Skip fields not defined in the struct
        end
        begin
          struct_class.new(**converted_hash)
        rescue
          # Return original value if conversion fails
          value
        end
      when T::Types::Union
        # Check if value has a _type field for automatic type detection
        type_name = value[:_type] || value["_type"]
        
        if type_name
          # Use _type field to determine which struct to instantiate
          type.types.each do |t|
            next if t == T::Utils.coerce(NilClass)
            
            if t.is_a?(T::Types::Simple) && t.raw_type < T::Struct
              struct_name = t.raw_type.name.split('::').last
              if struct_name == type_name
                return convert_to_struct(value, t)
              end
            end
          end
          
          # If no matching type found, raise an error
          raise DSPy::DeserializationError, "Unknown type: #{type_name}. Expected one of: #{type.types.map { |t| t.is_a?(T::Types::Simple) && t.raw_type < T::Struct ? t.raw_type.name.split('::').last : nil }.compact.join(', ')}"
        end
        
        # Fallback to trying each type if no _type field
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
        needs_struct_conversion?(type.type) || is_enum_type?(type.type)
      when T::Types::Union
        # Handle nilable arrays: T.nilable(T::Array[...])
        if is_nilable_type?(type)
          # Find the non-nil type in the union
          non_nil_type = type.types.find { |t| t != T::Utils.coerce(NilClass) }
          # Recursively check if it needs array conversion
          needs_array_conversion?(non_nil_type)
        else
          false
        end
      else
        false
      end
    end

    sig { params(array: T::Array[T.untyped], type: T.untyped).returns(T::Array[T.untyped]) }
    def convert_array_elements(array, type)
      # Handle nilable arrays: T.nilable(T::Array[...])
      if type.is_a?(T::Types::Union) && is_nilable_type?(type)
        # Find the non-nil type (should be TypedArray)
        array_type = type.types.find { |t| t != T::Utils.coerce(NilClass) }
        return convert_array_elements(array, array_type)
      end
      
      return array unless type.is_a?(T::Types::TypedArray)

      element_type = type.type
      # Check if elements need any conversion (structs or enums)
      return array unless needs_struct_conversion?(element_type) || is_enum_type?(element_type)

      array.map do |element|
        if element.is_a?(Hash)
          # For union types, we need to infer which struct type based on the hash structure
          if is_union_type?(element_type) && !is_nilable_type?(element_type)
            convert_hash_to_union_struct(element, element_type)
          else
            convert_to_struct(element, element_type)
          end
        elsif element.is_a?(String) && is_enum_type?(element_type)
          # Convert string to enum
          element_type.raw_type.deserialize(element)
        else
          element
        end
      end
    end

    sig { params(hash: T::Hash[Symbol, T.untyped], union_type: T::Types::Union).returns(T.untyped) }
    def convert_hash_to_union_struct(hash, union_type)
      # First check if hash has a _type field for automatic type detection
      type_name = hash[:_type] || hash["_type"]
      
      if type_name
        # Use _type field to determine which struct to instantiate
        union_type.types.each do |type|
          next if type == T::Utils.coerce(NilClass)
          
          if type.is_a?(T::Types::Simple) && type.raw_type < T::Struct
            struct_name = type.raw_type.name.split('::').last
            if struct_name == type_name
              return convert_to_struct(hash, type)
            end
          end
        end
        
        # If no matching type found, raise an error
        raise DSPy::DeserializationError, "Unknown type: #{type_name}. Expected one of: #{union_type.types.map { |t| t.is_a?(T::Types::Simple) && t.raw_type < T::Struct ? t.raw_type.name.split('::').last : nil }.compact.join(', ')}"
      end
      
      # Fallback: Try to match the hash structure to one of the union types
      union_type.types.each do |type|
        next if type == T::Utils.coerce(NilClass)
        
        if type.is_a?(T::Types::Simple) && type.raw_type < T::Struct
          struct_class = type.raw_type
          
          # Check if all required fields of this struct are present in the hash
          required_fields = struct_class.props.reject { |_, info| info[:fully_optional] }.keys
          if required_fields.all? { |field| hash.key?(field) }
            begin
              # Need to convert nested values too
              converted_hash = {}
              hash.each do |k, v|
                # Skip _type field
                next if k == :_type || k == "_type"
                
                prop_info = struct_class.props[k]
                if prop_info
                  prop_type = prop_info[:type_object] || prop_info[:type]
                  if v.is_a?(String) && is_enum_type?(prop_type)
                    converted_hash[k] = prop_type.raw_type.deserialize(v)
                  elsif v.is_a?(Hash) && needs_struct_conversion?(prop_type)
                    converted_hash[k] = convert_to_struct(v, prop_type)
                  elsif v.is_a?(Array) && needs_array_conversion?(prop_type)
                    converted_hash[k] = convert_array_elements(v, prop_type)
                  else
                    converted_hash[k] = v
                  end
                end
                # Skip fields not defined in the struct
              end
              return struct_class.new(**converted_hash)
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
      # If we have a schema, include all fields from it in the dynamic struct
      all_fields = if @_schema
        # Merge schema fields with provided attributes
        schema_fields = @_schema.props.keys.to_h { |k| [k, nil] }
        schema_fields.merge(attributes)
      else
        attributes
      end
      
      Class.new(T::Struct) do
        const :_prediction_marker, T::Boolean, default: true
        
        all_fields.each do |key, value|
          # Use T.untyped for dynamic properties
          const key, T.untyped
        end
      end
    end
  end
end