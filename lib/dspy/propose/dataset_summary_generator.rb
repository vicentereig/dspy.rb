# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../signature'
require_relative '../predict'

module DSPy
  module Propose
    # Dataset Summary Generator for creating concise dataset descriptions
    # Used by GroundedProposer for data-aware instruction generation
    module DatasetSummaryGenerator
      extend T::Sig

      # Signature for summarizing observations into a brief summary
      class ObservationSummarizer < DSPy::Signature
        description "Given a series of observations I have made about my dataset, please summarize them into a brief 2-3 sentence summary which highlights only the most important details."

        input do
          const :observations, String, description: "Observations I have made about my dataset"
        end

        output do
          const :summary, String, description: "Two to Three sentence summary of only the most significant highlights of my observations"
        end
      end

      # Signature for generating initial dataset observations
      class DatasetDescriptor < DSPy::Signature
        description "Given several examples from a dataset please write observations about trends that hold for most or all of the samples. " \
                   "Some areas you may consider in your observations: topics, content, syntax, conciceness, etc. " \
                   "It will be useful to make an educated guess as to the nature of the task this dataset will enable. Don't be afraid to be creative"

        input do
          const :examples, String, description: "Sample data points from the dataset"
        end

        output do
          const :observations, String, description: "Somethings that holds true for most or all of the data you observed"
        end
      end

      # Signature for refining observations with prior context
      class DatasetDescriptorWithPriorObservations < DSPy::Signature
        description "Given several examples from a dataset please write observations about trends that hold for most or all of the samples. " \
                   "I will also provide you with a few observations I have already made.  Please add your own observations or if you feel the observations are comprehensive say 'COMPLETE' " \
                   "Some areas you may consider in your observations: topics, content, syntax, conciceness, etc. " \
                   "It will be useful to make an educated guess as to the nature of the task this dataset will enable. Don't be afraid to be creative"

        input do
          const :examples, String, description: "Sample data points from the dataset"
          const :prior_observations, String, description: "Some prior observations I made about the data"
        end

        output do
          const :observations, String, description: "Somethings that holds true for most or all of the data you observed or COMPLETE if you have nothing to add"
        end
      end

      # Helper function to ensure consistent ordering of input keys in string representations
      # This helps with caching and consistent LLM prompts
      sig { params(unordered_repr: String).returns(String) }
      def self.order_input_keys_in_string(unordered_repr)
        # Regex pattern to match the input keys structure
        pattern = /input_keys=\{([^}]+)\}/

        # Function to reorder keys
        unordered_repr.gsub(pattern) do |match|
          keys_str = Regexp.last_match(1)
          # Split the keys, strip extra spaces, and sort them
          keys = keys_str.split(',').map(&:strip).sort
          # Format the sorted keys back into the expected structure
          "input_keys={#{keys.join(', ')}}"
        end
      end

      # Strip common prefixes from LLM outputs (e.g., "Answer:", "Output:")
      sig { params(text: String).returns(String) }
      def self.strip_prefix(text)
        # Pattern matches up to 4 words followed by a colon
        pattern = /^[\*\s]*(([\w'\-]+\s+){0,4}[\w'\-]+):\s*/
        modified_text = text.gsub(pattern, '')
        modified_text.strip.gsub(/^["']|["']$/, '')
      end

      # Generate a concise 2-3 sentence summary of a training dataset
      # Used for data-aware instruction proposal in MIPROv2
      #
      # @param trainset [Array<DSPy::Example>] Training examples to summarize
      # @param view_data_batch_size [Integer] Number of examples to process per batch
      # @param prompt_model [DSPy::LM, nil] Language model to use (defaults to DSPy.lm)
      # @param verbose [Boolean] Whether to print progress information
      # @return [String] 2-3 sentence summary of the dataset characteristics
      #
      # @example Basic usage
      #   summary = DatasetSummaryGenerator.create_dataset_summary(
      #     trainset,
      #     view_data_batch_size: 10,
      #     prompt_model: DSPy::LM.new('gpt-4o-mini')
      #   )
      #
      sig do
        params(
          trainset: T::Array[DSPy::Example],
          view_data_batch_size: Integer,
          prompt_model: T.nilable(DSPy::LM),
          verbose: T::Boolean
        ).returns(String)
      end
      def self.create_dataset_summary(trainset, view_data_batch_size, prompt_model, verbose: false)
        if verbose
          puts "\nBootstrapping dataset summary (this will be used to generate instructions)..."
        end

        # Use provided model or fall back to global LM
        lm = prompt_model || DSPy.lm
        raise ArgumentError, "No language model configured. Set prompt_model or DSPy.lm" unless lm

        # Use provided LM in a block context
        DSPy.with_lm(lm) do
          # Initial observation from first batch
          upper_lim = [trainset.length, view_data_batch_size].min
          examples_repr = order_input_keys_in_string(trainset[0...upper_lim].inspect)

          predictor = DSPy::Predict.new(DatasetDescriptor)
          observation = predictor.call(examples: examples_repr)
          observations = observation.observations

          # Iteratively refine observations with additional batches
          skips = 0
          max_calls = 10
          calls = 0

          begin
            (view_data_batch_size...trainset.length).step(view_data_batch_size) do |b|
              calls += 1
              break if calls >= max_calls

              puts "Processing batch starting at index #{b}" if verbose

              upper_lim = [trainset.length, b + view_data_batch_size].min
              examples_repr = order_input_keys_in_string(trainset[b...upper_lim].inspect)

              predictor = DSPy::Predict.new(DatasetDescriptorWithPriorObservations)
              output = predictor.call(
                prior_observations: observations,
                examples: examples_repr
              )

              # Check if LLM indicates observations are complete
              if output.observations.length >= 8 && output.observations[0...8].upcase == "COMPLETE"
                skips += 1
                break if skips >= 5
                next
              end

              observations += output.observations
            end
          rescue => e
            if verbose
              puts "Error during observation refinement: #{e.message}. Using observations from past round for summary."
            end
          end

          # Generate final summary from accumulated observations
          predictor = DSPy::Predict.new(ObservationSummarizer)
          summary = predictor.call(observations: observations)

          if verbose
            puts "\nGenerated summary: #{strip_prefix(summary.summary)}\n"
          end

          strip_prefix(summary.summary)
        end
      end
    end
  end
end
