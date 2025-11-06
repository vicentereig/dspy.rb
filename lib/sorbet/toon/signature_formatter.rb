# frozen_string_literal: true

require 'sorbet-runtime'

module Sorbet
  module Toon
    module SignatureFormatter
      module_function

      def describe_signature(signature_class, role)
        struct_class = struct_for(signature_class, role)
        return "No #{role} fields defined." unless struct_class

        descriptors = field_descriptors(signature_class, role)
        describe_struct(struct_class, descriptors)
      end

      def struct_for(signature_class, role)
        return nil unless signature_class

        case role
        when :input
          signature_class.input_struct_class if signature_class.respond_to?(:input_struct_class)
        else
          signature_class.output_struct_class if signature_class.respond_to?(:output_struct_class)
        end
      end
      private_class_method :struct_for

      def field_descriptors(signature_class, role)
        return {} unless signature_class

        case role
        when :input
          signature_class.respond_to?(:input_field_descriptors) ? signature_class.input_field_descriptors || {} : {}
        else
          signature_class.respond_to?(:output_field_descriptors) ? signature_class.output_field_descriptors || {} : {}
        end
      end
      private_class_method :field_descriptors

      def describe_struct(struct_class, descriptors)
        lines = []

        struct_class.props.each do |prop_name, prop_info|
          descriptor = descriptors[prop_name]
          type_object = descriptor&.type || prop_info[:type_object] || prop_info[:type]
          type_info = describe_type(type_object)
          optional = descriptor&.has_default || prop_info[:fully_optional]

          line = "- #{prop_name}"
          type_label = type_info[:label]
          line << " (#{type_label}"
          line << ', optional' if optional
          line << ')'
          if descriptor&.description
            line << " — #{descriptor.description}"
          end

          lines << line

          if type_info[:tabular_columns]
            lines << "    • Tabular columns: #{type_info[:tabular_columns].join(', ')}"
          end
        end

        return "No fields defined." if lines.empty?

        lines.join("\n")
      end
      private_class_method :describe_struct

      def describe_type(type)
        case type
        when T::Types::TypedArray
          inner = describe_type(type.type)
          {
            label: "Array<#{inner[:label]}>",
            tabular_columns: inner[:tabular_columns]
          }
        when T::Types::TypedSet
          inner = describe_type(type.type)
          {
            label: "Set<#{inner[:label]}>"
          }
        when T::Types::TypedHash
          key = describe_type(type.keys)
          value = describe_type(type.values)
          {
            label: "Hash<#{key[:label]} => #{value[:label]}>"
          }
        when T::Types::Union
          members = type.types.reject { |member| nil_type?(member) }
          labels = members.map { |member| describe_type(member)[:label] }.uniq
          { label: labels.join(' | ') }
        when T::Private::Types::TypeAlias
          describe_type(type.aliased_type)
        when T::Types::Simple
          describe_class(type.raw_type)
        when Class
          describe_class(type)
        else
          { label: type_label_from_object(type) }
        end
      end
      private_class_method :describe_type

      def describe_class(klass)
        return { label: 'nil' } if klass.nil?

        if struct_class?(klass)
          {
            label: klass.name ? klass.name.split('::').last : 'Struct',
            tabular_columns: klass.props.keys.map(&:to_s)
          }
        elsif enum_class?(klass)
          values = klass.respond_to?(:values) ? klass.values.map(&:serialize).join(', ') : ''
          { label: values.empty? ? klass.name || 'Enum' : "Enum<#{values}>" }
        else
          { label: primitive_label(klass) }
        end
      end
      private_class_method :describe_class

      def primitive_label(klass)
        case klass.name
        when 'String' then 'String'
        when 'Integer' then 'Integer'
        when 'Float' then 'Float'
        when 'TrueClass', 'FalseClass' then 'Boolean'
        when 'Numeric' then 'Number'
        when 'Date' then 'Date'
        when 'DateTime', 'Time' then 'DateTime'
        else
          klass.name || klass.to_s
        end
      end
      private_class_method :primitive_label

      def type_label_from_object(type)
        if type.respond_to?(:name)
          type.name
        else
          type.to_s
        end
      end
      private_class_method :type_label_from_object

      def struct_class?(klass)
        klass.is_a?(Class) && klass < T::Struct
      rescue StandardError
        false
      end
      private_class_method :struct_class?

      def enum_class?(klass)
        klass.is_a?(Class) && klass < T::Enum
      rescue StandardError
        false
      end
      private_class_method :enum_class?

      def nil_type?(type)
        (type.is_a?(T::Types::Simple) && type.raw_type == NilClass) ||
          type == T::Utils.coerce(NilClass)
      rescue StandardError
        false
      end
      private_class_method :nil_type?
    end
  end
end
