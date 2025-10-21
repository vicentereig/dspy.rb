require 'spec_helper'
require 'json'
require 'dspy/propose/dataset_summary_generator'

RSpec.describe DSPy::Propose::DatasetSummaryGenerator do
  describe 'Signatures' do
    describe DSPy::Propose::DatasetSummaryGenerator::ObservationSummarizer do
      it 'is a DSPy::Signature subclass' do
        expect(described_class).to be < DSPy::Signature
      end

      it 'has descriptive signature description' do
        expect(described_class.description).to include('brief 2-3 sentence summary')
        expect(described_class.description).to include('most important details')
      end
    end

    describe DSPy::Propose::DatasetSummaryGenerator::DatasetDescriptor do
      it 'is a DSPy::Signature subclass' do
        expect(described_class).to be < DSPy::Signature
      end

      it 'has descriptive signature description' do
        expect(described_class.description).to include('write observations about trends')
        expect(described_class.description).to include('topics, content, syntax')
      end
    end

    describe DSPy::Propose::DatasetSummaryGenerator::DatasetDescriptorWithPriorObservations do
      it 'is a DSPy::Signature subclass' do
        expect(described_class).to be < DSPy::Signature
      end

      it 'has descriptive signature description' do
        expect(described_class.description).to include('add your own observations')
        expect(described_class.description).to include("say 'COMPLETE'")
      end
    end
  end

  describe '.order_input_keys_in_string' do
    it 'sorts input keys alphabetically' do
      unordered = 'Example{input_keys={question, context, reasoning}}'
      ordered = described_class.order_input_keys_in_string(unordered)
      expect(ordered).to eq('Example{input_keys={context, question, reasoning}}')
    end

    it 'handles multiple input_keys blocks' do
      unordered = 'Ex1{input_keys={z, a, m}} Ex2{input_keys={b, y, c}}'
      ordered = described_class.order_input_keys_in_string(unordered)
      expect(ordered).to eq('Ex1{input_keys={a, m, z}} Ex2{input_keys={b, c, y}}')
    end

    it 'preserves spacing around commas' do
      unordered = 'Example{input_keys={  foo  ,  bar  ,  baz  }}'
      ordered = described_class.order_input_keys_in_string(unordered)
      expect(ordered).to eq('Example{input_keys={bar, baz, foo}}')
    end

    it 'returns unchanged string when no input_keys found' do
      unchanged = 'Example without input keys'
      result = described_class.order_input_keys_in_string(unchanged)
      expect(result).to eq(unchanged)
    end

    it 'handles already sorted keys' do
      already_sorted = 'Example{input_keys={a, b, c}}'
      result = described_class.order_input_keys_in_string(already_sorted)
      expect(result).to eq(already_sorted)
    end
  end

  describe '.strip_prefix' do
    it 'strips single word prefixes followed by colon' do
      expect(described_class.strip_prefix('Answer: This is the answer')).to eq('This is the answer')
      expect(described_class.strip_prefix('Output: Some output')).to eq('Some output')
      expect(described_class.strip_prefix('Summary: The summary')).to eq('The summary')
    end

    it 'strips multi-word prefixes (up to 4 words)' do
      expect(described_class.strip_prefix('Final Answer: Result')).to eq('Result')
      expect(described_class.strip_prefix('My Best Answer: Result')).to eq('Result')
      expect(described_class.strip_prefix('The Final Best Answer: Result')).to eq('Result')
    end

    it 'handles asterisks and whitespace before prefix' do
      expect(described_class.strip_prefix('* Answer: Text')).to eq('Text')
      expect(described_class.strip_prefix('  Answer: Text')).to eq('Text')
      expect(described_class.strip_prefix('** Output: Text')).to eq('Text')
    end

    it 'strips surrounding quotes' do
      expect(described_class.strip_prefix('"Answer: Text"')).to eq('Answer: Text')
      expect(described_class.strip_prefix("'Some text'")).to eq('Some text')
    end

    it 'handles text without prefix' do
      expect(described_class.strip_prefix('Just plain text')).to eq('Just plain text')
    end

    it 'handles empty string' do
      expect(described_class.strip_prefix('')).to eq('')
    end

    it 'handles text with hyphens and apostrophes in prefix' do
      expect(described_class.strip_prefix("User's-Answer: Text")).to eq('Text')
    end
  end

  describe '.create_dataset_summary' do
    # Integration tests with VCR will test the full functionality
    # Unit tests focus on pure logic and helper functions

    it 'is defined as a module function' do
      expect(described_class).to respond_to(:create_dataset_summary)
    end
  end

  describe '.format_examples_for_prompt' do
    let(:signature_class) do
      stub_const('DatasetSummaryGeneratorSpecSignature', Class.new(DSPy::Signature) do
        description "Simple QA signature"

        input do
          const :question, String
        end

        output do
          const :answer, String
        end
      end)
    end

    let(:example) do
      DSPy::Example.new(
        signature_class: signature_class,
        input: { question: "What is DSPy?" },
        expected: { answer: "A declarative optimization framework." }
      )
    end

    it 'serializes DSPy::Example payloads to structured hashes' do
      serialized = described_class.format_examples_for_prompt([example])

      expect(serialized).to be_an(Array)
      expect(serialized.size).to eq(1)

      first = serialized.first
      expect(first).to include('signature', 'input', 'expected')
      expect(first['signature']).to eq('DatasetSummaryGeneratorSpecSignature')
      expect(first['input']['question']).to eq('What is DSPy?')
      expect(first['expected']['answer']).to eq('A declarative optimization framework.')
      expect { JSON.parse(JSON.generate(serialized)) }.not_to raise_error
    end

    it 'serializes multiple examples deterministically' do
      serialized = described_class.format_examples_for_prompt([example, example])

      expect(serialized).to be_an(Array)
      expect(serialized.length).to eq(2)
      expect(serialized.all? { |item| item['signature'] == example.signature_class.name }).to be(true)
      expect { JSON.parse(JSON.generate(serialized)) }.not_to raise_error
    end

    it 'serializes few-shot examples to hashes' do
      few_shot = DSPy::FewShotExample.new(
        input: { question: "What is DSPy?" },
        output: { answer: "A declarative optimization framework." }
      )

      serialized = described_class.format_examples_for_prompt([few_shot])

      expect(serialized).to be_an(Array)
      expect(serialized.first['input']['question']).to eq('What is DSPy?')
      expect(serialized.first['output']['answer']).to eq('A declarative optimization framework.')
      expect { JSON.parse(JSON.generate(serialized)) }.not_to raise_error
    end

    it 'produces input payloads that render without double escaping' do
      serialized = described_class.format_examples_for_prompt([example])

      prompt_signature = Class.new(DSPy::Signature) do
        description "Example rendering signature"

        input do
          const :examples, T::Array[T::Hash[String, T.untyped]]
        end

        output do
          const :observations, String
        end
      end

      prompt = DSPy::Prompt.from_signature(prompt_signature)
      user_prompt = prompt.render_user_prompt(examples: serialized)

      expect(user_prompt).to include('"examples": [')
      expect(user_prompt).to include('"signature"')
      expect(user_prompt).not_to include('\\"signature\\"')
    end
  end
end
