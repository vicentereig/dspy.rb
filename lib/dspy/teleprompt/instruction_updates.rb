# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'
require_relative '../errors'

module DSPy
  module Teleprompt
    module InstructionUpdates
      extend T::Sig

      module_function

      sig { params(predictor: T.untyped).void }
      def ensure_instruction_capability!(predictor)
        return if predictor.respond_to?(:with_instruction)
        raise DSPy::InstructionUpdateError.missing_instruction_capability(predictor.class)
      end

      sig { params(predictor: T.untyped).void }
      def ensure_examples_capability!(predictor)
        return if predictor.respond_to?(:with_examples)
        raise DSPy::InstructionUpdateError.missing_examples_capability(predictor.class)
      end

      sig { params(owner: T.untyped, predictor: T.untyped, instruction: String).returns([T.untyped, T.untyped]) }
      def apply_instruction(owner, predictor, instruction)
        ensure_instruction_capability!(predictor)
        updated = predictor.with_instruction(instruction)
        [replace_reference(owner, predictor, updated), updated]
      end

      sig { params(owner: T.untyped, predictor: T.untyped, examples: T::Array[T.untyped]).returns([T.untyped, T.untyped]) }
      def apply_examples(owner, predictor, examples)
        ensure_examples_capability!(predictor)
        updated = predictor.with_examples(examples)
        [replace_reference(owner, predictor, updated), updated]
      end

      sig { params(owner: T.untyped, target: T.untyped, replacement: T.untyped).returns(T.untyped) }
      def replace_reference(owner, target, replacement)
        return replacement if owner.equal?(target)

        Array(owner.instance_variables).each do |ivar|
          value = owner.instance_variable_get(ivar)
          next if value.nil?

          new_value = replace_in_object(value, target, replacement, ::Set.new)
          unless new_value.equal?(value)
            owner.instance_variable_set(ivar, new_value)
          end
        end

        owner
      end

      sig do
        params(
          container: T.untyped,
          target: T.untyped,
          replacement: T.untyped,
          visited: ::Set[Integer]
        ).returns(T.untyped)
      end
      def replace_in_object(container, target, replacement, visited)
        return replacement if container.equal?(target)
        return container if visited.include?(container.object_id)

        visited.add(container.object_id)

        case container
        when Array
          modified = false
          new_array = container.map do |value|
            new_value = replace_in_object(value, target, replacement, visited)
            modified ||= !new_value.equal?(value)
            new_value
          end
          modified ? new_array : container
        when Hash
          modified = false
          new_hash = container.each_with_object({}) do |(key, value), memo|
            new_value = replace_in_object(value, target, replacement, visited)
            modified ||= !new_value.equal?(value)
            memo[key] = new_value
          end
          modified ? new_hash : container
        else
          container
        end
      end
    end
  end
end
