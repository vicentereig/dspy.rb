# frozen_string_literal: true

require_relative 'toon/errors'
require_relative 'toon/constants'
require_relative 'toon/codec'
require_relative 'toon/normalizer'
require_relative 'toon/config'
require_relative 'toon/encoder'
require_relative 'toon/decoder'

module Sorbet
  module Toon
    class << self
      def encode(value, **options)
        Encoder.encode(value, config: config, **options)
      end

      def decode(payload, **options)
        Decoder.decode(payload, config: config, **options)
      end

      def configure
        yield(config)
      end

      def config
        @config ||= Config.new
      end

      def reset_config!(new_config = nil)
        @config = new_config&.copy || Config.new
      end
    end
  end
end
