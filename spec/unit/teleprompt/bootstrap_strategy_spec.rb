# frozen_string_literal: true

require 'spec_helper'
require 'dspy/teleprompt/bootstrap_strategy'

RSpec.describe DSPy::Teleprompt::BootstrapStrategy do
  it 'defines all bootstrap strategies' do
    expect(described_class.values).to contain_exactly(
      DSPy::Teleprompt::BootstrapStrategy::ZeroShot,
      DSPy::Teleprompt::BootstrapStrategy::LabeledOnly,
      DSPy::Teleprompt::BootstrapStrategy::Unshuffled,
      DSPy::Teleprompt::BootstrapStrategy::Shuffled
    )
  end

  describe 'ZeroShot' do
    it 'represents zero-shot strategy (no demos)' do
      expect(DSPy::Teleprompt::BootstrapStrategy::ZeroShot).to be_a(DSPy::Teleprompt::BootstrapStrategy)
    end
  end

  describe 'LabeledOnly' do
    it 'represents labeled-only strategy' do
      expect(DSPy::Teleprompt::BootstrapStrategy::LabeledOnly).to be_a(DSPy::Teleprompt::BootstrapStrategy)
    end
  end

  describe 'Unshuffled' do
    it 'represents unshuffled bootstrap strategy' do
      expect(DSPy::Teleprompt::BootstrapStrategy::Unshuffled).to be_a(DSPy::Teleprompt::BootstrapStrategy)
    end
  end

  describe 'Shuffled' do
    it 'represents shuffled bootstrap strategy' do
      expect(DSPy::Teleprompt::BootstrapStrategy::Shuffled).to be_a(DSPy::Teleprompt::BootstrapStrategy)
    end
  end
end
