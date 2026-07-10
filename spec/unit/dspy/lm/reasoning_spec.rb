# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Reasoning do
  describe '.low' do
    it 'builds a struct with the Low effort level and nothing else set' do
      reasoning = described_class.low

      expect(reasoning.effort).to eq(described_class::Effort::Low)
      expect(reasoning.budget_tokens).to be_nil
      expect(reasoning.adaptive).to be false
      expect(reasoning.disabled).to be false
    end
  end

  describe '.medium' do
    it 'builds a struct with the Medium effort level' do
      expect(described_class.medium.effort).to eq(described_class::Effort::Medium)
    end
  end

  describe '.high' do
    it 'builds a struct with the High effort level' do
      expect(described_class.high.effort).to eq(described_class::Effort::High)
    end
  end

  describe '.xhigh' do
    it 'builds a struct with the XHigh effort level' do
      expect(described_class.xhigh.effort).to eq(described_class::Effort::XHigh)
    end
  end

  describe '.max' do
    it 'builds a struct with the Max effort level' do
      expect(described_class.max.effort).to eq(described_class::Effort::Max)
    end
  end

  describe '.budget' do
    it 'builds a struct carrying the requested token budget' do
      reasoning = described_class.budget(10_000)

      expect(reasoning.budget_tokens).to eq(10_000)
      expect(reasoning.effort).to be_nil
      expect(reasoning.adaptive).to be false
      expect(reasoning.disabled).to be false
    end
  end

  describe '.adaptive' do
    it 'builds a struct with adaptive set to true and nothing else' do
      reasoning = described_class.adaptive

      expect(reasoning.adaptive).to be true
      expect(reasoning.effort).to be_nil
      expect(reasoning.budget_tokens).to be_nil
      expect(reasoning.disabled).to be false
    end
  end

  describe '.disabled' do
    it 'builds a struct with disabled set to true and nothing else' do
      reasoning = described_class.disabled

      expect(reasoning.disabled).to be true
      expect(reasoning.effort).to be_nil
      expect(reasoning.budget_tokens).to be_nil
      expect(reasoning.adaptive).to be false
    end
  end

  it 'is immutable (T::Struct with const fields)' do
    reasoning = described_class.low

    expect(reasoning).not_to respond_to(:effort=)
  end

  describe DSPy::Reasoning::Effort do
    it 'exposes the five documented Anthropic effort levels' do
      expect(described_class.values.map(&:serialize)).to contain_exactly(
        'low', 'medium', 'high', 'xhigh', 'max'
      )
    end
  end

  describe 'one-mode invariant (PR #257 review)' do
    it 'allows constructing a struct with no mode set at all (equivalent to reasoning: nil)' do
      expect { described_class.new }.not_to raise_error
    end

    it 'allows constructing a struct with exactly one mode set directly' do
      expect { described_class.new(effort: described_class::Effort::High) }.not_to raise_error
      expect { described_class.new(budget_tokens: 2_000) }.not_to raise_error
      expect { described_class.new(adaptive: true) }.not_to raise_error
      expect { described_class.new(disabled: true) }.not_to raise_error
    end

    it 'raises ConfigurationError when effort and budget_tokens are both set' do
      expect {
        described_class.new(effort: described_class::Effort::High, budget_tokens: 2_000)
      }.to raise_error(DSPy::LM::ConfigurationError, /exactly one/i)
    end

    it 'raises ConfigurationError when effort and adaptive are both set' do
      expect {
        described_class.new(effort: described_class::Effort::High, adaptive: true)
      }.to raise_error(DSPy::LM::ConfigurationError, /exactly one/i)
    end

    it 'raises ConfigurationError when budget_tokens and disabled are both set' do
      expect {
        described_class.new(budget_tokens: 2_000, disabled: true)
      }.to raise_error(DSPy::LM::ConfigurationError, /exactly one/i)
    end

    it 'raises ConfigurationError when adaptive and disabled are both set' do
      expect {
        described_class.new(adaptive: true, disabled: true)
      }.to raise_error(DSPy::LM::ConfigurationError, /exactly one/i)
    end

    it 'raises ConfigurationError for three modes set at once' do
      expect {
        described_class.new(effort: described_class::Effort::Low, budget_tokens: 2_000, adaptive: true)
      }.to raise_error(DSPy::LM::ConfigurationError, /exactly one/i)
    end
  end
end
