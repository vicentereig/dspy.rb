require 'spec_helper'
require 'dspy'
require_relative '../../../examples/ade_optimizer_miprov2/ade_example'

RSpec.describe ADEExample do
  describe '.evaluate' do
    it 'counts invalid predictions as false positives' do
      example = DSPy::Example.new(
        signature_class: described_class::ADETextClassifier,
        input: { text: 'Patient reports an itchy rash after medication.' },
        expected: { label: described_class::ADETextClassifier::ADELabel::NotRelated }
      )

      stub_program = instance_double('ADEClassifier')
      allow(stub_program).to receive(:call).and_return('maybe???')

      metrics = described_class.evaluate(stub_program, [example])

      expect(metrics.accuracy).to be < 1.0
    end
  end

  describe '.split_examples' do
    it 'preserves both labels across train/val/test when data contains both' do
      positives = Array.new(5) do |idx|
        DSPy::Example.new(
          signature_class: described_class::ADETextClassifier,
          input: { text: "positive #{idx}" },
          expected: { label: described_class::ADETextClassifier::ADELabel::Related }
        )
      end

      negatives = Array.new(5) do |idx|
        DSPy::Example.new(
          signature_class: described_class::ADETextClassifier,
          input: { text: "negative #{idx}" },
          expected: { label: described_class::ADETextClassifier::ADELabel::NotRelated }
        )
      end

      examples = positives + negatives

      train, val, test = described_class.split_examples(examples, train_ratio: 0.6, val_ratio: 0.2, seed: 1)

      [train, val, test].each do |split|
        labels = split.map { |example| example.expected_values[:label] }
        expect(labels).to include(described_class::ADETextClassifier::ADELabel::Related)
        expect(labels).to include(described_class::ADETextClassifier::ADELabel::NotRelated)
      end
    end
  end
end
