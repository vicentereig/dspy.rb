require 'spec_helper'
require 'dspy/prompt'
require 'dspy/signature'

class MathQA < DSPy::Signature
  description "Answer math questions with step-by-step reasoning."

  input do
    const :question, String, description: "A math word problem"
  end

  output do
    const :answer, String, description: "The numerical answer"
    const :explanation, String, description: "Step-by-step solution"
  end
end

class PromptClassify < DSPy::Signature
  description "Classify text sentiment."

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :text, String
  end

  output do
    const :sentiment, Sentiment
  end
end

RSpec.describe DSPy::Prompt do
  let(:instruction) { "Solve this math problem step by step." }
  let(:input_schema) do
    {
      "$schema": "http://json-schema.org/draft-06/schema#",
      type: "object",
      properties: { question: { type: "string", description: "A math word problem" } },
      required: ["question"]
    }
  end
  let(:output_schema) do
    {
      "$schema": "http://json-schema.org/draft-06/schema#",
      type: "object",
      properties: {
        answer: { type: "string", description: "The numerical answer" },
        explanation: { type: "string", description: "Step-by-step solution" }
      },
      required: ["answer", "explanation"]
    }
  end
  let(:few_shot_examples) do
    [
      DSPy::FewShotExample.new(
        input: { question: "What is 2 + 2?" },
        output: { answer: "4", explanation: "2 + 2 = 4" }
      )
    ]
  end

  describe 'initialization' do
    it 'creates prompt with required parameters' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      expect(prompt.instruction).to eq(instruction)
    end

    it 'creates prompt with few-shot examples' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      expect(prompt.few_shot_examples).to eq(few_shot_examples)
    end

    it 'freezes few-shot examples array' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      expect(prompt.few_shot_examples).to be_frozen
    end

    it 'defaults to empty few-shot examples' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      expect(prompt.few_shot_examples).to be_empty
    end
  end

  describe '#with_instruction' do
    it 'returns new prompt with updated instruction' do
      original = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      new_instruction = "Solve this problem carefully."
      updated = original.with_instruction(new_instruction)
      
      expect(updated.instruction).to eq(new_instruction)
      expect(original.instruction).to eq(instruction)
    end

    it 'preserves other properties' do
      original = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      updated = original.with_instruction("New instruction")
      
      expect(updated.few_shot_examples).to eq(original.few_shot_examples)
    end
  end

  describe '#with_examples' do
    it 'returns new prompt with updated examples' do
      original = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      updated = original.with_examples(few_shot_examples)
      
      expect(updated.few_shot_examples).to eq(few_shot_examples)
      expect(original.few_shot_examples).to be_empty
    end
  end

  describe '#add_examples' do
    it 'combines existing and new examples' do
      original = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      new_example = DSPy::FewShotExample.new(
        input: { question: "What is 3 × 4?" },
        output: { answer: "12", explanation: "3 × 4 = 12" }
      )
      
      updated = original.add_examples([new_example])
      
      expect(updated.few_shot_examples.length).to eq(2)
      expect(updated.few_shot_examples).to include(new_example)
    end
  end

  describe '#render_system_prompt' do
    it 'includes input and output schemas' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      system_prompt = prompt.render_system_prompt
      
      expect(system_prompt).to include("input schema fields")
      expect(system_prompt).to include("output schema fields")
    end

    it 'includes instruction' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      system_prompt = prompt.render_system_prompt
      
      expect(system_prompt).to include(instruction)
    end

    it 'includes few-shot examples when present' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      system_prompt = prompt.render_system_prompt
      
      expect(system_prompt).to include("Here are some examples")
      expect(system_prompt).to include("What is 2 + 2?")
    end

    it 'excludes examples section when no examples' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      system_prompt = prompt.render_system_prompt
      
      expect(system_prompt).not_to include("Here are some examples")
    end
  end

  describe '#render_user_prompt' do
    it 'includes input values as JSON' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      input_values = { question: "What is 5 + 3?" }
      user_prompt = prompt.render_user_prompt(input_values)
      
      expect(user_prompt).to include("What is 5 + 3?")
      expect(user_prompt).to include("## Input Values")
    end
  end

  describe '#to_messages' do
    it 'returns system and user messages' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      input_values = { question: "What is 7 + 1?" }
      messages = prompt.to_messages(input_values)
      
      expect(messages.length).to eq(2)
      expect(messages[0][:role]).to eq('system')
      expect(messages[1][:role]).to eq('user')
    end

    it 'includes input values in user message' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      input_values = { question: "What is 9 - 4?" }
      messages = prompt.to_messages(input_values)
      
      expect(messages[1][:content]).to include("What is 9 - 4?")
    end
  end

  describe '.from_signature' do
    it 'creates prompt from signature class' do
      prompt = DSPy::Prompt.from_signature(MathQA)
      
      expect(prompt.instruction).to eq(MathQA.description)
      expect(prompt.signature_class_name).to eq("MathQA")
    end

    it 'extracts input and output schemas' do
      prompt = DSPy::Prompt.from_signature(PromptClassify)
      
      expect(prompt.input_schema).to eq(PromptClassify.input_json_schema)
      expect(prompt.output_schema).to eq(PromptClassify.output_json_schema)
    end

    it 'starts with empty few-shot examples' do
      prompt = DSPy::Prompt.from_signature(MathQA)
      
      expect(prompt.few_shot_examples).to be_empty
    end
  end

  describe 'serialization' do
    it 'serializes to hash' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema,
        signature_class_name: "MathQA"
      )
      
      hash = prompt.to_h
      
      expect(hash[:instruction]).to eq(instruction)
      expect(hash[:signature_class_name]).to eq("MathQA")
    end

    it 'deserializes from hash' do
      hash = {
        instruction: instruction,
        few_shot_examples: [few_shot_examples.first.to_h],
        input_schema: input_schema,
        output_schema: output_schema,
        signature_class_name: "MathQA"
      }
      
      prompt = DSPy::Prompt.from_h(hash)
      
      expect(prompt.instruction).to eq(instruction)
      expect(prompt.few_shot_examples.length).to eq(1)
    end
  end

  describe '#==' do
    it 'compares prompts correctly' do
      prompt1 = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      prompt2 = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      expect(prompt1).to eq(prompt2)
    end

    it 'returns false for different instructions' do
      prompt1 = DSPy::Prompt.new(
        instruction: "First instruction",
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      prompt2 = DSPy::Prompt.new(
        instruction: "Second instruction",
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      expect(prompt1).not_to eq(prompt2)
    end
  end

  describe '#diff' do
    it 'shows instruction changes' do
      prompt1 = DSPy::Prompt.new(
        instruction: "Old instruction",
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      prompt2 = DSPy::Prompt.new(
        instruction: "New instruction",
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      diff = prompt1.diff(prompt2)
      
      expect(diff[:instruction][:from]).to eq("Old instruction")
      expect(diff[:instruction][:to]).to eq("New instruction")
    end

    it 'shows example changes' do
      prompt1 = DSPy::Prompt.new(
        instruction: instruction,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      prompt2 = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      diff = prompt1.diff(prompt2)
      
      expect(diff[:few_shot_examples][:from]).to eq(0)
      expect(diff[:few_shot_examples][:to]).to eq(1)
    end
  end

  describe '#stats' do
    it 'returns prompt statistics' do
      prompt = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema
      )
      
      stats = prompt.stats
      
      expect(stats[:character_count]).to be > 0
      expect(stats[:example_count]).to eq(1)
      expect(stats[:input_fields]).to eq(1)
      expect(stats[:output_fields]).to eq(2)
    end
  end

  describe 'round-trip serialization' do
    it 'preserves all data' do
      original = DSPy::Prompt.new(
        instruction: instruction,
        few_shot_examples: few_shot_examples,
        input_schema: input_schema,
        output_schema: output_schema,
        signature_class_name: "MathQA"
      )
      
      hash = original.to_h
      restored = DSPy::Prompt.from_h(hash)
      
      expect(restored).to eq(original)
    end
  end
end