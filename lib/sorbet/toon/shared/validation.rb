# frozen_string_literal: true

require_relative '../constants'
require_relative 'literal_utils'

module Sorbet
  module Toon
    module Shared
      module Validation
        module_function

        UNQUOTED_KEY_REGEX = /\A[A-Z_][\w.]*\z/i.freeze
        NUMERIC_LIKE_REGEX = /\A-?\d+(?:\.\d+)?(?:e[+-]?\d+)?\z/i.freeze
        LEADING_ZERO_REGEX = /\A0\d+\z/.freeze

        def valid_unquoted_key?(key)
          UNQUOTED_KEY_REGEX.match?(key)
        end

        def safe_unquoted?(value, delimiter = Constants::COMMA)
          return false if value.nil? || value.empty?
          return false if value != value.strip
          return false if LiteralUtils.boolean_or_null_literal?(value) || numeric_like?(value)
          return false if value.include?(Constants::COLON)
          return false if value.include?(Constants::DOUBLE_QUOTE) || value.include?(Constants::BACKSLASH)
          return false if value.match?(/[{}\[\]]/)
          return false if value.match?(/[\n\r\t]/)
          return false if value.include?(delimiter)
          return false if value.start_with?(Constants::LIST_ITEM_MARKER)

          true
        end

        def numeric_like?(value)
          NUMERIC_LIKE_REGEX.match?(value) || LEADING_ZERO_REGEX.match?(value)
        end
        private_class_method :numeric_like?
      end
    end
  end
end
