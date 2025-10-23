require 'spec_helper'
require 'dspy/structured_outputs_prompt'
require 'dspy/signature'

class TestSignature < DSPy::Signature
  description "Test signature for structured outputs"

  input do
    const :query, String, description: "User query"
  end

  output do
    const :answer, String, description: "Answer to query"
    const :confidence, Float, description: "Confidence score"
  end
end

RSpec.describe DSPy::StructuredOutputsPrompt do
  let(:instruction) { "Answer the query with high confidence." }
  let(:input_schema) do
    {
      "$schema": "http://json-schema.org/draft-06/schema#",
      type: "object",
      properties: { query: { type: "string", description: "User query" } },
      required: ["query"]
    }
  end
  let(:output_schema) do
    {
      "$schema": "http://json-schema.org/draft-06/schema#",
      type: "object",
      properties: {
        answer: { type: "string", description: "Answer to query" },
        confidence: { type: "number", description: "Confidence score" }
      },
      required: ["answer", "confidence"]
    }
  end
  let(:few_shot_examples) do
    [
      DSPy::FewShotExample.new(
        input: { query: "What is Ruby?" },
        output: { answer: "A programming language", confidence: 0.95 }
      )
    ]
  end

  describe '#render_system_prompt' do
    it 'includes input schema' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      system_prompt = prompt.render_system_prompt

      expect(system_prompt).to include("Your input schema fields are:")
      expect(system_prompt).to include('"query"')
    end

    it 'excludes output schema' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      system_prompt = prompt.render_system_prompt

      expect(system_prompt).not_to include("Your output schema fields are:")
      expect(system_prompt).not_to include('"answer"')
      expect(system_prompt).not_to include('"confidence"')
    end

    it 'excludes JSON formatting template' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      system_prompt = prompt.render_system_prompt

      expect(system_prompt).not_to include("All interactions will be structured")
      expect(system_prompt).not_to include("## Input values")
      expect(system_prompt).not_to include("## Output values")
      expect(system_prompt).not_to include("Respond exclusively with")
      expect(system_prompt).not_to include("{input_values}")
      expect(system_prompt).not_to include("{output_values}")
    end

    it 'includes instruction' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      system_prompt = prompt.render_system_prompt

      expect(system_prompt).to include("Your objective is: #{instruction}")
    end

    it 'includes few-shot examples when present' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )

      system_prompt = prompt.render_system_prompt

      expect(system_prompt).to include("Here are some examples:")
      expect(system_prompt).to include("What is Ruby?")
      expect(system_prompt).to include("A programming language")
    end

    it 'excludes examples section when no examples' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      system_prompt = prompt.render_system_prompt

      expect(system_prompt).not_to include("Here are some examples")
    end

    it 'handles few-shot examples provided as hashes' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema,
        few_shot_examples: [
          {
            input: { query: "What is Ruby?" },
            output: { answer: "A programming language", confidence: 0.95 },
            reasoning: "Training example"
          }
        ]
      )

      expect { prompt.render_system_prompt }.not_to raise_error
      expect(prompt.render_system_prompt).to include("Training example")
    end
  end

  describe '#render_user_prompt' do
    it 'includes input values as JSON' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      input_values = { query: "What is DSPy?" }
      user_prompt = prompt.render_user_prompt(input_values)

      expect(user_prompt).to include("## Input Values")
      expect(user_prompt).to include("What is DSPy?")
    end

    it 'excludes JSON formatting instructions' do
      prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      input_values = { query: "What is DSPy?" }
      user_prompt = prompt.render_user_prompt(input_values)

      expect(user_prompt).not_to include("Respond with the corresponding output schema")
      expect(user_prompt).not_to include("wrapped in a ```json ``` block")
      expect(user_prompt).not_to include("## Output values")
    end
  end

  describe 'comparison with regular Prompt' do
    it 'produces significantly shorter system prompt' do
      regular_prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      structured_prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      regular_length = regular_prompt.render_system_prompt.length
      structured_length = structured_prompt.render_system_prompt.length

      # Structured prompt should be at least 30% shorter
      expect(structured_length).to be < (regular_length * 0.7)
    end

    it 'produces significantly shorter user prompt' do
      regular_prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      structured_prompt = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      input_values = { query: "What is DSPy?" }

      regular_length = regular_prompt.render_user_prompt(input_values).length
      structured_length = structured_prompt.render_user_prompt(input_values).length

      # Structured prompt should be significantly shorter
      expect(structured_length).to be < regular_length
    end
  end

  describe 'inheritance from Prompt' do
    it 'can be instantiated from base prompt hash' do
      base_prompt = DSPy::Prompt.from_signature(TestSignature)

      structured_prompt = DSPy::StructuredOutputsPrompt.new(**base_prompt.to_h)

      expect(structured_prompt.instruction).to eq(base_prompt.instruction)
      expect(structured_prompt.input_schema).to eq(base_prompt.input_schema)
      expect(structured_prompt.output_schema).to eq(base_prompt.output_schema)
    end

    it 'supports immutable updates' do
      original = DSPy::StructuredOutputsPrompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )

      updated = original.with_instruction("New instruction")

      expect(updated).to be_a(DSPy::Prompt)
      expect(updated.instruction).to eq("New instruction")
      expect(original.instruction).to eq(instruction)
    end
  end
end
