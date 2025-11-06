# frozen_string_literal: true

require 'bigdecimal'

require_relative '../constants'
require_relative '../shared/validation'
require_relative '../shared/literal_utils'
require_relative '../shared/string_utils'

module Sorbet
  module Toon
    module Encode
      module Primitives
        module_function

        def encode_primitive(value, delimiter = Constants::DEFAULT_DELIMITER)
          case value
          when nil
            Constants::NULL_LITERAL
          when TrueClass, FalseClass
            value.to_s
          when Integer
            value.to_s
          when Float
            format_float(value)
          when Numeric
            value.to_s
          else
            encode_string_literal(value.to_s, delimiter)
          end
        end

        def encode_string_literal(value, delimiter = Constants::DEFAULT_DELIMITER)
          if Shared::Validation.safe_unquoted?(value, delimiter)
            value
          else
            "\"#{Shared::StringUtils.escape_string(value)}\""
          end
        end

        def encode_key(key)
          if Shared::Validation.valid_unquoted_key?(key)
            key
          else
            "\"#{Shared::StringUtils.escape_string(key)}\""
          end
        end

        def encode_and_join_primitives(values, delimiter = Constants::DEFAULT_DELIMITER)
          values.map { |v| encode_primitive(v, delimiter) }.join(delimiter)
        end

        def format_header(length, key: nil, fields: nil, delimiter: Constants::DEFAULT_DELIMITER, length_marker: false)
          header = +''
          header << encode_key(key) if key

          header << '['
          header << Constants::HASH if length_marker == Constants::HASH
          header << length.to_i.to_s
          header << delimiter if delimiter != Constants::DEFAULT_DELIMITER
          header << ']'

          if fields && !fields.empty?
            encoded_fields = fields.map { |field| encode_key(field) }
            header << '{'
            header << encoded_fields.join(delimiter)
            header << '}'
          end

          header << Constants::COLON
          header
        end

        def format_float(value)
          return '0' if value.zero?

          decimal = BigDecimal(value.to_s)
          str = decimal.to_s('F')
          str = str.sub(/\.0+\z/, '')
          str.sub(/(\.\d*?)0+\z/, '\1')
        end
        private_class_method :format_float
      end
    end
  end
end
