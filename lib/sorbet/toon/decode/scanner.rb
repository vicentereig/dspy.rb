# frozen_string_literal: true

require_relative '../constants'

module Sorbet
  module Toon
    module Decode
      ParsedLine = Struct.new(:raw, :indent, :content, :depth, :line_number, keyword_init: true)
      BlankLineInfo = Struct.new(:line_number, :indent, :depth, keyword_init: true)

      class LineCursor
        attr_reader :blank_lines

        def initialize(lines, blank_lines = [])
          @lines = lines
          @blank_lines = blank_lines
          @index = 0
        end

        def peek
          @lines[@index]
        end

        def next
          line = @lines[@index]
          @index += 1 if line
          line
        end

        def advance
          @index += 1
        end

        def current
          @index.positive? ? @lines[@index - 1] : nil
        end

        def at_end?
          @index >= @lines.length
        end

        def length
          @lines.length
        end

        def peek_at_depth(target_depth)
          line = peek
          return nil unless line
          return nil if line.depth < target_depth
          return line if line.depth == target_depth

          nil
        end

        def has_more_at_depth?(target_depth)
          !peek_at_depth(target_depth).nil?
        end
      end

      module Scanner
        module_function

        def to_parsed_lines(source, indent_size, strict)
          return { lines: [], blank_lines: [] } if source.nil? || source.strip.empty?

          raw_lines = source.split("\n", -1)
          parsed_lines = []
          blank_lines = []

          raw_lines.each_with_index do |raw, index|
            line_number = index + 1
            leading_whitespace = raw[/\A[ \t]*/] || ''
            indent = leading_whitespace.count(Constants::SPACE)
            content = raw[leading_whitespace.length..] || ''

            if content.strip.empty?
              depth = compute_depth_from_indent(indent, indent_size)
              blank_lines << BlankLineInfo.new(line_number: line_number, indent: indent, depth: depth)
              next
            end

            depth = compute_depth_from_indent(indent, indent_size)

            if strict
              validate_leading_whitespace!(leading_whitespace, line_number, indent, indent_size)
            end

            parsed_lines << ParsedLine.new(
              raw: raw,
              indent: indent,
              content: content,
              depth: depth,
              line_number: line_number
            )
          end

          { lines: parsed_lines, blank_lines: blank_lines }
        end

        def compute_depth_from_indent(indent_spaces, indent_size)
          (indent_spaces / indent_size.to_f).floor
        end
        private_class_method :compute_depth_from_indent

        def validate_leading_whitespace!(leading_whitespace, line_number, indent, indent_size)
          if leading_whitespace.include?(Constants::TAB)
            raise RuntimeError, "Line #{line_number}: Tabs are not allowed in indentation in strict mode"
          end

          if indent.positive? && (indent % indent_size != 0)
            raise RuntimeError, "Line #{line_number}: Indentation must be exact multiple of #{indent_size}, but found #{indent} spaces"
          end
        end
        private_class_method :validate_leading_whitespace!
      end
    end
  end
end
