# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'prompt'

module DSPy
  # Optimized prompt for structured outputs that omits redundant schema information
  # since the schema is already enforced by API parameters (response_format, generation_config, tools)
  class StructuredOutputsPrompt < Prompt
    extend T::Sig

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
  end
end
