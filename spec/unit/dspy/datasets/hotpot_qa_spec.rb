# frozen_string_literal: true

require 'spec_helper'
require 'set'

RSpec.describe DSPy::Datasets::HotPotQA do
  class FakeLoader
    def initialize(rows)
      @rows = rows
    end

    def each_row(&block)
      return enum_for(:each_row) unless block

      @rows.each(&block)
    end

    def row_count
      @rows.size
    end
  end

  let(:train_rows) do
    [
      {
        'id' => 'train-hard-1',
        'question' => 'Who wrote War and Peace?',
        'answer' => 'Leo Tolstoy',
        'type' => 'bridge',
        'level' => 'hard',
        'supporting_facts' => { 'title' => ['Leo Tolstoy', 'War and Peace'] },
        'context' => [
          ['Leo Tolstoy', ['Leo Tolstoy was a Russian author.']],
          ['War and Peace', ['War and Peace is a novel by Leo Tolstoy.']]
        ]
      },
      {
        'id' => 'train-medium-1',
        'question' => 'What is the capital of Spain?',
        'answer' => 'Madrid',
        'type' => 'comparison',
        'level' => 'medium'
      },
      {
        'id' => 'train-hard-2',
        'question' => 'Which scientist developed the theory of relativity?',
        'answer' => 'Albert Einstein',
        'type' => 'bridge',
        'level' => 'hard',
        'supporting_facts' => [['Albert Einstein', 0]]
      },
      {
        'id' => 'train-hard-3',
        'question' => 'Who painted The Starry Night?',
        'answer' => 'Vincent van Gogh',
        'type' => 'bridge',
        'level' => 'hard',
        'supporting_facts' => nil
      }
    ]
  end

  let(:validation_rows) do
    [
      {
        'id' => 'val-hard-1',
        'question' => 'What year did the Apollo 11 land on the moon?',
        'answer' => '1969',
        'type' => 'bridge',
        'level' => 'hard',
        'supporting_facts' => [['Apollo 11', 0]]
      },
      {
        'id' => 'val-easy-1',
        'question' => 'What color is the sky?',
        'answer' => 'Blue',
        'type' => 'comparison',
        'level' => 'easy'
      }
    ]
  end

  before do
    allow(DSPy::Datasets::Loaders).to receive(:build) do |info, split:, cache_dir:|
      case split
      when 'train'
        FakeLoader.new(train_rows)
      when 'validation'
        FakeLoader.new(validation_rows)
      else
        raise "Unexpected split: #{split}"
      end
    end
  end

  it 'filters to hard examples and creates train/dev/test splits' do
    dataset = described_class.new(train_seed: 42)

    train = dataset.train
    dev = dataset.dev
    test = dataset.test

    expect(train).to all(include(:question, :answer))
    expect(train.map { |ex| ex[:question] }).to include('Who wrote War and Peace?')
    expect(train.none? { |ex| ex[:question] == 'What is the capital of Spain?' }).to be(true)

    expect(dev).not_to be_empty
    expect(test.size).to eq(1)
    expect(test.first[:question]).to eq('What year did the Apollo 11 land on the moon?')
  end

  it 'normalizes context and gold title values' do
    dataset = described_class.new(train_seed: 0)
    example = (dataset.train + dataset.dev).find { |ex| ex[:question] == 'Who wrote War and Peace?' }

    expect(example).not_to be_nil
    expect(example[:context]).to include('Leo Tolstoy: Leo Tolstoy was a Russian author.')
    expect(example[:gold_titles]).to be_a(Set)
    expect(example[:gold_titles].to_a).to include('Leo Tolstoy', 'War and Peace')
  end
end
