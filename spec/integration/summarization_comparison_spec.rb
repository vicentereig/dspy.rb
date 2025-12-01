# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Summarization Comparison: Predict vs ChainOfThought', :vcr do
  let(:openai_lm) { DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY']) }

  # Signature for summarization
  class Summarize < DSPy::Signature
    description "Summarize the given text concisely while preserving key concepts"

    input do
      const :text, String, description: "Text to summarize"
    end

    output do
      const :summary, String, description: "Concise summary preserving key concepts"
    end
  end

  # Signature for LLM judge (G-Eval style multi-dimensional evaluation)
  # Each dimension is a direct output field with its own description
  class EvaluateSummary < DSPy::Signature
    description <<~DESC.strip
      Evaluate summary quality using G-Eval criteria.
      Be critical and objective - most summaries should score 3-4, not 5.
    DESC

    input do
      const :source_text, String, description: "Original text"
      const :summary, String, description: "Summary to evaluate"
    end

    output do
      const :faithfulness, Integer,
        description: "Score 1-5: Is the summary factually accurate? Does it avoid hallucinations?"
      const :relevance, Integer,
        description: "Score 1-5: Does the summary capture the most important information?"
      const :coherence, Integer,
        description: "Score 1-5: Is the summary well-structured with logical flow?"
      const :fluency, Integer,
        description: "Score 1-5: Is the summary grammatically correct and readable?"
      const :overall_score, Float,
        description: "Overall quality score from 1.0 to 5.0"
    end
  end

  before do
    DSPy.configure do |config|
      config.lm = openai_lm
    end
  end

  let(:wikipedia_photosynthesis) do
    <<~DOC
      Photosynthesis is a biological process used by many cellular organisms to convert light energy into chemical energy, which is stored in organic compounds that can later be metabolized through cellular respiration to fuel the organism's activities. The term usually refers to oxygenic photosynthesis, where oxygen is produced as a byproduct and some of the chemical energy produced is stored in carbohydrate molecules such as sugars, starch, glycogen and cellulose, which are synthesized from endergonic reaction of carbon dioxide with water. Most plants, algae, and cyanobacteria perform photosynthesis; such organisms are called photoautotrophs.
    DOC
  end

  let(:wikipedia_byzantine) do
    <<~DOC
      The Byzantine Empire, also referred to as the Eastern Roman Empire, was the continuation of the Roman Empire centred in Constantinople during Late Antiquity and the Middle Ages. The eastern half of the Empire survived for another millennium after the fall of the western half in 476 AD. During most of its existence, the empire remained the most powerful economic, cultural, and military force in the Mediterranean world. The term "Byzantine Empire" was coined after the fall of Constantinople in 1453; its citizens continued to refer to their empire as the Roman Empire and to themselves as Romans.
    DOC
  end

  describe 'Summarize signature' do
    it 'works with DSPy::Predict', vcr: { cassette_name: 'summarization/predict_simple' } do
      predict = DSPy::Predict.new(Summarize)
      result = predict.call(text: wikipedia_photosynthesis)

      expect(result).to respond_to(:summary)
      expect(result.summary).to be_a(String)
      expect(result.summary.length).to be > 10
      expect(result.summary.length).to be < wikipedia_photosynthesis.length
    end

    it 'works with DSPy::ChainOfThought', vcr: { cassette_name: 'summarization/cot_simple' } do
      cot = DSPy::ChainOfThought.new(Summarize)
      result = cot.call(text: wikipedia_photosynthesis)

      expect(result).to respond_to(:summary)
      expect(result).to respond_to(:reasoning)
      expect(result.summary).to be_a(String)
      expect(result.reasoning).to be_a(String)
      expect(result.reasoning.length).to be > 0
    end
  end

  describe 'EvaluateSummary LLM judge' do
    it 'returns structured multi-dimensional scores', vcr: { cassette_name: 'summarization/judge_evaluation' } do
      # First generate a summary
      summarizer = DSPy::Predict.new(Summarize)
      summary_result = summarizer.call(text: wikipedia_photosynthesis)

      # Then evaluate it with the LLM judge
      judge = DSPy::ChainOfThought.new(EvaluateSummary)
      eval_result = judge.call(
        source_text: wikipedia_photosynthesis,
        summary: summary_result.summary
      )

      # Dimensions are now direct output fields
      expect(eval_result).to respond_to(:faithfulness)
      expect(eval_result).to respond_to(:relevance)
      expect(eval_result).to respond_to(:coherence)
      expect(eval_result).to respond_to(:fluency)
      expect(eval_result).to respond_to(:overall_score)
      expect(eval_result).to respond_to(:reasoning)

      # Check all dimensions have valid scores (1-5)
      expect(eval_result.faithfulness).to be_between(1, 5)
      expect(eval_result.relevance).to be_between(1, 5)
      expect(eval_result.coherence).to be_between(1, 5)
      expect(eval_result.fluency).to be_between(1, 5)
      expect(eval_result.overall_score).to be_between(1.0, 5.0)
    end
  end

  describe 'LLM judge metric' do
    def create_llm_judge_metric(judge_lm)
      judge = DSPy::ChainOfThought.new(EvaluateSummary)
      judge.configure { |c| c.lm = judge_lm }

      ->(example, prediction) do
        # Extract summary from prediction (struct or hash)
        summary = prediction.respond_to?(:summary) ? prediction.summary : prediction[:summary]

        eval_result = judge.call(
          source_text: example.input_values[:text],
          summary: summary
        )

        # Access dimensions directly from the prediction
        {
          passed: eval_result.overall_score >= 3.5,
          score: eval_result.overall_score / 5.0, # Normalize to 0-1
          faithfulness: eval_result.faithfulness,
          relevance: eval_result.relevance,
          coherence: eval_result.coherence,
          fluency: eval_result.fluency
        }
      end
    end

    it 'returns expected hash format', vcr: { cassette_name: 'summarization/metric_format' } do
      metric = create_llm_judge_metric(openai_lm)

      # For LLM judge evaluation, we provide a placeholder expected value
      # since the judge evaluates absolute quality, not against a gold standard
      example = DSPy::Example.new(
        signature_class: Summarize,
        input: { text: wikipedia_photosynthesis },
        expected: { summary: "" }  # Placeholder - LLM judge ignores this
      )

      summarizer = DSPy::Predict.new(Summarize)
      prediction = summarizer.call(text: wikipedia_photosynthesis)

      result = metric.call(example, prediction)

      expect(result).to be_a(Hash)
      expect(result).to include(:passed, :score, :faithfulness, :relevance, :coherence, :fluency)
      expect([true, false]).to include(result[:passed])
      expect(result[:score]).to be_between(0.0, 1.0)
      expect(result[:faithfulness]).to be_between(1, 5)
      expect(result[:relevance]).to be_between(1, 5)
      expect(result[:coherence]).to be_between(1, 5)
      expect(result[:fluency]).to be_between(1, 5)
    end
  end

  describe 'Predict vs ChainOfThought comparison' do
    def create_llm_judge_metric(judge_lm)
      judge = DSPy::ChainOfThought.new(EvaluateSummary)
      judge.configure { |c| c.lm = judge_lm }

      ->(example, prediction) do
        # Extract summary from prediction (struct or hash)
        summary = prediction.respond_to?(:summary) ? prediction.summary : prediction[:summary]

        eval_result = judge.call(
          source_text: example.input_values[:text],
          summary: summary
        )

        # Access dimensions directly from the prediction
        {
          passed: eval_result.overall_score >= 3.5,
          score: eval_result.overall_score / 5.0,
          faithfulness: eval_result.faithfulness,
          relevance: eval_result.relevance,
          coherence: eval_result.coherence,
          fluency: eval_result.fluency
        }
      end
    end

    it 'evaluates both predictors on the same examples', vcr: { cassette_name: 'summarization/comparison' } do
      # For LLM judge evaluation, we provide placeholder expected values
      # since the judge evaluates absolute quality, not against a gold standard
      examples = [
        DSPy::Example.new(
          signature_class: Summarize,
          input: { text: wikipedia_photosynthesis },
          expected: { summary: "" }
        ),
        DSPy::Example.new(
          signature_class: Summarize,
          input: { text: wikipedia_byzantine },
          expected: { summary: "" }
        )
      ]

      llm_judge_metric = create_llm_judge_metric(openai_lm)

      # Evaluate Predict
      predict = DSPy::Predict.new(Summarize)
      predict_evaluator = DSPy::Evals.new(predict, metric: llm_judge_metric)
      predict_result = predict_evaluator.evaluate(examples, display_progress: false)

      # Evaluate ChainOfThought
      cot = DSPy::ChainOfThought.new(Summarize)
      cot_evaluator = DSPy::Evals.new(cot, metric: llm_judge_metric)
      cot_result = cot_evaluator.evaluate(examples, display_progress: false)

      # Verify both evaluations completed
      expect(predict_result).to be_a(DSPy::Evals::BatchEvaluationResult)
      expect(cot_result).to be_a(DSPy::Evals::BatchEvaluationResult)

      expect(predict_result.total_examples).to eq(2)
      expect(cot_result.total_examples).to eq(2)

      # Verify aggregated metrics contain dimension scores
      predict_result.results.each do |r|
        expect(r.metrics).to include(:faithfulness, :relevance, :coherence, :fluency)
      end

      cot_result.results.each do |r|
        expect(r.metrics).to include(:faithfulness, :relevance, :coherence, :fluency)
      end

      # Log comparison for visibility
      puts "\n=== Summarization Comparison Results ==="
      puts "Predict avg score: #{(predict_result.aggregated_metrics[:score_avg] * 100).round(1)}%"
      puts "ChainOfThought avg score: #{(cot_result.aggregated_metrics[:score_avg] * 100).round(1)}%"
      puts "Improvement: #{((cot_result.aggregated_metrics[:score_avg] - predict_result.aggregated_metrics[:score_avg]) * 100).round(1)} percentage points"
    end
  end
end
