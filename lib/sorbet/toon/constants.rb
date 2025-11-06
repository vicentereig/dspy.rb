# frozen_string_literal: true

module Sorbet
  module Toon
    module Constants
      LIST_ITEM_MARKER = '-'
      LIST_ITEM_PREFIX = '- '

      COMMA = ','
      COLON = ':'
      SPACE = ' '
      PIPE = '|'
      HASH = '#'
      TAB = "\t"

      OPEN_BRACKET = '['
      CLOSE_BRACKET = ']'
      OPEN_BRACE = '{'
      CLOSE_BRACE = '}'

      NULL_LITERAL = 'null'
      TRUE_LITERAL = 'true'
      FALSE_LITERAL = 'false'

      BACKSLASH = '\\'
      DOUBLE_QUOTE = '"'
      NEWLINE = "\n"
      CARRIAGE_RETURN = "\r"

      DELIMITERS = {
        comma: COMMA,
        tab: TAB,
        pipe: PIPE
      }.freeze

      DEFAULT_DELIMITER = DELIMITERS[:comma]
    end
  end
end
