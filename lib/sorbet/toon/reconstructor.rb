# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'

module Sorbet
  module Toon
    module Reconstructor
      class << self
        def reconstruct(value, signature: nil, struct_class: nil, role: :output)
          target_class = struct_class || resolve_struct_class(signature, role)
          return value unless target_class

          convert_hash_to_struct(value, target_class)
        end

        private

        def resolve_struct_class(signature, role)
          return nil unless signature

          case role
          when :input
            signature.input_struct_class
          else
            signature.output_struct_class
          end
        end

        def convert_hash_to_struct(hash, struct_class)
          return hash unless hash.is_a?(Hash)

          attributes = {}

          struct_class.props.each do |prop_name, prop_info|
            raw_value = fetch_value(hash, prop_name)
            next if raw_value.nil?

            type_object = prop_info[:type_object] || T::Utils.coerce(prop_info[:type])
            attributes[prop_name] = convert_value(raw_value, type_object)
          end

          struct_class.new(**attributes)
        rescue StandardError
          hash
        end

        def fetch_value(hash, prop_name)
          key = prop_name.to_s
          return hash[key] if hash.key?(key)
          return hash[prop_name] if hash.key?(prop_name)

          sym_key = key.to_sym
          hash[sym_key] if hash.key?(sym_key)
        end

        def convert_value(value, type_object)
          return nil if value.nil?
          return value unless type_object

          case type_object
          when T::Types::TypedArray
            convert_typed_array(value, type_object)
          when T::Types::TypedSet
            convert_typed_set(value, type_object)
          when T::Types::TypedHash
            convert_typed_hash(value, type_object)
          when T::Types::Simple
            convert_simple(value, type_object)
          when T::Types::Union
            convert_union(value, type_object)
          else
            value
          end
        end

        def convert_simple(value, simple_type)
          raw = simple_type.raw_type
          return convert_hash_to_struct(value, raw) if struct_class?(raw) && value.is_a?(Hash)
          return deserialize_enum(raw, value) if enum_class?(raw) && !value.is_a?(raw)

          value
        end

        def convert_typed_array(value, typed_array)
          return value unless value.is_a?(Array)

          value.map { |element| convert_value(element, typed_array.type) }
        end

        def convert_typed_set(value, typed_set)
          return value unless value.is_a?(Array)

          Set.new(value.map { |element| convert_value(element, typed_set.type) })
        end

        def convert_typed_hash(value, typed_hash)
          return value unless value.is_a?(Hash)

          value.each_with_object({}) do |(key, val), memo|
            converted_key = coerce_hash_key(key, typed_hash.keys)
            memo[converted_key] = convert_value(val, typed_hash.values)
          end
        end

        def convert_union(value, union_type)
          return nil if value.nil? && union_type.types.any? { |member| nil_type?(member) }

          if value.is_a?(Hash)
            explicit_type = union_struct_from_type_field(value, union_type)
            return convert_value(value, explicit_type) if explicit_type
          end

          union_type.types.each do |member|
            next if nil_type?(member)

            converted = convert_value(value, member)
            return converted unless converted.equal?(value)
          end

          value
        end

        def union_struct_from_type_field(hash, union_type)
          type_name = hash['_type'] || hash[:_type]
          return nil unless type_name

          union_type.types.find do |member|
            struct_type?(member) && struct_name(member.raw_type) == type_name
          end
        end

        def struct_type?(type)
          type.is_a?(T::Types::Simple) && struct_class?(type.raw_type)
        end

        def nil_type?(type)
          type.is_a?(T::Types::Simple) && type.raw_type == NilClass
        end

        def struct_class?(klass)
          klass.is_a?(Class) && klass < T::Struct
        rescue StandardError
          false
        end

        def enum_class?(klass)
          klass.is_a?(Class) && klass < T::Enum
        rescue StandardError
          false
        end

        def deserialize_enum(enum_class, value)
          return value if value.is_a?(enum_class)
          return enum_class.deserialize(value) if enum_class.respond_to?(:deserialize)

          enum_class.values.find { |member| member.serialize == value } || value
        end

        def coerce_hash_key(key, key_type)
          return key unless key_type.is_a?(T::Types::Simple)

          case key_type.raw_type
          when Symbol
            key.to_sym
          when Integer
            key.to_i
          when Float
            key.to_f
          else
            key.to_s
          end
        end

        def struct_name(klass)
          klass.name&.split('::')&.last
        end
      end
    end
  end
end
