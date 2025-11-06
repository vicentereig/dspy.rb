# frozen_string_literal: true

require 'date'
require 'set'
require 'bigdecimal'

module Sorbet
  module Toon
    module Encode
      module Normalize
        module_function

        def normalize(value)
          case value
          when nil
            nil
          when String, TrueClass, FalseClass
            value
          when Integer
            normalize_integer(value)
          when Float
            normalize_float(value)
          when Rational
            normalize_float(value.to_f)
          when BigDecimal
            normalize_float(value.to_f)
          when Time, DateTime
            value.iso8601
          when Date
            value.iso8601
          when Array
            value.map { |item| normalize(item) }
          when Set
            value.map { |item| normalize(item) }
          when Hash
            normalize_hash(value)
          else
            try_custom_normalize(value)
          end
        end

        def json_primitive?(value)
          value.nil? || value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
        end

        def json_array?(value)
          value.is_a?(Array)
        end

        def json_object?(value)
          value.is_a?(Hash)
        end

        def array_of_primitives?(array)
          array.all? { |item| json_primitive?(item) }
        end

        def array_of_arrays?(array)
          array.all? { |item| json_array?(item) }
        end

        def array_of_objects?(array)
          array.all? { |item| json_object?(item) }
        end

        def is_plain_object?(value)
          value.is_a?(Hash)
        end

        def normalize_integer(value)
          value
        end
        private_class_method :normalize_integer

        def normalize_float(value)
          return 0 if value.zero?
          return nil unless value.finite?
          value
        end
        private_class_method :normalize_float

        def normalize_hash(hash)
          result = {}
          hash.each do |key, val|
            result[key.to_s] = normalize(val)
          end
          result
        end
        private_class_method :normalize_hash

        def try_custom_normalize(value)
          if value.respond_to?(:to_ary)
            normalize(value.to_ary)
          elsif value.respond_to?(:to_hash)
            normalize_hash(value.to_hash)
          elsif value.respond_to?(:to_h)
            normalize_hash(value.to_h)
          elsif value.respond_to?(:to_s)
            value.to_s
          else
            nil
          end
        end
        private_class_method :try_custom_normalize
      end
    end
  end
end
