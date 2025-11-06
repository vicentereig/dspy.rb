# frozen_string_literal: true
# frozen_string_literal: true

require_relative 'constants'
require_relative 'encode/normalize'
require_relative 'encode/encoders'
require_relative 'decode/scanner'
require_relative 'decode/decoders'

module Sorbet
  module Toon
    module Codec
      class << self
        DEFAULT_INDENT = 2
        DEFAULT_DELIMITER = Constants::DEFAULT_DELIMITER
        DEFAULT_LENGTH_MARKER = false

        def encode(input, indent: DEFAULT_INDENT, delimiter: DEFAULT_DELIMITER, length_marker: DEFAULT_LENGTH_MARKER)
          normalized = Encode::Normalize.normalize(input)
          Encode::Encoders.encode_value(
            normalized,
            indent: indent,
            delimiter: delimiter,
            length_marker: length_marker
          )
        end

        def decode(input, **opts)
          raise ArgumentError, 'Input must be a string' unless input.is_a?(String)

          indent = extract_option(opts, :indent, DEFAULT_INDENT)
          strict = extract_option(opts, :strict, true)

          scan_result = Decode::Scanner.to_parsed_lines(input, indent, strict)
          return {} if scan_result[:lines].empty?

          cursor = Decode::LineCursor.new(scan_result[:lines], scan_result[:blank_lines])
          Decode::Decoders.decode_value_from_lines(cursor, strict: strict)
        end

        private

        def extract_option(options, key, default)
          if options.key?(key)
            options[key]
          elsif options.key?(key.to_s)
            options[key.to_s]
          else
            default
          end
        end
      end
    end
  end
end
