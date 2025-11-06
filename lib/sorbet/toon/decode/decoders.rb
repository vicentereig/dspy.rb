# frozen_string_literal: true

require_relative '../constants'
require_relative '../shared/string_utils'
require_relative '../shared/literal_utils'
require_relative 'scanner'
require_relative 'parser'
require_relative 'validation'

module Sorbet
  module Toon
    module Decode
      module Decoders
        module_function

        def decode_value_from_lines(cursor, **options)
          first = cursor.peek
          raise ReferenceError, 'No content to decode' unless first

          if Parser.array_header_after_hyphen?(first.content)
            header_info = Parser.parse_array_header_line(first.content, Constants::DEFAULT_DELIMITER)
            if header_info
              cursor.advance
              return decode_array_from_header(header_info[:header], header_info[:inline_values], cursor, 0, options)
            end
          end

          if cursor.length == 1 && !key_value_line?(first)
            return Parser.parse_primitive_token(first.content.strip)
          end

          decode_object(cursor, 0, options)
        end

        def key_value_line?(line)
          content = line.content

          if content.start_with?(Constants::DOUBLE_QUOTE)
            closing = Shared::StringUtils.find_closing_quote(content, 0)
            return false if closing == -1

            return content[closing + 1..]&.include?(Constants::COLON)
          end

          content.include?(Constants::COLON)
        end
        private_class_method :key_value_line?

        def decode_object(cursor, base_depth, options)
          result = {}
          computed_depth = nil

          until cursor.at_end?
            line = cursor.peek
            break unless line
            break if line.depth < base_depth

            computed_depth ||= line.depth
            break unless line.depth == computed_depth

            key, value = decode_key_value_pair(line, cursor, computed_depth, options)
            result[key] = value
          end

          result
        end

        def decode_key_value_pair(line, cursor, base_depth, options)
          cursor.advance
          key_value = decode_key_value(line.content, cursor, base_depth, options)
          [key_value[:key], key_value[:value]]
        end

        def decode_key_value(content, cursor, base_depth, options)
          array_header = Parser.parse_array_header_line(content, Constants::DEFAULT_DELIMITER)
          if array_header && array_header[:header][:key]
            value = decode_array_from_header(array_header[:header], array_header[:inline_values], cursor, base_depth, options)
            return { key: array_header[:header][:key], value: value, follow_depth: base_depth + 1 }
          end

          key_info = Parser.parse_key_token(content, 0)
          key = key_info[:key]
          rest = content[key_info[:end]..]&.strip

          if rest.nil? || rest.empty?
            next_line = cursor.peek
            if next_line && next_line.depth > base_depth
              nested = decode_object(cursor, base_depth + 1, options)
              return { key: key, value: nested, follow_depth: base_depth + 1 }
            end
            return { key: key, value: {}, follow_depth: base_depth + 1 }
          end

          value = Parser.parse_primitive_token(rest)
          { key: key, value: value, follow_depth: base_depth + 1 }
        end

        def decode_array_from_header(header, inline_values, cursor, base_depth, options)
          if inline_values
            values = Parser.parse_delimited_values(inline_values, header[:delimiter])
            primitives = Parser.map_row_values_to_primitives(values)
            Validation.assert_expected_count(primitives.length, header[:length], 'inline array items', strict: options[:strict])
            return primitives
          end

          if header[:fields] && !header[:fields].empty?
            return decode_tabular_array(header, cursor, base_depth, options)
          end

          decode_list_array(header, cursor, base_depth, options)
        end

        def decode_list_array(header, cursor, base_depth, options)
          items = []
          item_depth = base_depth + 1
          start_line = cursor.current&.line_number || 0
          end_line = start_line

          while !cursor.at_end? && items.length < header[:length]
            line = cursor.peek
            break unless line
            break if line.depth < item_depth

            if line.content == Constants::LIST_ITEM_MARKER || line.content.start_with?(Constants::LIST_ITEM_PREFIX)
              item = decode_list_item(cursor, item_depth, options)
              items << item
              end_line = cursor.current&.line_number || end_line
            else
              break
            end
          end

          Validation.assert_expected_count(items.length, header[:length], 'list array items', strict: options[:strict])
          Validation.validate_no_blank_lines_in_range(start_line, end_line, cursor.blank_lines, strict: options[:strict], context: 'list array')
          Validation.validate_no_extra_list_items(cursor, item_depth, header[:length])
          items
        end

        def decode_tabular_array(header, cursor, base_depth, options)
          rows = []
          row_depth = base_depth + 1
          start_line = cursor.current&.line_number || 0
          end_line = start_line

          while cursor.has_more_at_depth?(row_depth) && rows.length < header[:length]
            line = cursor.peek
            break unless line
            break if line.depth != row_depth
            break if line.content.start_with?(Constants::LIST_ITEM_PREFIX)

            values = Parser.parse_delimited_values(line.content, header[:delimiter])
            primitives = Parser.map_row_values_to_primitives(values)
            rows << primitives
            cursor.advance
            end_line = line.line_number
          end

          Validation.assert_expected_count(rows.length, header[:length], 'tabular rows', strict: options[:strict])
          Validation.validate_no_blank_lines_in_range(start_line, end_line, cursor.blank_lines, strict: options[:strict], context: 'tabular array')
          Validation.validate_no_extra_tabular_rows(cursor, row_depth, header)

          rows.map do |primitives|
            Hash[header[:fields].zip(primitives)]
          end
        end

        def decode_list_item(cursor, base_depth, options)
          line = cursor.next
          raise ReferenceError, 'Expected list item' unless line

          return {} if line.content == Constants::LIST_ITEM_MARKER

          unless line.content.start_with?(Constants::LIST_ITEM_PREFIX)
            raise SyntaxError, "Expected list item to start with \"#{Constants::LIST_ITEM_PREFIX}\""
          end

          after_hyphen = line.content[Constants::LIST_ITEM_PREFIX.length..] || ''
          return {} if after_hyphen.strip.empty?

          if Parser.array_header_after_hyphen?(after_hyphen)
            header_info = Parser.parse_array_header_line(after_hyphen, Constants::DEFAULT_DELIMITER)
            if header_info
              return decode_array_from_header(header_info[:header], header_info[:inline_values], cursor, base_depth, options)
            end
          end

          if Parser.object_first_field_after_hyphen?(after_hyphen)
            return decode_object_from_list_item(line, cursor, base_depth, options)
          end

          Parser.parse_primitive_token(after_hyphen)
        end

        def decode_object_from_list_item(first_line, cursor, base_depth, options)
          after_hyphen = first_line.content[Constants::LIST_ITEM_PREFIX.length..] || ''
          key_value = decode_key_value(after_hyphen, cursor, base_depth, options)

          obj = { key_value[:key] => key_value[:value] }
          follow_depth = key_value[:follow_depth]

          until cursor.at_end?
            line = cursor.peek
            break unless line
            break if line.depth < follow_depth

            if line.depth == follow_depth && !line.content.start_with?(Constants::LIST_ITEM_PREFIX)
              k, v = decode_key_value_pair(line, cursor, follow_depth, options)
              obj[k] = v
            else
              break
            end
          end

          obj
        end
      end
    end
  end
end
