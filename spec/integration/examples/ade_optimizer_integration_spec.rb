require 'spec_helper'
require_relative '../../../examples/ade_optimizer_miprov2/ade_example'

RSpec.describe 'ADE optimizer integration' do
  let(:positive_label) { ADEExample::ADETextClassifier::ADELabel::Related }
  let(:negative_label) { ADEExample::ADETextClassifier::ADELabel::NotRelated }

  def build_example(label, text)
    DSPy::Example.new(
      signature_class: ADEExample::ADETextClassifier,
      input: { text: text },
      expected: { label: label }
    )
  end

  it 'drops precision below 100% when the model emits malformed outputs' do
    positives = Array.new(6) { |idx| build_example(positive_label, "positive #{idx}") }
    negatives = Array.new(6) { |idx| build_example(negative_label, "negative #{idx}") }

    train, val, test = ADEExample.split_examples(
      positives + negatives,
      train_ratio: 0.6,
      val_ratio: 0.2,
      seed: 3
    )

    # Ensure stratified split keeps label coverage across all partitions
    [train, val, test].each do |split|
      labels = split.map { |example| example.expected_values[:label] }
      expect(labels).to include(positive_label)
      expect(labels).to include(negative_label)
    end

    responses = test.map do |example|
      example.expected_values[:label] == negative_label ? 'not sure' : positive_label
    end

    stub_program = instance_double('ADEClassifier')
    allow(stub_program).to receive(:call) do |text:|
      responses.shift
    end

    metrics = ADEExample.evaluate(stub_program, test)

    expect(metrics.precision).to be < 1.0
  end
end
