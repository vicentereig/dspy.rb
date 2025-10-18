# frozen_string_literal: true

require 'forwardable'

module GEPA
  module Logging
    # Minimal logger interface used across GEPA components.
    class Logger
      extend Forwardable

      def initialize(io: $stdout)
        @io = io
      end

      def log(message)
        write(message)
      end

      private

      attr_reader :io

      def write(message)
        io.puts(message)
        io.flush if io.respond_to?(:flush)
      end
    end

    # Logger that fans out messages to multiple IO streams.
    class CompositeLogger < Logger
      def initialize(*ios)
        @ios = ios.flatten
      end

      def log(message)
        @ios.each do |io|
          io.puts(message)
          io.flush if io.respond_to?(:flush)
        end
      end
    end

    # Logger that captures messages into memory (handy for tests).
    class BufferingLogger < Logger
      attr_reader :messages

      def initialize
        @messages = []
      end

      def log(message)
        @messages << message
      end
    end
  end
end

