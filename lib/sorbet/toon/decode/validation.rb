# frozen_string_literal: true

require_relative '../constants'
require_relative '../errors'

module Sorbet
  module Toon
    module Decode
      module Validation
        module_function

        def assert_expected_count(actual, expected, item_type, strict:)
          return unless strict
          return if actual == expected

          raise RangeError, "Expected #{expected} #{item_type}, but got #{actual}"
        end

        def validate_no_extra_list_items(cursor, item_depth, expected_count)
          return if cursor.at_end?

          next_line = cursor.peek
          if next_line && next_line.depth == item_depth && next_line.content.start_with?(Constants::LIST_ITEM_PREFIX)
            raise RangeError, "Expected #{expected_count} list array items, but found more"
          end
        end

        def validate_no_extra_tabular_rows(cursor, row_depth, header)
          return if cursor.at_end?

          next_line = cursor.peek
          if next_line &&
             next_line.depth == row_depth &&
             !next_line.content.start_with?(Constants::LIST_ITEM_PREFIX) &&
             data_row?(next_line.content, header[:delimiter])
            raise RangeError, "Expected #{header[:length]} tabular rows, but found more"
          end
        end

        def validate_no_blank_lines_in_range(start_line, end_line, blank_lines, strict:, context:)
          return unless strict

          blanks_in_range = blank_lines.select do |blank|
            blank.line_number > start_line && blank.line_number < end_line
          end

          return if blanks_in_range.empty?

          raise Sorbet::Toon::DecodeError,
                "Line #{blanks_in_range.first.line_number}: Blank lines inside #{context} are not allowed in strict mode"
        end

        def data_row?(content, delimiter)
          colon_pos = content.index(Constants::COLON)
          delimiter_pos = content.index(delimiter)

          return true if colon_pos.nil?
          return true if delimiter_pos && delimiter_pos < colon_pos

          false
        end
        private_class_method :data_row?
      end
    end
  end
end
