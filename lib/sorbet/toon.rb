# frozen_string_literal: true

require 'sorbet-runtime'

require_relative 'toon/version'
require_relative 'toon/errors'
require_relative 'toon/constants'
require_relative 'toon/codec'
require_relative 'toon/normalizer'
require_relative 'toon/config'
require_relative 'toon/encoder'
require_relative 'toon/decoder'
require_relative 'toon/reconstructor'
require_relative 'toon/signature_formatter'
require_relative 'toon/struct_extensions'
require_relative 'toon/enum_extensions'

module Sorbet
  module Toon
    class << self
      def encode(value, **options)
        Encoder.encode(value, config: config, **options)
      end

      def decode(payload, struct_class: nil, **options)
        Decoder.decode(payload, config: config, struct_class: struct_class, **options)
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

      def enable_extensions!
        return if extensions_enabled?

        T::Struct.include(Sorbet::Toon::StructExtensions)
        T::Enum.include(Sorbet::Toon::EnumExtensions)
        @extensions_enabled = true
      end

      def extensions_enabled?
        !!@extensions_enabled
      end
    end
  end
end
