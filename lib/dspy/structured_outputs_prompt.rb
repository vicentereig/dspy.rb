# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'prompt'

module DSPy
  # Optimized prompt for structured outputs that omits redundant schema information
  # since the schema is already enforced by API parameters (response_format, generation_config, tools)
  class StructuredOutputsPrompt < Prompt
    extend T::Sig

    sig do
      params(
        instruction: String,
        input_schema: T::Hash[Symbol, T.untyped],
        output_schema: T::Hash[Symbol, T.untyped],
        few_shot_examples: T::Array[T.untyped],
        signature_class_name: T.nilable(String),
        schema_format: T.nilable(Symbol),
        signature_class: T.nilable(T.class_of(Signature)),
        data_format: T.nilable(Symbol)
      ).void
    end
    def initialize(instruction:, input_schema:, output_schema:, few_shot_examples: [], signature_class_name: nil, schema_format: nil, signature_class: nil, data_format: nil)
      normalized_examples = few_shot_examples.map do |example|
        case example
        when FewShotExample
          example
        when Hash
          FewShotExample.from_h(symbolize_keys(example))
        else
          raise ArgumentError, "Unsupported few-shot example type: #{example.class}"
        end
      end

      super(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema,
        few_shot_examples: normalized_examples,
        signature_class_name: signature_class_name,
        schema_format: schema_format,
        signature_class: signature_class,
        data_format: data_format
      )
    end

    # Render minimal system prompt without output schema or JSON formatting instructions
    sig { returns(String) }
    def render_system_prompt
      sections = []

      sections << "Your input schema fields are:"
      sections << "```json"
      sections << JSON.pretty_generate(@input_schema)
      sections << "```"

      # Add few-shot examples if present
      if @few_shot_examples.any?
        sections << ""
        sections << "Here are some examples:"
        sections << ""
        @few_shot_examples.each_with_index do |example, index|
          sections << "### Example #{index + 1}"
          sections << example.to_prompt_section
          sections << ""
        end
      end

      sections << ""
      sections << "Your objective is: #{@instruction}"

      sections.join("\n")
    end

    # Render minimal user prompt without JSON formatting instructions
    sig { params(input_values: T::Hash[Symbol, T.untyped]).returns(String) }
    def render_user_prompt(input_values)
      sections = []

      sections << "## Input Values"
      sections << "```json"
      sections << JSON.pretty_generate(serialize_for_json(input_values))
      sections << "```"

      sections.join("\n")
    end

    private

    sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        value = symbolize_keys(value) if value.is_a?(Hash)
        if value.is_a?(Array)
          value = value.map { |item| item.is_a?(Hash) ? symbolize_keys(item) : item }
        end
        key_sym = key.is_a?(Symbol) ? key : key.to_sym
        result[key_sym] = value
      end
    end
  end
end
