# frozen_string_literal: true

require 'sorbet-runtime'

module GEPA
  module Strategies
    class InstructionProposalSignature
      extend T::Sig

      PROMPT_TEMPLATE = <<~PROMPT
        I provided an assistant with the following instructions to perform a task for me:
        ```
        <curr_instructions>
        ```

        The following are examples of different task inputs provided to the assistant along with the assistant's response for each of them, and some feedback on how the assistant's response could be better:
        ```
        <inputs_outputs_feedback>
        ```

        Your task is to write a new instruction for the assistant.

        Read the inputs carefully and identify the input format and infer detailed task description about the task I wish to solve with the assistant.

        Read all the assistant responses and the corresponding feedback. Identify all niche and domain specific factual information about the task and include it in the instruction, as a lot of it may not be available to the assistant in the future. The assistant may have utilized a generalizable strategy to solve the task, if so, include that in the instruction as well.

        Provide the new instructions within ``` blocks.
      PROMPT

      sig { returns(T::Array[String]) }
      def self.input_keys
        %w[current_instruction_doc dataset_with_feedback]
      end

      sig { returns(T::Array[String]) }
      def self.output_keys
        %w[new_instruction]
      end

      sig { params(input: T::Hash[String, T.untyped]).returns(String) }
      def self.prompt_renderer(input)
        prompt = PROMPT_TEMPLATE.dup
        prompt = prompt.sub('<curr_instructions>', input.fetch('current_instruction_doc', ''))
        prompt.sub('<inputs_outputs_feedback>', render_samples(input.fetch('dataset_with_feedback', [])))
      end

      sig { params(output: String).returns(T::Hash[String, String]) }
      def self.output_extractor(output)
        stripped = output.strip
        return { 'new_instruction' => stripped } if stripped.count('```') < 2

        first = stripped.index('```')
        last = stripped.rindex('```')
        if first.nil? || last.nil? || first == last
          { 'new_instruction' => stripped.delete_prefix('```').delete_suffix('```').strip }
        else
          inner = stripped[(first + 3)...last].strip
          { 'new_instruction' => inner.empty? ? stripped : inner }
        end
      end

      class << self
        extend T::Sig
        private

        sig { params(samples: T::Array[T.untyped]).returns(String) }
        def render_samples(samples)
          samples.each_with_index.map do |sample, index|
            convert_sample_to_markdown(sample, index + 1)
          end.join("\n\n")
        end

        sig { params(sample: T.untyped, index: Integer).returns(String) }
        def convert_sample_to_markdown(sample, index)
          return '' unless sample.is_a?(Hash)

          sample.map do |key, value|
            "## Example #{index}\n### #{key}\n#{render_value(value, 4)}"
          end.join
        end

        sig { params(value: T.untyped, level: Integer).returns(String) }
        def render_value(value, level)
          case value
          when Hash
            value.map do |key, val|
              heading = '#' * [level, 6].min
              "#{heading} #{key}\n#{render_value(val, level + 1)}"
            end.join
          when Array
            value.each_with_index.map do |item, idx|
              heading = '#' * [level, 6].min
              "#{heading} Item #{idx + 1}\n#{render_value(item, level + 1)}"
            end.join
          else
            "#{value}\n\n"
          end
        end
      end
    end
  end
end

