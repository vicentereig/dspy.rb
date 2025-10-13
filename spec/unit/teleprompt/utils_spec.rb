# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::Utils do
  describe '.create_minibatch' do
    let(:trainset) { (1..10).to_a }

    it 'returns a minibatch of specified size' do
      batch = described_class.create_minibatch(trainset, 5)

      expect(batch.size).to eq(5)
      batch.each do |item|
        expect(trainset).to include(item)
      end
    end

    it 'returns entire dataset when batch_size exceeds dataset size' do
      batch = described_class.create_minibatch(trainset, 20)

      expect(batch.size).to eq(trainset.size)
      expect(batch.sort).to eq(trainset.sort)
    end

    it 'uses provided RNG for reproducible sampling' do
      rng1 = Random.new(42)
      rng2 = Random.new(42)

      batch1 = described_class.create_minibatch(trainset, 5, rng1)
      batch2 = described_class.create_minibatch(trainset, 5, rng2)

      expect(batch1).to eq(batch2)
    end

    it 'samples without replacement' do
      batch = described_class.create_minibatch(trainset, 5)

      expect(batch.uniq.size).to eq(batch.size)
    end

    it 'returns different samples across multiple calls without seeded RNG' do
      batches = 10.times.map { described_class.create_minibatch(trainset, 5) }
      unique_batches = batches.uniq

      # With 10 samples from 10 items, we should get at least 2 different batches
      expect(unique_batches.size).to be > 1
    end
  end
end
