# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../errors'

module DSPy
  module Mixins
    module InstructionUpdatable
      extend T::Sig

      sig { params(new_instruction: String).returns(T.untyped) }
      def with_instruction(new_instruction)
        raise DSPy::InstructionUpdateError.missing_instruction_capability(self.class)
      end

      sig { params(few_shot_examples: T::Array[T.untyped]).returns(T.untyped) }
      def with_examples(few_shot_examples)
        raise DSPy::InstructionUpdateError.missing_examples_capability(self.class)
      end
    end
  end
end
