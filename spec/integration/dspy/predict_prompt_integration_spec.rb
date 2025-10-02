require 'spec_helper'
require 'dspy/predict'
require 'dspy/signature'

class BasicMath < DSPy::Signature
  description "Solve basic math problems."

  input do
    const :problem, String, description: "A math problem to solve"
  end

  output do
    const :answer, String, description: "The numerical answer"
  end
end

class TextClassification < DSPy::Signature
  description "Classify text into categories."

  class Category < T::Enum
    enums do
      Sports = new('sports')
      Technology = new('technology')
      Politics = new('politics')
    end
  end

  input do
    const :text, String
  end

  output do
    const :category, Category
    const :confidence, Float
  end
end

RSpec.describe DSPy::Predict, "prompt integration" do
  let(:math_predictor) { DSPy::Predict.new(BasicMath) }
  let(:classifier) { DSPy::Predict.new(TextClassification) }

  before do
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
    end
  end

  describe 'initialization' do
    it 'creates prompt object from signature' do
      expect(math_predictor.prompt).to be_a(DSPy::Prompt)
    end

    it 'sets instruction from signature description' do
      expect(math_predictor.prompt.instruction).to eq(BasicMath.description)
    end

    it 'starts with empty few-shot examples' do
      expect(math_predictor.prompt.few_shot_examples).to be_empty
    end

    it 'includes input and output schemas from signature' do
      prompt = math_predictor.prompt
      
      expect(prompt.input_schema).to eq(BasicMath.input_json_schema)
      expect(prompt.output_schema).to eq(BasicMath.output_json_schema)
    end
  end

  describe 'backward compatibility' do
    it 'system_signature delegates to prompt' do
      system_prompt = math_predictor.system_signature
      expected_prompt = math_predictor.prompt.render_system_prompt
      
      expect(system_prompt).to eq(expected_prompt)
    end

    it 'user_signature delegates to prompt' do
      input_values = { problem: "What is 5 + 3?" }
      user_prompt = math_predictor.user_signature(input_values)
      expected_prompt = math_predictor.prompt.render_user_prompt(input_values)
      
      expect(user_prompt).to eq(expected_prompt)
    end

    it 'maintains original prediction functionality', :vcr do
      VCR.use_cassette('predict_prompt_integration/basic_math') do
        result = math_predictor.call(problem: "What is 7 + 9?")
        
        expect(result).to respond_to(:problem)
        expect(result).to respond_to(:answer)
        expect(result.problem).to eq("What is 7 + 9?")
      end
    end
  end

  describe '#with_instruction' do
    it 'returns new predictor with updated instruction' do
      new_instruction = "Solve this math problem step by step with detailed explanation."
      updated_predictor = math_predictor.with_instruction(new_instruction)
      
      expect(updated_predictor.prompt.instruction).to eq(new_instruction)
      expect(math_predictor.prompt.instruction).to eq(BasicMath.description)
    end

    it 'preserves signature class' do
      updated_predictor = math_predictor.with_instruction("New instruction")
      
      expect(updated_predictor.signature_class).to eq(BasicMath)
    end
  end

  describe '#with_examples' do
    it 'returns new predictor with few-shot examples' do
      examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 2 + 2?" },
          output: { answer: "4" }
        ),
        DSPy::FewShotExample.new(
          input: { problem: "What is 3 × 4?" },
          output: { answer: "12" }
        )
      ]
      
      updated_predictor = math_predictor.with_examples(examples)
      
      expect(updated_predictor.prompt.few_shot_examples).to eq(examples)
      expect(math_predictor.prompt.few_shot_examples).to be_empty
    end

    it 'preserves other prompt properties' do
      examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 1 + 1?" },
          output: { answer: "2" }
        )
      ]
      
      updated_predictor = math_predictor.with_examples(examples)
      
      expect(updated_predictor.prompt.instruction).to eq(math_predictor.prompt.instruction)
      expect(updated_predictor.prompt.input_schema).to eq(math_predictor.prompt.input_schema)
    end
  end

  describe '#add_examples' do
    it 'combines existing and new examples' do
      initial_examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 5 + 5?" },
          output: { answer: "10" }
        )
      ]
      
      predictor_with_examples = math_predictor.with_examples(initial_examples)
      
      new_examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 6 + 6?" },
          output: { answer: "12" }
        )
      ]
      
      final_predictor = predictor_with_examples.add_examples(new_examples)
      
      expect(final_predictor.prompt.few_shot_examples.length).to eq(2)
      expect(final_predictor.prompt.few_shot_examples).to include(*initial_examples)
      expect(final_predictor.prompt.few_shot_examples).to include(*new_examples)
    end
  end

  describe '#with_prompt' do
    it 'returns new predictor with custom prompt' do
      custom_prompt = DSPy::Prompt.new(
        instruction: "Custom math solver",
        input_schema: BasicMath.input_json_schema,
        output_schema: BasicMath.output_json_schema,
        few_shot_examples: [
          DSPy::FewShotExample.new(
            input: { problem: "What is 8 + 7?" },
            output: { answer: "15" }
          )
        ]
      )
      
      updated_predictor = math_predictor.with_prompt(custom_prompt)
      
      expect(updated_predictor.prompt).to eq(custom_prompt)
      expect(updated_predictor.signature_class).to eq(BasicMath)
    end
  end

  describe 'prompt rendering with examples', :vcr do
    it 'includes few-shot examples in system prompt' do
      examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 10 + 15?" },
          output: { answer: "25" }
        )
      ]
      
      predictor_with_examples = math_predictor.with_examples(examples)
      system_prompt = predictor_with_examples.system_signature
      
      expect(system_prompt).to include("Here are some examples")
      expect(system_prompt).to include("What is 10 + 15?")
      expect(system_prompt).to include("25")
    end

    it 'works with LM when examples are included' do
      VCR.use_cassette('predict_prompt_integration/math_with_examples') do
        examples = [
          DSPy::FewShotExample.new(
            input: { problem: "What is 4 + 6?" },
            output: { answer: "10" }
          )
        ]
        
        predictor_with_examples = math_predictor.with_examples(examples)
        result = predictor_with_examples.call(problem: "What is 12 + 8?")
        
        expect(result).to respond_to(:answer)
        expect(result.problem).to eq("What is 12 + 8?")
      end
    end
  end

  describe 'immutability' do
    it 'original predictor remains unchanged after with_instruction' do
      original_instruction = math_predictor.prompt.instruction
      math_predictor.with_instruction("New instruction")
      
      expect(math_predictor.prompt.instruction).to eq(original_instruction)
    end

    it 'original predictor remains unchanged after with_examples' do
      original_examples = math_predictor.prompt.few_shot_examples
      math_predictor.with_examples([
        DSPy::FewShotExample.new(
          input: { problem: "Test" },
          output: { answer: "Test" }
        )
      ])
      
      expect(math_predictor.prompt.few_shot_examples).to eq(original_examples)
    end
  end

  describe 'chain methods for optimization' do
    it 'allows chaining instruction and examples' do
      examples = [
        DSPy::FewShotExample.new(
          input: { problem: "What is 3 + 3?" },
          output: { answer: "6" }
        )
      ]
      
      optimized_predictor = math_predictor
        .with_instruction("Solve math problems accurately")
        .with_examples(examples)
      
      expect(optimized_predictor.prompt.instruction).to eq("Solve math problems accurately")
      expect(optimized_predictor.prompt.few_shot_examples).to eq(examples)
    end
  end
end