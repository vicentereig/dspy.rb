# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'

require_relative 'errors'

module Sorbet
  module Toon
    module Normalizer
      class << self
        def normalize(value, signature: nil, role: :output, include_type_metadata: false)
          context = {
            signature: signature,
            role: role,
            include_type_metadata: include_type_metadata
          }

          normalize_value(value, context)
        end

        private

        def normalize_value(value, context)
          return nil if value.nil?

          case value
          when T::Struct
            normalize_struct(value, context)
          when T::Enum
            value.serialize
          when Array
            value.map { |item| normalize_value(item, context) }
          when Set
            value.map { |item| normalize_value(item, context) }
          when Hash
            normalize_hash(value, context)
          else
            normalize_primitive(value)
          end
        end

        def normalize_struct(struct, context)
          result = {}
          if context[:include_type_metadata]
            result['_type'] = type_label_for(struct.class)
          end

          struct.class.props.each do |prop_name, prop_info|
            prop_value = struct.send(prop_name)
            next if prop_value.nil? && prop_info[:fully_optional]

            result[prop_name.to_s] = normalize_value(prop_value, context)
          end

          result
        end

        def normalize_hash(hash, context)
          hash.each_with_object({}) do |(key, value), memo|
            memo[key_to_string(key)] = normalize_value(value, context)
          end
        end

        def normalize_primitive(value)
          case value
          when Float
            return nil unless value.finite?
            return 0.0 if value.zero?

            value
          else
            if value.respond_to?(:serialize)
              value.serialize
            else
              value
            end
          end
        end

        def key_to_string(key)
          key.to_s
        end

        def type_label_for(klass)
          return 'AnonymousStruct' if klass.name.nil? || klass.name.empty?

          klass.name.split('::').last
        end
      end
    end
  end
end
