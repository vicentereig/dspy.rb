# frozen_string_literal: true

require 'sorbet-runtime'
require_relative '../example'

module DSPy
  module Teleprompt
    # Data handling for optimization with efficient operations
    # Provides operations for large datasets during bootstrap and optimization
    class DataHandler
      extend T::Sig

      sig { returns(T::Array[T.untyped]) }
      attr_reader :examples

      sig { params(examples: T::Array[T.untyped]).void }
      def initialize(examples)
        @examples = examples
      end

      # Sample examples efficiently
      sig { params(n: Integer, random_state: T.nilable(Integer)).returns(T::Array[T.untyped]) }
      def sample(n, random_state: nil)
        return [] if @examples.empty? || n <= 0
        
        # Handle case where n is larger than available examples
        actual_n = [n, @examples.size].min
        
        # Set random seed if provided
        if random_state
          srand(random_state)
        end

        @examples.sample(actual_n)
      end

      # Shuffle examples efficiently
      sig { params(random_state: T.nilable(Integer)).returns(T::Array[T.untyped]) }
      def shuffle(random_state: nil)
        if random_state
          srand(random_state)
        end

        @examples.shuffle
      end

      # Get examples in batches for processing
      sig { params(batch_size: Integer).returns(T::Enumerator[T::Array[T.untyped]]) }
      def each_batch(batch_size)
        @examples.each_slice(batch_size)
      end

      # Filter examples based on success/failure
      sig { params(successful_indices: T::Array[Integer]).returns([T::Array[T.untyped], T::Array[T.untyped]]) }
      def partition_by_success(successful_indices)
        successful_examples = successful_indices.map { |i| @examples[i] if i < @examples.size }.compact
        failed_indices = (0...@examples.size).to_a - successful_indices
        failed_examples = failed_indices.map { |i| @examples[i] }

        [successful_examples, failed_examples]
      end

      # Create stratified samples maintaining distribution
      sig { params(n: Integer, stratify_column: T.nilable(String)).returns(T::Array[T.untyped]) }
      def stratified_sample(n, stratify_column: nil)
        # For now, fall back to regular sampling (can be enhanced later)
        sample(n)
      end

      # Get statistics about the data
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def statistics
        {
          total_examples: @examples.size,
          example_types: @examples.map(&:class).uniq.map(&:name),
          memory_usage_estimate: @examples.size * 1000 # Rough estimate
        }
      end

      # Create multiple candidate sets efficiently
      sig { params(num_sets: Integer, set_size: Integer, random_state: T.nilable(Integer)).returns(T::Array[T::Array[T.untyped]]) }
      def create_candidate_sets(num_sets, set_size, random_state: nil)
        return Array.new(num_sets) { [] } if @examples.empty?
        
        if random_state
          srand(random_state)
        end

        candidate_sets = []
        actual_set_size = [set_size, @examples.size].min
        
        num_sets.times do |i|
          # Use different random state for each set to ensure variety
          current_seed = random_state ? random_state + i : nil
          if current_seed
            srand(current_seed)
          end
          
          set_examples = @examples.sample(actual_set_size)
          candidate_sets << set_examples
        end

        candidate_sets
      end
    end
  end
end