# frozen_string_literal: true

require_relative 'codec'
require_relative 'reconstructor'

module Sorbet
  module Toon
    module Decoder
      CONFIG_KEYS = %i[indent strict].freeze

      class << self
        def decode(payload, config:, signature: nil, role: :output, struct_class: nil, **overrides)
          config_overrides = extract_overrides(overrides, CONFIG_KEYS)
          resolved = config.resolve(config_overrides)

          decoded = Sorbet::Toon::Codec.decode(
            payload,
            indent: resolved.indent,
            strict: resolved.strict
          )

          Sorbet::Toon::Reconstructor.reconstruct(
            decoded,
            signature: signature,
            struct_class: struct_class,
            role: role
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
