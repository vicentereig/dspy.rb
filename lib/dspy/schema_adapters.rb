# frozen_string_literal: true

require 'sorbet-schema'

module DSPy
  # Schema adapters for integrating sorbet-schema with T::Struct
  module SchemaAdapters
    # Handles sorbet-schema integration for serialization/deserialization
    class SorbetSchemaAdapter
      extend T::Sig
      
      # Serialize a hash to a T::Struct using sorbet-schema
      #
      # @param struct_class [Class] T::Struct class 
      # @param hash_data [Hash] Data to serialize
      # @return [T::Struct] Validated struct instance
      sig { params(struct_class: T.class_of(T::Struct), hash_data: T::Hash[T.untyped, T.untyped]).returns(T::Struct) }
      def self.from_hash(struct_class, hash_data)
        # TODO: Implement using sorbet-schema
        # For now, fall back to direct struct creation
        struct_class.new(**hash_data.transform_keys(&:to_sym))
      end
      
      # Deserialize a T::Struct to a hash using sorbet-schema
      #
      # @param struct_instance [T::Struct] Struct instance to serialize
      # @return [Hash] Serialized hash
      sig { params(struct_instance: T::Struct).returns(T::Hash[T.untyped, T.untyped]) }
      def self.to_hash(struct_instance)
        # TODO: Implement using sorbet-schema
        # For now, fall back to simple serialization
        result = {}
        struct_instance.class.props.each do |name, _prop_info|
          result[name] = struct_instance.send(name)
        end
        result
      end
      
      # Validate data against a T::Struct schema using sorbet-schema
      #
      # @param struct_class [Class] T::Struct class
      # @param hash_data [Hash] Data to validate
      # @return [Array] [success_boolean, result_or_errors]
      sig { params(struct_class: T.class_of(T::Struct), hash_data: T::Hash[T.untyped, T.untyped]).returns([T::Boolean, T.untyped]) }
      def self.validate(struct_class, hash_data)
        begin
          result = from_hash(struct_class, hash_data)
          [true, result]
        rescue StandardError => e
          [false, [e.message]]
        end
      end
    end
  end
end
