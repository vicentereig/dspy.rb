# frozen_string_literal: true

require_relative 'codec'

module Sorbet
  module Toon
    module Decoder
      class << self
        def decode(payload, config:, signature: nil, role: :output, **overrides)
          resolved = config.resolve(overrides)

          Sorbet::Toon::Codec.decode(
            payload,
            indent: resolved.indent,
            strict: resolved.strict
          )
        end
      end
    end
  end
end
