# frozen_string_literal: true

require_relative 'normalizer'
require_relative 'codec'

module Sorbet
  module Toon
    module Encoder
      class << self
        def encode(value, config:, signature: nil, role: :output, **overrides)
          resolved = config.resolve(overrides)

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
      end
    end
  end
end
