# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Teleprompt::GEPA::FitnessEvaluator do
  # Test signature for fitness evaluation
  class FitnessTestSignature < DSPy::Signature
    description "Test signature for fitness evaluation"

    input do
      const :question, String
    end
    
    output do
      const :answer, String
      const :confidence, Float
    end
  end

  let(:primary_metric) { proc { |example, prediction| example.expected_values[:answer] == prediction.answer ? 1.0 : 0.0 } }
  
  let(:config) do
    DSPy::Teleprompt::GEPA::GEPAConfig.new
  end

  let(:trainset) do
    [
      DSPy::Example.new(
        signature_class: FitnessTestSignature,
        input: { question: 'What is 2+2?' },
        expected: { answer: '4', confidence: 0.9 }
      ),
      DSPy::Example.new(
        signature_class: FitnessTestSignature,
        input: { question: 'What is 3+3?' },
        expected: { answer: '6', confidence: 0.8 }
      )
    ]
  end

  let(:mock_program) do
    double('program', signature_class: FitnessTestSignature)
  end

  describe 'initialization' do
    it 'creates evaluator with primary metric and config' do
      evaluator = described_class.new(primary_metric: primary_metric, config: config)
      
      expect(evaluator.primary_metric).to eq(primary_metric)
      expect(evaluator.config).to eq(config)
    end

    it 'initializes with default secondary metrics' do
      evaluator = described_class.new(primary_metric: primary_metric, config: config)
      
      expect(evaluator.secondary_metrics).to include(:token_efficiency, :consistency, :latency)
    end

    it 'allows custom secondary metrics' do
      custom_metrics = { custom_score: proc { |prog, ex| 0.5 } }
      evaluator = described_class.new(primary_metric: primary_metric, config: config, secondary_metrics: custom_metrics)
      
      expect(evaluator.secondary_metrics).to include(:custom_score)
    end

    it 'requires primary_metric parameter' do
      expect { described_class.new(config: config) }.to raise_error(ArgumentError)
    end
  end

  describe '#evaluate_candidate' do
    let(:evaluator) { described_class.new(primary_metric: primary_metric, config: config) }

    before do
      # Mock program responses
      allow(mock_program).to receive(:call).with(question: 'What is 2+2?').and_return(
        double('prediction', answer: '4', confidence: 0.9)
      )
      allow(mock_program).to receive(:call).with(question: 'What is 3+3?').and_return(
        double('prediction', answer: '6', confidence: 0.8)
      )
    end

    it 'returns FitnessScore with all metrics' do
      score = evaluator.evaluate_candidate(mock_program, trainset)
      
      expect(score).to be_a(DSPy::Teleprompt::GEPA::FitnessScore)
      expect(score.primary_score).to be_between(0.0, 1.0)
      expect(score.secondary_scores).to be_a(Hash)
      expect(score.overall_score).to be_between(0.0, 1.0)
    end

    it 'calculates primary metric correctly' do
      score = evaluator.evaluate_candidate(mock_program, trainset)
      
      # Both predictions should be correct -> 1.0
      expect(score.primary_score).to eq(1.0)
    end

    it 'includes secondary metric scores' do
      score = evaluator.evaluate_candidate(mock_program, trainset)
      
      expect(score.secondary_scores).to include(:token_efficiency, :consistency, :latency)
      score.secondary_scores.each { |_, value| expect(value).to be_between(0.0, 1.0) }
    end

    it 'handles prediction errors gracefully' do
      allow(mock_program).to receive(:call).and_raise(StandardError, 'Prediction error')
      
      score = evaluator.evaluate_candidate(mock_program, trainset)
      
      expect(score.primary_score).to eq(0.0)
      expect(score.overall_score).to be <= 0.2 # Very low due to errors
    end

    it 'calculates weighted overall score' do
      score = evaluator.evaluate_candidate(mock_program, trainset)
      
      # Overall score should be weighted combination of primary and secondary
      expected_min = score.primary_score * 0.6 # 60% weight on primary
      expect(score.overall_score).to be >= expected_min
    end
  end

  describe '#batch_evaluate' do
    let(:evaluator) { described_class.new(primary_metric: primary_metric, config: config) }
    
    let(:programs) do
      [
        double('program1', signature_class: FitnessTestSignature),
        double('program2', signature_class: FitnessTestSignature)
      ]
    end

    before do
      # Mock first program (perfect accuracy)
      allow(programs[0]).to receive(:call).and_return(
        double('prediction', answer: '4', confidence: 0.9)
      ).with(question: 'What is 2+2?')
      allow(programs[0]).to receive(:call).and_return(
        double('prediction', answer: '6', confidence: 0.8)
      ).with(question: 'What is 3+3?')

      # Mock second program (partial accuracy)
      allow(programs[1]).to receive(:call).and_return(
        double('prediction', answer: '4', confidence: 0.7)
      ).with(question: 'What is 2+2?')
      allow(programs[1]).to receive(:call).and_return(
        double('prediction', answer: 'wrong', confidence: 0.5)
      ).with(question: 'What is 3+3?')
    end

    it 'evaluates multiple programs' do
      scores = evaluator.batch_evaluate(programs, trainset)
      
      expect(scores).to be_an(Array)
      expect(scores.size).to eq(programs.size)
      scores.each { |score| expect(score).to be_a(DSPy::Teleprompt::GEPA::FitnessScore) }
    end

    it 'maintains relative performance ordering' do
      scores = evaluator.batch_evaluate(programs, trainset)
      
      # Program 0 should outperform program 1
      expect(scores[0].overall_score).to be > scores[1].overall_score
    end

    it 'handles empty program list' do
      scores = evaluator.batch_evaluate([], trainset)
      
      expect(scores).to be_empty
    end
  end

  describe '#compare_candidates' do
    let(:evaluator) { described_class.new(primary_metric: primary_metric, config: config) }

    let(:high_score) do
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.9,
        secondary_scores: { token_efficiency: 0.8, consistency: 0.9, latency: 0.7 },
        overall_score: 0.85
      )
    end

    let(:low_score) do
      DSPy::Teleprompt::GEPA::FitnessScore.new(
        primary_score: 0.6,
        secondary_scores: { token_efficiency: 0.5, consistency: 0.6, latency: 0.8 },
        overall_score: 0.6
      )
    end

    it 'returns positive value when first candidate is better' do
      comparison = evaluator.compare_candidates(high_score, low_score)
      expect(comparison).to be > 0
    end

    it 'returns negative value when second candidate is better' do
      comparison = evaluator.compare_candidates(low_score, high_score)
      expect(comparison).to be < 0
    end

    it 'returns zero for identical candidates' do
      comparison = evaluator.compare_candidates(high_score, high_score)
      expect(comparison).to eq(0)
    end
  end

  describe '#rank_candidates' do
    let(:evaluator) { described_class.new(primary_metric: primary_metric, config: config) }
    
    let(:scores) do
      [
        DSPy::Teleprompt::GEPA::FitnessScore.new(primary_score: 0.6, secondary_scores: {}, overall_score: 0.6),
        DSPy::Teleprompt::GEPA::FitnessScore.new(primary_score: 0.9, secondary_scores: {}, overall_score: 0.9),
        DSPy::Teleprompt::GEPA::FitnessScore.new(primary_score: 0.7, secondary_scores: {}, overall_score: 0.7)
      ]
    end

    it 'returns candidates sorted by fitness (best first)' do
      ranked_indices = evaluator.rank_candidates(scores)
      
      expect(ranked_indices).to eq([1, 2, 0]) # Index 1 has highest score (0.9)
    end

    it 'handles empty scores array' do
      ranked = evaluator.rank_candidates([])
      expect(ranked).to be_empty
    end

    it 'handles single candidate' do
      ranked = evaluator.rank_candidates([scores.first])
      expect(ranked).to eq([0])
    end
  end

  describe 'secondary metrics' do
    let(:evaluator) { described_class.new(primary_metric: primary_metric, config: config) }

    describe '#calculate_token_efficiency' do
      it 'measures token usage efficiency' do
        # Mock trace data for token calculation
        traces = [
          double('trace', token_usage: 100),
          double('trace', token_usage: 50)
        ]
        
        efficiency = evaluator.send(:calculate_token_efficiency, traces, 2)
        
        expect(efficiency).to be_between(0.0, 1.0)
        expect(efficiency).to be < 1.0 # Penalized for high token usage
      end

      it 'returns high efficiency for minimal token usage' do
        traces = [double('trace', token_usage: 10)]
        efficiency = evaluator.send(:calculate_token_efficiency, traces, 1)
        
        expect(efficiency).to be > 0.9
      end
    end

    describe '#calculate_consistency' do
      it 'measures response consistency across examples' do
        responses = ['Answer: 4', 'Answer: 6', 'Answer: 8']
        consistency = evaluator.send(:calculate_consistency, responses)
        
        expect(consistency).to be_between(0.0, 1.0)
      end

      it 'returns high consistency for similar responses' do
        responses = ['The answer is 4', 'The answer is 6', 'The answer is 8']
        consistency = evaluator.send(:calculate_consistency, responses)
        
        expect(consistency).to be > 0.5 # Similar structure
      end
    end

    describe '#calculate_latency_score' do
      it 'measures response latency performance' do
        latencies = [0.5, 1.0, 0.8] # seconds
        latency_score = evaluator.send(:calculate_latency_score, latencies)
        
        expect(latency_score).to be_between(0.0, 1.0)
        expect(latency_score).to be > 0.5 # Reasonable latencies
      end
    end
  end
end