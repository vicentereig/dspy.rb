require 'spec_helper'
require 'dspy/few_shot_example'

RSpec.describe DSPy::FewShotExample do
  let(:input_data) { { sentence: "This is great!" } }
  let(:output_data) { { sentiment: "positive", confidence: 0.95 } }
  let(:reasoning) { "The phrase 'This is great!' expresses positive sentiment with high confidence." }

  describe 'initialization' do
    it 'creates example with input and output' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data)
      
      expect(example.input).to eq(input_data)
    end

    it 'creates example with reasoning' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data, reasoning: reasoning)
      
      expect(example.reasoning).to eq(reasoning)
    end

    it 'freezes input and output hashes' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data)
      
      expect(example.input).to be_frozen
    end

    it 'handles nil reasoning' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data)
      
      expect(example.reasoning).to be_nil
    end
  end

  describe '#to_prompt_section' do
    it 'renders example without reasoning' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data)
      section = example.to_prompt_section
      
      expect(section).to include("## Input")
      expect(section).to include("## Output")
      expect(section).not_to include("## Reasoning")
    end

    it 'renders example with reasoning' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data, reasoning: reasoning)
      section = example.to_prompt_section
      
      expect(section).to include("## Reasoning")
    end

    it 'includes JSON formatted input and output' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data)
      section = example.to_prompt_section
      
      expect(section).to include('"sentence": "This is great!"')
      expect(section).to include('"sentiment": "positive"')
    end
  end

  describe '#to_h' do
    it 'serializes example without reasoning' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data)
      hash = example.to_h
      
      expect(hash[:input]).to eq(input_data)
      expect(hash[:output]).to eq(output_data)
      expect(hash).not_to have_key(:reasoning)
    end

    it 'serializes example with reasoning' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data, reasoning: reasoning)
      hash = example.to_h
      
      expect(hash[:reasoning]).to eq(reasoning)
    end
  end

  describe '.from_h' do
    it 'deserializes example without reasoning' do
      hash = { input: input_data, output: output_data }
      example = DSPy::FewShotExample.from_h(hash)
      
      expect(example.input).to eq(input_data)
      expect(example.output).to eq(output_data)
      expect(example.reasoning).to be_nil
    end

    it 'deserializes example with reasoning' do
      hash = { input: input_data, output: output_data, reasoning: reasoning }
      example = DSPy::FewShotExample.from_h(hash)
      
      expect(example.reasoning).to eq(reasoning)
    end

    it 'handles missing keys gracefully' do
      hash = {}
      example = DSPy::FewShotExample.from_h(hash)
      
      expect(example.input).to eq({})
      expect(example.output).to eq({})
    end
  end

  describe '#==' do
    it 'compares examples correctly' do
      example1 = DSPy::FewShotExample.new(input: input_data, output: output_data, reasoning: reasoning)
      example2 = DSPy::FewShotExample.new(input: input_data, output: output_data, reasoning: reasoning)
      
      expect(example1).to eq(example2)
    end

    it 'returns false for different examples' do
      example1 = DSPy::FewShotExample.new(input: input_data, output: output_data)
      example2 = DSPy::FewShotExample.new(input: input_data, output: output_data, reasoning: reasoning)
      
      expect(example1).not_to eq(example2)
    end

    it 'returns false for non-FewShotExample objects' do
      example = DSPy::FewShotExample.new(input: input_data, output: output_data)
      
      expect(example).not_to eq("not an example")
    end
  end

  describe 'round-trip serialization' do
    it 'preserves all data through serialization and deserialization' do
      original = DSPy::FewShotExample.new(input: input_data, output: output_data, reasoning: reasoning)
      hash = original.to_h
      restored = DSPy::FewShotExample.from_h(hash)
      
      expect(restored).to eq(original)
    end
  end
end