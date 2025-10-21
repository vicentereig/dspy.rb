require 'spec_helper'
require 'dspy/propose/dataset_summary_generator'

RSpec.describe DSPy::Propose::DatasetSummaryGenerator, :vcr do
  # Test signature for creating examples
  class DatasetSummaryTestQA < DSPy::Signature
    description "Answer questions based on provided context"

    input do
      const :question, String
      const :context, String
    end

    output do
      const :answer, String
      const :confidence, Float
    end
  end

  let(:small_trainset) do
    [
      DSPy::Example.new(
        signature_class: DatasetSummaryTestQA,
        input: {
          question: "What is photosynthesis?",
          context: "Photosynthesis is the process by which plants convert sunlight into energy"
        },
        expected: { answer: "A process where plants convert sunlight to energy", confidence: 0.9 }
      ),
      DSPy::Example.new(
        signature_class: DatasetSummaryTestQA,
        input: {
          question: "How do birds fly?",
          context: "Birds fly by generating lift with their wings through air pressure differences"
        },
        expected: { answer: "By creating lift with their wings", confidence: 0.85 }
      ),
      DSPy::Example.new(
        signature_class: DatasetSummaryTestQA,
        input: {
          question: "What causes rain?",
          context: "Rain occurs when water vapor in clouds condenses and falls to Earth"
        },
        expected: { answer: "Water vapor condensing in clouds", confidence: 0.9 }
      )
    ]
  end

  let(:lm) { DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) }

  before do
    DSPy.configure do |config|
      config.lm = lm
    end
  end

  describe '.create_dataset_summary' do
    it 'generates a summary for a small dataset', vcr: { cassette_name: 'dataset_summary/small_dataset' } do
      summary = described_class.create_dataset_summary(
        small_trainset,
        2,
        lm,
        verbose: false
      )

      expect(summary).to be_a(String)
      expect(summary.length).to be > 10
      expect(summary.length).to be < 500
      # Summary should mention key aspects of the dataset
      expect(summary.downcase).to match(/question|answer|science|natural|phenomena/i)
    end

    it 'generates a summary with verbose output', vcr: { cassette_name: 'dataset_summary/verbose' } do
      # Capture stdout to verify verbose output
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      begin
        summary = described_class.create_dataset_summary(
          small_trainset.take(2),
          2,
          lm,
          verbose: true
        )

        $stdout = original_stdout
        verbose_output = output.string

        expect(verbose_output).to include('Bootstrapping dataset summary')
        expect(verbose_output).to include('Generated summary:')
        expect(summary).to be_a(String)
      ensure
        $stdout = original_stdout
      end
    end

    it 'handles larger datasets with batching', vcr: { cassette_name: 'dataset_summary/larger_dataset' } do
      # Create a larger dataset by duplicating with variations
      larger_trainset = (0...10).map do |i|
        DSPy::Example.new(
          signature_class: DatasetSummaryTestQA,
          input: {
            question: "Question #{i} about science?",
            context: "Context #{i} explaining scientific concept"
          },
          expected: { answer: "Answer #{i}", confidence: 0.8 + (i * 0.01) }
        )
      end

      summary = described_class.create_dataset_summary(
        larger_trainset,
        3,  # Batch size of 3 will process in multiple batches
        lm,
        verbose: false
      )

      expect(summary).to be_a(String)
      expect(summary.length).to be > 20
      expect(summary).not_to be_empty
    end

    it 'works with different batch sizes', vcr: { cassette_name: 'dataset_summary/batch_size_variation' } do
      summary = described_class.create_dataset_summary(
        small_trainset,
        1,  # Process one at a time
        lm,
        verbose: false
      )

      expect(summary).to be_a(String)
      expect(summary).not_to be_empty
    end
  end

  describe 'ObservationSummarizer signature' do
    it 'can summarize observations', vcr: { cassette_name: 'dataset_summary/observation_summarizer' } do
      observations = "The dataset contains question-answer pairs about science. " \
                    "Questions are concise and direct. Answers provide clear explanations. " \
                    "Topics include biology, physics, and natural phenomena. " \
                    "Confidence scores are generally high (0.8-0.9)."

      predictor = DSPy::Predict.new(DSPy::Propose::DatasetSummaryGenerator::ObservationSummarizer)
      result = predictor.call(observations: observations)

      expect(result).to respond_to(:summary)
      expect(result.summary).to be_a(String)
      expect(result.summary).not_to be_empty
      expect(result.summary.downcase).to match(/science|question|answer|dataset/i)
    end
  end

  describe 'DatasetDescriptor signature' do
    it 'can describe a dataset', vcr: { cassette_name: 'dataset_summary/dataset_descriptor' } do
      examples_payload = described_class.format_examples_for_prompt(small_trainset.take(2))

      predictor = DSPy::Predict.new(DSPy::Propose::DatasetSummaryGenerator::DatasetDescriptor)
      result = predictor.call(examples: examples_payload)

      expect(result).to respond_to(:observations)
      expect(result.observations).to be_a(String)
      expect(result.observations).not_to be_empty
      expect(result.observations.length).to be > 20
    end
  end

  describe 'DatasetDescriptorWithPriorObservations signature' do
    it 'can refine observations', vcr: { cassette_name: 'dataset_summary/refine_observations' } do
      examples_payload = described_class.format_examples_for_prompt(small_trainset.drop(1).take(2))
      prior_observations = "Dataset contains Q&A pairs about scientific topics. Questions are short and direct."

      predictor = DSPy::Predict.new(DSPy::Propose::DatasetSummaryGenerator::DatasetDescriptorWithPriorObservations)
      result = predictor.call(
        examples: examples_payload,
        prior_observations: prior_observations
      )

      expect(result).to respond_to(:observations)
      expect(result.observations).to be_a(String)
      # Either adds new observations or says COMPLETE
      expect(result.observations).not_to be_empty
    end

    it 'can indicate completion', vcr: { cassette_name: 'dataset_summary/indicate_complete' } do
      examples_payload = described_class.format_examples_for_prompt(small_trainset.take(1))
      # Provide very comprehensive prior observations
      prior_observations = "This dataset consists of question-answer pairs focused on natural science phenomena. " \
                          "Questions are concise, averaging 5-7 words. Answers are explanatory and fact-based. " \
                          "Topics span biology (photosynthesis, bird flight) and meteorology (rain). " \
                          "Confidence scores indicate high certainty (0.85-0.9). " \
                          "The task appears to be educational Q&A for science students. " \
                          "Context fields provide background information that directly supports the answers. " \
                          "The dataset exhibits consistency in format and quality across all examples."

      predictor = DSPy::Predict.new(DSPy::Propose::DatasetSummaryGenerator::DatasetDescriptorWithPriorObservations)
      result = predictor.call(
        examples: examples_payload,
        prior_observations: prior_observations
      )

      expect(result).to respond_to(:observations)
      expect(result.observations).to be_a(String)
      # May or may not say COMPLETE depending on LLM, but should respond
      expect(result.observations).not_to be_empty
    end
  end

  describe 'helper functions in integration context' do
    it 'order_input_keys_in_string preserves Example structure' do
      examples_str = small_trainset.inspect
      ordered = described_class.order_input_keys_in_string(examples_str)

      # Should still be valid Ruby array representation
      expect(ordered).to include('Example')
      # Keys should appear in order (context comes before question alphabetically)
      if ordered.include?('input_keys={')
        first_match = ordered.scan(/input_keys=\{([^}]+)\}/).first
        expect(first_match).not_to be_nil
        expect(first_match.first).to match(/context.*question/)
      end
    end

    it 'strip_prefix works on actual LLM outputs', vcr: { cassette_name: 'dataset_summary/strip_prefix_integration' } do
      # Get a real LLM output
      predictor = DSPy::Predict.new(DSPy::Propose::DatasetSummaryGenerator::ObservationSummarizer)
      result = predictor.call(observations: "The dataset has scientific Q&A pairs.")
      original_summary = result.summary

      # Strip any prefix from the output
      stripped = described_class.strip_prefix(original_summary)

      expect(stripped).to be_a(String)
      expect(stripped).not_to be_empty
      # Stripped version should not start with common prefixes
      expect(stripped).not_to match(/^(Answer|Summary|Output):/i)
    end
  end
end
