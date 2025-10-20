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
end
