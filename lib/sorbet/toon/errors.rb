# frozen_string_literal: true

module Sorbet
  module Toon
    class Error < StandardError; end

    class DecodeError < Error; end
    class EncodeError < Error; end
  end
end
