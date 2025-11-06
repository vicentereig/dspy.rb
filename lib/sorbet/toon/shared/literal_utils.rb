# frozen_string_literal: true

require_relative '../constants'

module Sorbet
  module Toon
    module Shared
      module LiteralUtils
        module_function

        def boolean_or_null_literal?(token)
          return false if token.nil?

          token == Constants::TRUE_LITERAL ||
            token == Constants::FALSE_LITERAL ||
            token == Constants::NULL_LITERAL
        end

        def numeric_literal?(token)
          return false if token.nil? || token.empty?

          # Reject numbers with leading zeros (except 0.x cases)
          if token.length > 1 && token.start_with?('0') && token[1] != '.'
            return false
          end

          numeric_value = Float(token)
          numeric_value.finite?
        rescue ArgumentError
          false
        end
      end
    end
  end
end
