# frozen_string_literal: true

require_relative '../constants'
require_relative '../errors'

module Sorbet
  module Toon
    module Shared
      module StringUtils
        module_function

        def escape_string(value)
          value
            .gsub('\\') { Constants::BACKSLASH * 2 }
            .gsub('"', "#{Constants::BACKSLASH}#{Constants::DOUBLE_QUOTE}")
            .gsub("\n", "#{Constants::BACKSLASH}n")
            .gsub("\r", "#{Constants::BACKSLASH}r")
            .gsub("\t", "#{Constants::BACKSLASH}t")
        end

        def unescape_string(value)
          result = +''
          i = 0
          while i < value.length
            char = value[i]
            if char == Constants::BACKSLASH
              raise Sorbet::Toon::DecodeError, 'Invalid escape sequence: backslash at end of string' if i + 1 >= value.length

              next_char = value[i + 1]
              case next_char
              when 'n'
                result << Constants::NEWLINE
              when 't'
                result << Constants::TAB
              when 'r'
                result << Constants::CARRIAGE_RETURN
              when Constants::BACKSLASH
                result << Constants::BACKSLASH
              when Constants::DOUBLE_QUOTE
                result << Constants::DOUBLE_QUOTE
              else
                raise Sorbet::Toon::DecodeError, "Invalid escape sequence: \\#{next_char}"
              end
              i += 2
              next
            end

            result << char
            i += 1
          end
          result
        end

        def find_closing_quote(content, start_index)
          i = start_index + 1
          while i < content.length
            if content[i] == Constants::BACKSLASH && i + 1 < content.length
              i += 2
              next
            end

            return i if content[i] == Constants::DOUBLE_QUOTE

            i += 1
          end
          -1
        end

        def find_unquoted_char(content, char, start_index = 0)
          in_quotes = false
          i = start_index

          while i < content.length
            if content[i] == Constants::BACKSLASH && i + 1 < content.length && in_quotes
              i += 2
              next
            end

            if content[i] == Constants::DOUBLE_QUOTE
              in_quotes = !in_quotes
              i += 1
              next
            end

            return i if content[i] == char && !in_quotes

            i += 1
          end

          -1
        end
      end
    end
  end
end
