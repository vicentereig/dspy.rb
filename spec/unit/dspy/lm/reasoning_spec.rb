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
end
