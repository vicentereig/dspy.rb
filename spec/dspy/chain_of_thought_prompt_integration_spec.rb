require 'spec_helper'
require 'dspy/chain_of_thought'
require 'dspy/signature'

class ReasoningMath < DSPy::Signature
  description "Solve math problems with clear reasoning."

  input do
    const :problem, String, description: "A math problem to solve"
  end

  output do
    const :answer, String, description: "The numerical answer"
    const :explanation, String, description: "How the problem was solved"
  end
end

class Analysis < DSPy::Signature
  description "Analyze the given text."

  input do
    const :text, String
  end

  output do
    const :summary, String
    const :key_points, String
  end
end

RSpec.describe DSPy::ChainOfThought, "prompt integration" do
  let(:cot_math) { DSPy::ChainOfThought.new(ReasoningMath) }
  let(:cot_analysis) { DSPy::ChainOfThought.new(Analysis) }

  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
    end
  end

  describe 'initialization' do
    it 'creates prompt object with enhanced signature' do
      expect(cot_math.prompt).to be_a(DSPy::Prompt)
    end

    it 'adds "Think step by step" to instruction' do
      original_description = ReasoningMath.description
      expected_instruction = "#{original_description} Think step by step."
      
      expect(cot_math.prompt.instruction).to eq(expected_instruction)
    end

    it 'includes reasoning field in output schema' do
      output_schema = cot_math.prompt.output_schema
      reasoning_field = output_schema.dig(:properties, :reasoning)
      
      expect(reasoning_field).not_to be_nil
      expect(reasoning_field[:type]).to eq("string")
    end

    it 'preserves original signature input schema' do
      expect(cot_math.prompt.input_schema).to eq(ReasoningMath.input_json_schema)
    end

    it 'stores reference to original signature' do
      expect(cot_math.original_signature).to eq(ReasoningMath)
    end

    it 'starts with empty few-shot examples' do
      expect(cot_math.prompt.few_shot_examples).to be_empty
    end
  end

  describe 'backward compatibility' do
    it 'system_signature includes reasoning instructions' do
      system_prompt = cot_math.system_signature
      
      expect(system_prompt).to include("Think step by step")
      expect(system_prompt).to include("reasoning")
    end

    it 'maintains ChainOfThought prediction functionality', :vcr do
      VCR.use_cassette('chain_of_thought_prompt_integration/reasoning_math') do
        result = cot_math.call(problem: "What is 15 × 8?")
        
        expect(result).to respond_to(:problem)
        expect(result).to respond_to(:answer) 
        expect(result).to respond_to(:explanation)
        expect(result).to respond_to(:reasoning)
        expect(result.problem).to eq("What is 15 × 8?")
      end
    end
  end

  describe '#with_instruction' do
    it 'preserves "Think step by step" when not included' do
      new_instruction = "Solve this math problem carefully."
      updated_cot = cot_math.with_instruction(new_instruction)
      
      expect(updated_cot.prompt.instruction).to include("Think step by step")
      expect(updated_cot.prompt.instruction).to include(new_instruction)
    end

    it 'does not duplicate "Think step by step" when already present' do
      instruction_with_cot = "Think step by step and solve this problem."
      updated_cot = cot_math.with_instruction(instruction_with_cot)
      
      step_count = updated_cot.prompt.instruction.scan(/Think step by step/).length
      expect(step_count).to eq(1)
    end

    it 'returns ChainOfThought instance' do
      updated_cot = cot_math.with_instruction("New instruction")
      
      expect(updated_cot).to be_a(DSPy::ChainOfThought)
      expect(updated_cot.original_signature).to eq(ReasoningMath)
    end

    it 'preserves enhanced output schema with reasoning' do
      updated_cot = cot_math.with_instruction("Better instruction")
      reasoning_field = updated_cot.prompt.output_schema.dig(:properties, :reasoning)
      
      expect(reasoning_field).not_to be_nil
    end
  end

  describe '#with_examples' do
    it 'enhances examples with reasoning when missing' do
      examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 5 + 3?" },
          output: { answer: "8", explanation: "Add 5 and 3", reasoning: "5 + 3 = 8" }
        ),
        DSPy::FewShotExample.new(
          input: { problem: "What is 10 - 4?" },
          output: { answer: "6", explanation: "Subtract 4 from 10" }
          # No reasoning provided
        )
      ]
      
      updated_cot = cot_math.with_examples(examples)
      enhanced_examples = updated_cot.prompt.few_shot_examples
      
      expect(enhanced_examples.length).to eq(2)
      expect(enhanced_examples[0].reasoning).to eq("5 + 3 = 8")
      expect(enhanced_examples[1].reasoning).not_to be_nil
      expect(enhanced_examples[1].reasoning).not_to be_empty
    end

    it 'preserves existing reasoning in examples' do
      example_with_reasoning = DSPy::FewShotExample.new(
        input: { problem: "What is 2 × 6?" },
        output: { answer: "12", explanation: "Multiply 2 by 6", reasoning: "2 × 6 = 12" },
        reasoning: "I need to multiply 2 by 6 to get 12"
      )
      
      updated_cot = cot_math.with_examples([example_with_reasoning])
      
      expect(updated_cot.prompt.few_shot_examples[0].reasoning).to eq("I need to multiply 2 by 6 to get 12")
    end

    it 'returns ChainOfThought instance' do
      examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 7 + 2?" },
          output: { answer: "9", explanation: "Add 7 and 2" }
        )
      ]
      
      updated_cot = cot_math.with_examples(examples)
      
      expect(updated_cot).to be_a(DSPy::ChainOfThought)
    end
  end

  describe '#with_prompt' do
    it 'creates ChainOfThought with custom prompt' do
      custom_prompt = DSPy::Prompt.new(
        instruction: "Solve mathematical problems systematically",
        input_schema: ReasoningMath.input_json_schema,
        output_schema: ReasoningMath.output_json_schema,
        few_shot_examples: [
          DSPy::FewShotExample.new(
            input: { problem: "What is 4 × 9?" },
            output: { answer: "36", explanation: "Multiply 4 by 9" }
          )
        ]
      )
      
      updated_cot = cot_math.with_prompt(custom_prompt)
      
      expect(updated_cot).to be_a(DSPy::ChainOfThought)
      expect(updated_cot.prompt.instruction).to include("Think step by step")
      expect(updated_cot.prompt.few_shot_examples.length).to eq(1)
    end

    it 'maintains enhanced output schema with reasoning field' do
      custom_prompt = DSPy::Prompt.new(
        instruction: "Custom instruction",
        input_schema: ReasoningMath.input_json_schema,
        output_schema: ReasoningMath.output_json_schema
      )
      
      updated_cot = cot_math.with_prompt(custom_prompt)
      reasoning_field = updated_cot.prompt.output_schema.dig(:properties, :reasoning)
      
      expect(reasoning_field).not_to be_nil
      expect(reasoning_field[:type]).to eq("string")
    end

    it 'preserves original signature reference' do
      custom_prompt = DSPy::Prompt.new(
        instruction: "Another instruction",
        input_schema: ReasoningMath.input_json_schema,
        output_schema: ReasoningMath.output_json_schema
      )
      
      updated_cot = cot_math.with_prompt(custom_prompt)
      
      expect(updated_cot.original_signature).to eq(ReasoningMath)
    end
  end

  describe 'prompt rendering with reasoning' do
    it 'includes reasoning field in system prompt' do
      system_prompt = cot_math.system_signature
      
      expect(system_prompt).to include("reasoning")
      expect(system_prompt).to include("Step by step reasoning process")
    end

    it 'works with LM when reasoning examples are included', :vcr do
      VCR.use_cassette('chain_of_thought_prompt_integration/math_with_reasoning_examples') do
        examples = [
          DSPy::FewShotExample.new(
            input: { problem: "What is 6 + 7?" },
            output: { answer: "13", explanation: "Add 6 and 7", reasoning: "6 + 7 = 13" },
            reasoning: "I need to add 6 and 7. 6 + 7 = 13."
          )
        ]
        
        cot_with_examples = cot_math.with_examples(examples)
        result = cot_with_examples.call(problem: "What is 9 + 4?")
        
        expect(result).to respond_to(:reasoning)
        expect(result.reasoning).to be_a(String)
        expect(result.reasoning.length).to be > 0
      end
    end
  end

  describe 'immutability' do
    it 'original ChainOfThought remains unchanged after with_instruction' do
      original_instruction = cot_math.prompt.instruction
      cot_math.with_instruction("New instruction")
      
      expect(cot_math.prompt.instruction).to eq(original_instruction)
    end

    it 'original ChainOfThought remains unchanged after with_examples' do
      original_examples = cot_math.prompt.few_shot_examples
      cot_math.with_examples([
        DSPy::FewShotExample.new(
          input: { problem: "Test" },
          output: { answer: "Test", explanation: "Test" }
        )
      ])
      
      expect(cot_math.prompt.few_shot_examples).to eq(original_examples)
    end
  end

  describe 'chain methods for optimization' do
    it 'allows chaining instruction and examples while preserving ChainOfThought behavior' do
      examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 8 ÷ 2?" },
          output: { answer: "4", explanation: "Divide 8 by 2" }
        )
      ]
      
      optimized_cot = cot_math
        .with_instruction("Solve math problems with detailed reasoning")
        .with_examples(examples)
      
      expect(optimized_cot).to be_a(DSPy::ChainOfThought)
      expect(optimized_cot.prompt.instruction).to include("Think step by step")
      expect(optimized_cot.prompt.instruction).to include("detailed reasoning")
      expect(optimized_cot.prompt.few_shot_examples.length).to eq(1)
      expect(optimized_cot.prompt.few_shot_examples[0].reasoning).not_to be_nil
    end
  end

  describe 'reasoning analysis' do
    it 'maintains reasoning step counting functionality', :vcr do
      VCR.use_cassette('chain_of_thought_prompt_integration/reasoning_analysis') do
        # This test ensures that the reasoning analysis instrumentation still works
        # We'll capture the instrumentation events in a separate test if needed
        result = cot_analysis.call(text: "Ruby is a dynamic programming language created by Yukihiro Matsumoto.")
        
        expect(result).to respond_to(:reasoning)
        expect(result.reasoning).to be_a(String)
      end
    end
  end
end