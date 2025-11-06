# frozen_string_literal: true

require_relative '../constants'

module Sorbet
  module Toon
    module Encode
      class Writer
        def initialize(indent_size)
          @indentation_string = Constants::SPACE * indent_size
          @lines = []
        end

        def push(depth, content)
          @lines << "#{@indentation_string * depth}#{content}"
        end

        def push_list_item(depth, content)
          push(depth, "#{Constants::LIST_ITEM_PREFIX}#{content}")
        end

        def to_s
          @lines.join("\n")
        end
      end
    end
  end
end
