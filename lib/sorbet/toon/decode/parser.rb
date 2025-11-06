# frozen_string_literal: true

require_relative '../constants'
require_relative '../shared/string_utils'
require_relative '../shared/validation'
require_relative '../shared/literal_utils'

module Sorbet
  module Toon
    module Decode
      module Parser
        module_function

        def parse_array_header_line(content, default_delimiter)
          trimmed = content.lstrip

          bracket_start = find_bracket_start(trimmed, content)
          return nil unless bracket_start

          bracket_end = content.index(Constants::CLOSE_BRACKET, bracket_start)
          return nil unless bracket_end

          colon_index = find_colon_after_brackets(content, bracket_end)
          return nil unless colon_index

          key = extract_key_from_header(content, bracket_start)

          bracket_content = content[(bracket_start + 1)...bracket_end]
          parsed_segment = parse_bracket_segment(bracket_content, default_delimiter)
          return nil unless parsed_segment

          fields = extract_fields(content, bracket_end, colon_index, parsed_segment[:delimiter])

          after_colon = content[(colon_index + 1)..]&.strip

          header = {
            key: key,
            length: parsed_segment[:length],
            delimiter: parsed_segment[:delimiter],
            fields: fields,
            has_length_marker: parsed_segment[:has_length_marker]
          }

          {
            header: header,
            inline_values: after_colon&.empty? ? nil : after_colon
          }
        end

        def parse_bracket_segment(segment, default_delimiter)
          content = segment
          has_length_marker = false

          if content.start_with?(Constants::HASH)
            has_length_marker = true
            content = content[1..]
          end

          delimiter = default_delimiter
          if content.end_with?(Constants::TAB)
            delimiter = Constants::TAB
            content = content[0...-1]
          elsif content.end_with?(Constants::PIPE)
            delimiter = Constants::PIPE
            content = content[0...-1]
          end

          length = Integer(content, exception: false)
          return nil if length.nil?

          {
            length: length,
            delimiter: delimiter,
            has_length_marker: has_length_marker
          }
        end

        def parse_delimited_values(input, delimiter)
          values = []
          current = +''
          in_quotes = false
          i = 0

          while i < input.length
            char = input[i]

            if char == Constants::BACKSLASH && in_quotes && (i + 1) < input.length
              current << char << input[i + 1]
              i += 2
              next
            end

            if char == Constants::DOUBLE_QUOTE
              in_quotes = !in_quotes
              current << char
              i += 1
              next
            end

            if char == delimiter && !in_quotes
              values << current.strip
              current = +''
              i += 1
              next
            end

            current << char
            i += 1
          end

          values << current.strip unless current.empty? && values.empty?
          values
        end

        def map_row_values_to_primitives(values)
          values.map { |token| parse_primitive_token(token) }
        end

        def parse_primitive_token(token)
          trimmed = token.strip
          return nil if trimmed.empty?

          if trimmed.start_with?(Constants::DOUBLE_QUOTE)
            if trimmed.length < 2 || trimmed[-1] != Constants::DOUBLE_QUOTE
              raise SyntaxError, "Unterminated string literal: #{trimmed}"
            end
            inner = trimmed[1...-1]
            return Shared::StringUtils.unescape_string(inner)
          end

          case trimmed
          when Constants::TRUE_LITERAL
            true
          when Constants::FALSE_LITERAL
            false
          when Constants::NULL_LITERAL
            nil
          else
            if Shared::LiteralUtils.numeric_literal?(trimmed)
              parsed = Float(trimmed)
              return 0 if parsed.zero?
              return parsed
            end
            trimmed
          end
        end

        def parse_key_token(content, start_index)
          if content[start_index] == Constants::DOUBLE_QUOTE
            closing = Shared::StringUtils.find_closing_quote(content, start_index)
            raise SyntaxError, 'Unterminated quoted key' if closing == -1

            key = Shared::StringUtils.unescape_string(content[(start_index + 1)...closing])
            rest_index = closing + 1
            colon_index = Shared::StringUtils.find_unquoted_char(content, Constants::COLON, rest_index)
            raise SyntaxError, 'Key must be followed by colon' if colon_index == -1
            return { key: key, end: colon_index + 1 }
          end

          colon_index = Shared::StringUtils.find_unquoted_char(content, Constants::COLON, start_index)
          raise SyntaxError, 'Key must be followed by colon' if colon_index == -1

          key = content[start_index...colon_index].strip
          { key: key, end: colon_index + 1 }
        end

        def find_bracket_start(trimmed, original)
          if trimmed.start_with?(Constants::DOUBLE_QUOTE)
            closing_quote = Shared::StringUtils.find_closing_quote(trimmed, 0)
            return nil if closing_quote == -1
            key_end_in_original = original.length - trimmed.length + closing_quote + 1
            original.index(Constants::OPEN_BRACKET, key_end_in_original)
          else
            original.index(Constants::OPEN_BRACKET)
          end
        end
        private_class_method :find_bracket_start

        def find_colon_after_brackets(content, bracket_end)
          brace_end = bracket_end
          brace_start = content.index(Constants::OPEN_BRACE, bracket_end)
          colon_after_bracket = content.index(Constants::COLON, bracket_end)

          if brace_start && colon_after_bracket && brace_start < colon_after_bracket
            found_brace_end = content.index(Constants::CLOSE_BRACE, brace_start)
            brace_end = found_brace_end ? found_brace_end + 1 : brace_end
          end

          search_start = [bracket_end, brace_end].max
          content.index(Constants::COLON, search_start)
        end
        private_class_method :find_colon_after_brackets

        def extract_key_from_header(content, bracket_start)
          return nil if bracket_start.zero?

          raw_key = content[0...bracket_start].strip
          return nil if raw_key.empty?

          if raw_key.start_with?(Constants::DOUBLE_QUOTE)
            closing = Shared::StringUtils.find_closing_quote(raw_key, 0)
            raise SyntaxError, 'Unterminated quoted key' if closing == -1

            return Shared::StringUtils.unescape_string(raw_key[1...closing])
          end

          raw_key
        end
        private_class_method :extract_key_from_header

        def extract_fields(content, bracket_end, colon_index, delimiter)
          brace_start = content.index(Constants::OPEN_BRACE, bracket_end)
          return nil unless brace_start && brace_start < colon_index

          brace_end = content.index(Constants::CLOSE_BRACE, brace_start)
          return nil unless brace_end && brace_end < colon_index

          fields_content = content[(brace_start + 1)...brace_end]
          parse_delimited_values(fields_content, delimiter).map do |field|
            field.strip!
            if field.start_with?(Constants::DOUBLE_QUOTE)
              Shared::StringUtils.unescape_string(field[1...-1])
            else
              field
            end
          end
        end
        private_class_method :extract_fields

        def array_header_after_hyphen?(content)
          stripped = content.strip
          stripped.start_with?(Constants::OPEN_BRACKET) &&
            Shared::StringUtils.find_unquoted_char(content, Constants::COLON) != -1
        end

        def object_first_field_after_hyphen?(content)
          Shared::StringUtils.find_unquoted_char(content, Constants::COLON) != -1
        end
      end
    end
  end
end
