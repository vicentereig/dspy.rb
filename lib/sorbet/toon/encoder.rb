# frozen_string_literal: true

require_relative 'normalizer'
require_relative 'codec'

module Sorbet
  module Toon
    module Encoder
      CONFIG_KEYS = %i[indent delimiter length_marker include_type_metadata].freeze

      class << self
        def encode(value, config:, signature: nil, role: :output, **overrides)
          config_overrides = extract_overrides(overrides, CONFIG_KEYS)
          resolved = config.resolve(config_overrides)

          normalized = Sorbet::Toon::Normalizer.normalize(
            value,
            signature: signature,
            role: role,
            include_type_metadata: resolved.include_type_metadata
          )

          Sorbet::Toon::Codec.encode(
            normalized,
            indent: resolved.indent,
            delimiter: resolved.delimiter,
            length_marker: resolved.length_marker
          )
        end

        private

        def extract_overrides(options, keys)
          keys.each_with_object({}) do |key, memo|
            next unless options.key?(key)

            memo[key] = options.delete(key)
          end
        end
      end
    end
  end
end
