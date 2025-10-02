# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::ReflectionResult do
  before(:all) { skip 'Skip all GEPA tests until retry logic is optimized' }
  describe 'data structure' do
    let(:reflection_data) do
      {
        trace_id: 'trace-123',
        diagnosis: 'The prompt is too vague and lacks specific instructions for mathematical reasoning.',
        improvements: [
          'Add explicit step-by-step reasoning instructions',
          'Include examples of mathematical problem solving',
          'Specify the expected format for the answer'
        ],
        confidence: 0.85,
        reasoning: 'Based on the execution trace, the model struggled with the arithmetic problem. The prompt should provide more structure.',
        suggested_mutations: [
          :rewrite,
          :expand
        ],
        metadata: {
          reflection_model: 'gpt-4o',
          analysis_timestamp: Time.now,
          trace_count: 5,
          token_usage: 234
        }
      }
    end

    it 'creates an immutable reflection record' do
      result = described_class.new(**reflection_data)
      
      expect(result.trace_id).to eq('trace-123')
      expect(result.diagnosis).to include('too vague')
      expect(result.improvements.size).to eq(3)
      expect(result.confidence).to eq(0.85)
      expect(result.reasoning).to include('execution trace')
      expect(result.suggested_mutations).to contain_exactly(:rewrite, :expand)
      expect(result.metadata[:reflection_model]).to eq('gpt-4o')
    end

    it 'is immutable' do
      result = described_class.new(**reflection_data)
      
      # Should be a Data class (immutable)
      expect(result).to be_a(Data)
      
      # Attempting to modify should raise error
      expect { result.diagnosis = 'new diagnosis' }.to raise_error(NoMethodError)
    end

    it 'freezes nested data structures' do
      result = described_class.new(**reflection_data)
      
      expect(result.improvements).to be_frozen
      expect(result.suggested_mutations).to be_frozen
      expect(result.metadata).to be_frozen
    end

    it 'validates required fields' do
      expect { described_class.new(trace_id: 'test') }.to raise_error(ArgumentError)
      expect { described_class.new(diagnosis: 'test') }.to raise_error(ArgumentError)
      expect { described_class.new(confidence: 0.5) }.to raise_error(ArgumentError)
    end

    it 'validates confidence score range' do
      expect {
        described_class.new(
          trace_id: 'test',
          diagnosis: 'test diagnosis',
          confidence: 1.5,  # Invalid: > 1.0
          improvements: [],
          reasoning: 'test',
          suggested_mutations: [],
          metadata: {}
        )
      }.to raise_error(ArgumentError, /confidence must be between 0 and 1/)

      expect {
        described_class.new(
          trace_id: 'test',
          diagnosis: 'test diagnosis',
          confidence: -0.1,  # Invalid: < 0.0
          improvements: [],
          reasoning: 'test',
          suggested_mutations: [],
          metadata: {}
        )
      }.to raise_error(ArgumentError, /confidence must be between 0 and 1/)
    end
  end

  describe 'convenience methods' do
    let(:result) do
      described_class.new(
        trace_id: 'trace-456',
        diagnosis: 'The model lacks mathematical reasoning structure.',
        improvements: [
          'Add step-by-step instructions',
          'Include calculation examples'
        ],
        confidence: 0.92,
        reasoning: 'Analysis shows consistent arithmetic errors.',
        suggested_mutations: [:expand, :combine],
        metadata: {
          reflection_model: 'gpt-4o',
          token_usage: 156,
          analysis_duration_ms: 1200
        }
      )
    end

    describe '#high_confidence?' do
      it 'returns true for confidence >= 0.8' do
        expect(result.high_confidence?).to be(true)
      end

      it 'returns false for confidence < 0.8' do
        low_confidence = described_class.new(
          trace_id: 'test',
          diagnosis: 'uncertain',
          improvements: [],
          confidence: 0.7,
          reasoning: 'unclear',
          suggested_mutations: [],
          metadata: {}
        )
        expect(low_confidence.high_confidence?).to be(false)
      end
    end

    describe '#actionable?' do
      it 'returns true when improvements and mutations are present' do
        expect(result.actionable?).to be(true)
      end

      it 'returns false when no improvements or mutations' do
        non_actionable = described_class.new(
          trace_id: 'test',
          diagnosis: 'no issues found',
          improvements: [],
          confidence: 0.9,
          reasoning: 'everything looks good',
          suggested_mutations: [],
          metadata: {}
        )
        expect(non_actionable.actionable?).to be(false)
      end
    end

    describe '#mutation_priority' do
      it 'returns sorted mutations by priority' do
        # Alphabetical sorting: combine comes before expand
        expect(result.mutation_priority).to eq([:combine, :expand])
      end
    end

    describe '#to_h' do
      it 'returns reflection as hash' do
        hash = result.to_h
        
        expect(hash).to include(
          trace_id: 'trace-456',
          diagnosis: 'The model lacks mathematical reasoning structure.',
          confidence: 0.92
        )
        expect(hash[:improvements]).to be_an(Array)
        expect(hash[:metadata]).to be_a(Hash)
      end
    end

    describe '#summary' do
      it 'returns concise summary of reflection' do
        summary = result.summary
        
        expect(summary).to include('mathematical reasoning')
        expect(summary).to include('92%')
        expect(summary).to include('2 improvements')
        expect(summary).to include('expand, combine')
      end
    end
  end
end