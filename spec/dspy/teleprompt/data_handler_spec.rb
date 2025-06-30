require 'spec_helper'
require 'ostruct'
require 'dspy/teleprompt/data_handler'
require 'dspy/signature'
require 'dspy/example'

# Test signature for data handler testing
class DataMath < DSPy::Signature
  description "Math problems for data handling tests."

  input do
    const :problem, String
  end

  output do
    const :answer, Integer
    const :category, String
  end
end

RSpec.describe DSPy::Teleprompt::DataHandler do
  let(:test_examples) do
    [
      DSPy::Example.new(
        signature_class: DataMath,
        input: { problem: "2 + 2" },
        expected: { answer: 4, category: "addition" },
        id: "example_1"
      ),
      DSPy::Example.new(
        signature_class: DataMath,
        input: { problem: "5 - 3" },
        expected: { answer: 2, category: "subtraction" },
        id: "example_2"
      ),
      DSPy::Example.new(
        signature_class: DataMath,
        input: { problem: "3 × 4" },
        expected: { answer: 12, category: "multiplication" },
        id: "example_3"
      ),
      DSPy::Example.new(
        signature_class: DataMath,
        input: { problem: "8 ÷ 2" },
        expected: { answer: 4, category: "division" },
        id: "example_4"
      ),
      DSPy::Example.new(
        signature_class: DataMath,
        input: { problem: "10 + 5" },
        expected: { answer: 15, category: "addition" },
        id: "example_5"
      )
    ]
  end

  let(:data_handler) { DSPy::Teleprompt::DataHandler.new(test_examples) }

  describe 'initialization' do
    it 'creates data handler with examples' do
      expect(data_handler.examples).to eq(test_examples)
      expect(data_handler.examples.size).to eq(5)
    end

    it 'handles empty examples' do
      empty_handler = DSPy::Teleprompt::DataHandler.new([])
      expect(empty_handler.examples).to be_empty
    end

    it 'stores examples directly' do
      expect(data_handler.examples.all? { |ex| ex.is_a?(DSPy::Example) }).to be(true)
    end
  end

  describe '#sample' do
    it 'samples requested number of examples' do
      sampled = data_handler.sample(3)
      expect(sampled.size).to eq(3)
      expect(sampled.all? { |ex| ex.is_a?(DSPy::Example) }).to be(true)
    end

    it 'samples with random state for reproducibility' do
      sample1 = data_handler.sample(3, random_state: 42)
      sample2 = data_handler.sample(3, random_state: 42)
      
      expect(sample1.map(&:id)).to eq(sample2.map(&:id))
    end

    it 'handles sampling more than available examples' do
      sampled = data_handler.sample(10)
      expect(sampled.size).to eq(5) # Should return all available examples
    end

    it 'returns empty array when sampling zero' do
      sampled = data_handler.sample(0)
      expect(sampled).to be_empty
    end
  end

  describe '#shuffle' do
    it 'returns all examples in different order' do
      shuffled = data_handler.shuffle
      expect(shuffled.size).to eq(5)
      expect(shuffled.all? { |ex| ex.is_a?(DSPy::Example) }).to be(true)
    end

    it 'provides reproducible shuffling with random state' do
      shuffle1 = data_handler.shuffle(random_state: 123)
      shuffle2 = data_handler.shuffle(random_state: 123)
      
      expect(shuffle1.map(&:id)).to eq(shuffle2.map(&:id))
    end

    it 'actually changes order (statistically)' do
      # Run shuffle multiple times and expect at least one different ordering
      original_ids = test_examples.map(&:id)
      different_order_found = false
      
      10.times do
        shuffled_ids = data_handler.shuffle.map(&:id)
        if shuffled_ids != original_ids
          different_order_found = true
          break
        end
      end
      
      expect(different_order_found).to be(true)
    end
  end

  describe '#each_batch' do
    it 'yields batches of specified size' do
      batches = []
      data_handler.each_batch(2).each do |batch|
        batches << batch
      end
      
      expect(batches.size).to eq(3) # 5 examples / 2 per batch = 3 batches
      expect(batches[0].size).to eq(2)
      expect(batches[1].size).to eq(2)
      expect(batches[2].size).to eq(1) # Last batch with remainder
    end

    it 'handles batch size larger than total examples' do
      batches = []
      data_handler.each_batch(10).each do |batch|
        batches << batch
      end
      
      expect(batches.size).to eq(1)
      expect(batches[0].size).to eq(5)
    end

    it 'returns enumerator when no block given' do
      enumerator = data_handler.each_batch(2)
      expect(enumerator).to be_a(Enumerator)
      
      first_batch = enumerator.next
      expect(first_batch.size).to eq(2)
    end
  end

  describe '#partition_by_success' do
    it 'partitions examples by success indices' do
      successful_indices = [0, 2, 4] # First, third, and fifth examples
      
      successful, failed = data_handler.partition_by_success(successful_indices)
      
      expect(successful.size).to eq(3)
      expect(failed.size).to eq(2)
      expect(successful.map(&:id)).to include("example_1", "example_3", "example_5")
      expect(failed.map(&:id)).to include("example_2", "example_4")
    end

    it 'handles empty success indices' do
      successful, failed = data_handler.partition_by_success([])
      
      expect(successful).to be_empty
      expect(failed.size).to eq(5)
    end

    it 'handles all success indices' do
      all_indices = (0...test_examples.size).to_a
      successful, failed = data_handler.partition_by_success(all_indices)
      
      expect(successful.size).to eq(5)
      expect(failed).to be_empty
    end
  end

  describe '#stratified_sample' do
    it 'performs stratified sampling by category' do
      # This test assumes the dataframe has a column for category
      # Since our conversion flattens expected values, we should have 'expected_category'
      sampled = data_handler.stratified_sample(4, stratify_column: 'expected_category')
      
      expect(sampled.size).to be <= 4
      expect(sampled.all? { |ex| ex.is_a?(DSPy::Example) }).to be(true)
    end

    it 'falls back to regular sampling for non-existent column' do
      sampled = data_handler.stratified_sample(3, stratify_column: 'non_existent')
      
      expect(sampled.size).to eq(3)
    end

    it 'falls back to regular sampling when no stratify column provided' do
      sampled = data_handler.stratified_sample(3)
      
      expect(sampled.size).to eq(3)
    end
  end

  describe '#create_candidate_sets' do
    it 'creates multiple candidate sets' do
      sets = data_handler.create_candidate_sets(3, 2)
      
      expect(sets.size).to eq(3)
      expect(sets.all? { |set| set.size == 2 }).to be(true)
      expect(sets.all? { |set| set.all? { |ex| ex.is_a?(DSPy::Example) } }).to be(true)
    end

    it 'creates reproducible sets with random state' do
      sets1 = data_handler.create_candidate_sets(2, 2, random_state: 42)
      sets2 = data_handler.create_candidate_sets(2, 2, random_state: 42)
      
      expect(sets1.map { |set| set.map(&:id) }).to eq(sets2.map { |set| set.map(&:id) })
    end

    it 'handles set size larger than available examples' do
      sets = data_handler.create_candidate_sets(2, 10)
      
      expect(sets.size).to eq(2)
      expect(sets.all? { |set| set.size == 5 }).to be(true) # Should use all available
    end

    it 'creates empty sets when no examples available' do
      empty_handler = DSPy::Teleprompt::DataHandler.new([])
      sets = empty_handler.create_candidate_sets(3, 2)
      
      expect(sets.size).to eq(3)
      expect(sets.all?(&:empty?)).to be(true)
    end
  end

  describe '#statistics' do
    it 'provides data statistics' do
      stats = data_handler.statistics
      
      expect(stats[:total_examples]).to eq(5)
      expect(stats[:example_types]).to be_an(Array)
      expect(stats[:memory_usage_estimate]).to be_a(Numeric)
    end

    it 'includes relevant information in statistics' do
      stats = data_handler.statistics
      
      expect(stats[:example_types]).to include('DSPy::Example')
      expect(stats[:memory_usage_estimate]).to be > 0
    end
  end

  describe 'data conversion' do
    context 'with hash-based examples' do
      let(:hash_examples) do
        [
          {
            input: { problem: "1 + 1" },
            expected: { answer: 2, category: "addition" }
          },
          {
            input: { problem: "3 - 1" },
            expected: { answer: 2, category: "subtraction" }
          }
        ]
      end

      it 'handles hash examples' do
        hash_handler = DSPy::Teleprompt::DataHandler.new(hash_examples)
        
        expect(hash_handler.examples.size).to eq(2)
        expect(hash_handler.examples).to eq(hash_examples)
      end

      it 'allows sampling of hash examples' do
        hash_handler = DSPy::Teleprompt::DataHandler.new(hash_examples)
        sampled = hash_handler.sample(1)
        
        expect(sampled.size).to eq(1)
        expect(sampled.first).to be_a(Hash)
      end
    end

    context 'with object-based examples' do
      let(:object_examples) do
        [
          OpenStruct.new(
            input: { problem: "4 ÷ 2" },
            expected: { answer: 2, category: "division" }
          ),
          OpenStruct.new(
            input: { problem: "5 × 2" },
            expected: { answer: 10, category: "multiplication" }
          )
        ]
      end

      it 'handles object examples' do
        object_handler = DSPy::Teleprompt::DataHandler.new(object_examples)
        
        expect(object_handler.examples.size).to eq(2)
      end

      it 'preserves original objects in sampling' do
        object_handler = DSPy::Teleprompt::DataHandler.new(object_examples)
        sampled = object_handler.sample(1)
        
        expect(sampled.size).to eq(1)
        expect(sampled.first).to be_an(OpenStruct)
      end
    end
  end

  describe 'edge cases' do
    it 'handles various example formats' do
      mixed_examples = [
        test_examples.first,
        { input: { problem: "hash example" }, expected: { answer: 42, category: "test" } }
      ]
      
      handler = DSPy::Teleprompt::DataHandler.new(mixed_examples)
      expect(handler.examples.size).to eq(2)
    end

    it 'handles examples with complex nested data' do
      complex_example = DSPy::Example.new(
        signature_class: DataMath,
        input: { problem: "complex" },
        expected: { answer: 42, category: "complex" },
        metadata: { 
          tags: ["test", "complex"], 
          settings: { level: "hard", timed: true }
        }
      )
      
      handler = DSPy::Teleprompt::DataHandler.new([complex_example])
      expect(handler.examples.size).to eq(1)
      
      # Should be able to sample the complex example
      sampled = handler.sample(1)
      expect(sampled.first).to eq(complex_example)
    end
  end
end