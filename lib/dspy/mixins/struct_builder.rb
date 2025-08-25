# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Mixins
    # Shared module for building enhanced structs with input/output properties
    module StructBuilder
      extend T::Sig

      private

      # Builds a new struct class with properties from multiple sources
      sig { params(property_sources: T::Hash[Symbol, T::Hash[Symbol, T.untyped]], additional_fields: T::Hash[Symbol, T.untyped]).returns(T.class_of(T::Struct)) }
      def build_enhanced_struct(property_sources, additional_fields = {})
        # Capture self to access methods from within the class block
        builder = self
        
        Class.new(T::Struct) do
          extend T::Sig
          
          # Add properties from each source
          property_sources.each do |_source_name, props|
            props.each do |name, prop|
              type = builder.send(:extract_type_from_prop, prop)
              options = builder.send(:extract_options_from_prop, prop)
              
              if options[:default]
                const name, type, default: options[:default]
              elsif options[:factory]
                const name, type, factory: options[:factory]
              else
                const name, type
              end
            end
          end
          
          # Add additional fields specific to the enhanced struct
          additional_fields.each do |name, field_config|
            type = builder.send(:extract_type_from_prop, field_config)
            options = builder.send(:extract_options_from_prop, field_config)
            
            if options[:default]
              const name, type, default: options[:default]
            elsif options[:factory]
              const name, type, factory: options[:factory]
            else
              const name, type
            end
          end
          
          include StructSerialization
        end
      end

      # Builds properties from a props hash (from T::Struct.props)
      sig { params(props: T::Hash[Symbol, T.untyped]).void }
      def build_properties_from_hash(props)
        props.each { |name, prop| build_single_property(name, prop) }
      end

      # Builds a single property with type and options
      sig { params(name: Symbol, prop: T.untyped).void }
      def build_single_property(name, prop)
        type = extract_type_from_prop(prop)
        options = extract_options_from_prop(prop)
        
        if options[:default]
          const name, type, default: options[:default]
        elsif options[:factory]
          const name, type, factory: options[:factory]
        else
          const name, type
        end
      end

      # Extracts type from property configuration
      sig { params(prop: T.untyped).returns(T.untyped) }
      def extract_type_from_prop(prop)
        case prop
        when Hash
          # Prefer type_object for nilable types, fallback to type
          prop[:type_object] || prop[:type]
        when Array
          # Handle [Type, description] format
          prop.first
        else
          prop
        end
      end

      # Extracts options from property configuration
      sig { params(prop: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def extract_options_from_prop(prop)
        case prop
        when Hash
          # Preserve important flags like fully_optional for nilable types
          extracted = prop.except(:type, :type_object, :accessor_key, :sensitivity, :redaction, :setter_proc, :value_validate_proc, :serialized_form, :need_nil_read_check, :immutable, :pii, :extra)
          
          # Handle default values properly
          if prop[:default]
            extracted[:default] = prop[:default]
          elsif prop[:fully_optional]
            # For fully optional fields (nilable), set default to nil
            extracted[:default] = nil
          end
          
          extracted
        else
          {}
        end
      end
    end

    # Module for adding serialization capabilities to enhanced structs
    module StructSerialization
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        hash = input_values_hash
        hash.merge(output_properties_hash)
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def input_values_hash
        if instance_variable_defined?(:@input_values)
          instance_variable_get(:@input_values) || {}
        else
          {}
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def output_properties_hash
        self.class.props.keys.each_with_object({}) do |key, hash|
          hash[key] = send(key)
        end
      end
    end
  end
end