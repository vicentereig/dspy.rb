# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::ObservationType do
  describe 'enum values' do
    it 'defines all Langfuse observation types' do
      expect(DSPy::ObservationType::Generation.serialize).to eq('generation')
      expect(DSPy::ObservationType::Agent.serialize).to eq('agent')
      expect(DSPy::ObservationType::Tool.serialize).to eq('tool')
      expect(DSPy::ObservationType::Chain.serialize).to eq('chain')
      expect(DSPy::ObservationType::Retriever.serialize).to eq('retriever')
      expect(DSPy::ObservationType::Embedding.serialize).to eq('embedding')
      expect(DSPy::ObservationType::Evaluator.serialize).to eq('evaluator')
      expect(DSPy::ObservationType::Span.serialize).to eq('span')
      expect(DSPy::ObservationType::Event.serialize).to eq('event')
    end

    it 'can deserialize from string values' do
      expect(DSPy::ObservationType.deserialize('generation')).to eq(DSPy::ObservationType::Generation)
      expect(DSPy::ObservationType.deserialize('agent')).to eq(DSPy::ObservationType::Agent)
      expect(DSPy::ObservationType.deserialize('tool')).to eq(DSPy::ObservationType::Tool)
      expect(DSPy::ObservationType.deserialize('chain')).to eq(DSPy::ObservationType::Chain)
      expect(DSPy::ObservationType.deserialize('retriever')).to eq(DSPy::ObservationType::Retriever)
      expect(DSPy::ObservationType.deserialize('embedding')).to eq(DSPy::ObservationType::Embedding)
      expect(DSPy::ObservationType.deserialize('evaluator')).to eq(DSPy::ObservationType::Evaluator)
      expect(DSPy::ObservationType.deserialize('span')).to eq(DSPy::ObservationType::Span)
      expect(DSPy::ObservationType.deserialize('event')).to eq(DSPy::ObservationType::Event)
    end
  end

  describe '.for_module_class' do
    it 'returns Agent for ReAct modules' do
      expect(DSPy::ObservationType.for_module_class(DSPy::ReAct)).to eq(DSPy::ObservationType::Agent)
    end

    it 'returns Chain for ChainOfThought modules' do
      expect(DSPy::ObservationType.for_module_class(DSPy::ChainOfThought)).to eq(DSPy::ObservationType::Chain)
    end

    it 'returns Agent for CodeAct modules' do
      expect(DSPy::ObservationType.for_module_class(DSPy::CodeAct)).to eq(DSPy::ObservationType::Agent)
    end

    it 'returns Span for Predict modules' do
      expect(DSPy::ObservationType.for_module_class(DSPy::Predict)).to eq(DSPy::ObservationType::Span)
    end

    it 'returns Span for unknown module classes' do
      unknown_class = Class.new(DSPy::Module)
      expect(DSPy::ObservationType.for_module_class(unknown_class)).to eq(DSPy::ObservationType::Span)
    end
  end

  describe '.langfuse_attribute' do
    it 'returns the correct attribute key and value for each type' do
      expect(DSPy::ObservationType::Generation.langfuse_attribute).to eq(['langfuse.observation.type', 'generation'])
      expect(DSPy::ObservationType::Agent.langfuse_attribute).to eq(['langfuse.observation.type', 'agent'])
      expect(DSPy::ObservationType::Tool.langfuse_attribute).to eq(['langfuse.observation.type', 'tool'])
      expect(DSPy::ObservationType::Chain.langfuse_attribute).to eq(['langfuse.observation.type', 'chain'])
      expect(DSPy::ObservationType::Retriever.langfuse_attribute).to eq(['langfuse.observation.type', 'retriever'])
      expect(DSPy::ObservationType::Embedding.langfuse_attribute).to eq(['langfuse.observation.type', 'embedding'])
      expect(DSPy::ObservationType::Evaluator.langfuse_attribute).to eq(['langfuse.observation.type', 'evaluator'])
      expect(DSPy::ObservationType::Span.langfuse_attribute).to eq(['langfuse.observation.type', 'span'])
      expect(DSPy::ObservationType::Event.langfuse_attribute).to eq(['langfuse.observation.type', 'event'])
    end
  end

  describe '.langfuse_attributes' do
    it 'returns a hash with the langfuse attribute for each type' do
      expect(DSPy::ObservationType::Generation.langfuse_attributes).to eq({'langfuse.observation.type' => 'generation'})
      expect(DSPy::ObservationType::Agent.langfuse_attributes).to eq({'langfuse.observation.type' => 'agent'})
      expect(DSPy::ObservationType::Tool.langfuse_attributes).to eq({'langfuse.observation.type' => 'tool'})
    end
  end
end