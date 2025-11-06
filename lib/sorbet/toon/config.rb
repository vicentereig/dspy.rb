# frozen_string_literal: true

require_relative 'constants'

module Sorbet
  module Toon
    class Config
      attr_accessor :include_type_metadata, :indent, :delimiter, :length_marker, :strict

      def initialize
        reset!
      end

      def reset!
        @include_type_metadata = false
        @indent = 2
        @delimiter = Constants::DEFAULT_DELIMITER
        @length_marker = false
        @strict = true
      end

      def copy
        copy = self.class.new
        copy.include_type_metadata = include_type_metadata
        copy.indent = indent
        copy.delimiter = delimiter
        copy.length_marker = length_marker
        copy.strict = strict
        copy
      end

      def resolve(overrides = {})
        copy.apply(overrides)
      end

      def apply(overrides = {})
        overrides.each do |key, value|
          next if value.nil?

          setter = "#{key}="
          raise ArgumentError, "Unknown config option: #{key}" unless respond_to?(setter)

          public_send(setter, value)
        end

        self
      end
    end
  end
end
