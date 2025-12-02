#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Comparing Predict vs ChainOfThought for Summarization
#
# This script demonstrates how to:
# 1. Use an LLM judge (G-Eval style) to evaluate summary quality
# 2. Compare DSPy::Predict vs DSPy::ChainOfThought performance
# 3. Get multi-dimensional evaluation scores (faithfulness, relevance, coherence, fluency)

require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

# Enum representing the evaluator's scoring mindset
class EvaluatorMindset < T::Enum
  enums do
    Critical = new('critical')   # Most should score 3-4, not 5
    Balanced = new('balanced')   # Fair assessment across the range
    Generous = new('generous')   # Benefit of the doubt
  end
end

# Struct pairing a summary with its source text for evaluation
class GroundedSummary < T::Struct
  const :source_text, String
  const :summary, String
end

def ensure_api_key!(env_key)
  return if ENV[env_key]

  warn "Missing #{env_key}. Set it in .env or your shell before running this example."
  exit 1
end

ensure_api_key!('OPENAI_API_KEY')

SUMMARIZER_MODEL = ENV.fetch('DSPY_SUMMARIZER_MODEL', 'openai/gpt-4o-mini')
JUDGE_MODEL = ENV.fetch('DSPY_JUDGE_MODEL', 'openai/gpt-4.1')

DSPy.configure do |config|
  config.lm = DSPy::LM.new(SUMMARIZER_MODEL, api_key: ENV['OPENAI_API_KEY'])
end

# Signature for summarization
class Summarize < DSPy::Signature
  description "Summarize the given text concisely while preserving key concepts and main ideas"

  input do
    const :text, String, description: "Text to summarize"
  end

  output do
    const :summary, String, description: "Concise summary preserving key concepts (2-3 sentences)"
  end
end

# Signature for LLM judge (G-Eval style multi-dimensional evaluation)
# Uses GroundedSummary struct and EvaluatorMindset enum for type-safe inputs
class EvaluateSummary < DSPy::Signature
  description "Evaluate summary quality using G-Eval criteria according to the specified mindset."

  input do
    const :grounded_summary, GroundedSummary, description: "The source text and summary to evaluate"
    const :mindset, EvaluatorMindset, description: "How critically to score (critical: most get 3-4, generous: benefit of doubt)"
  end

  output do
    const :faithfulness, Integer,
      description: "Score 1-5: Is the summary factually accurate? Does it avoid hallucinations or information not in the source?"
    const :relevance, Integer,
      description: "Score 1-5: Does the summary capture the most important information from the source text?"
    const :coherence, Integer,
      description: "Score 1-5: Is the summary well-structured with logical flow between sentences?"
    const :fluency, Integer,
      description: "Score 1-5: Is the summary grammatically correct, readable, and well-written?"
    const :overall_score, Float,
      description: "Overall quality score from 1.0 to 5.0 (weighted average of dimensions)"
  end
end

# Create LLM judge metric with configurable mindset
def create_llm_judge_metric(judge_lm, mindset: EvaluatorMindset::Critical)
  judge = DSPy::ChainOfThought.new(EvaluateSummary)
  judge.configure { |c| c.lm = judge_lm }

  ->(example, prediction) do
    eval_result = judge.call(
      grounded_summary: GroundedSummary.new(
        source_text: example.input_values[:text],
        summary: prediction.summary
      ),
      mindset: mindset
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
  rescue => e
    {
      passed: false,
      score: 0.0,
      error: e.message
    }
  end
end

# Wikipedia article excerpts (diverse topics for better comparison)
WIKIPEDIA_ARTICLES = [
  {
    name: "Photosynthesis",
    text: <<~DOC
      Photosynthesis is a biological process used by many cellular organisms to convert light energy into chemical energy, which is stored in organic compounds that can later be metabolized through cellular respiration to fuel the organism's activities. The term usually refers to oxygenic photosynthesis, where oxygen is produced as a byproduct and some of the chemical energy produced is stored in carbohydrate molecules such as sugars, starch, glycogen and cellulose, which are synthesized from endergonic reaction of carbon dioxide with water. Most plants, algae, and cyanobacteria perform photosynthesis; such organisms are called photoautotrophs. Photosynthesis is largely responsible for producing and maintaining the oxygen content of the Earth's atmosphere, and supplies most of the biological energy necessary for complex life on Earth.
    DOC
  },
  {
    name: "Byzantine Empire",
    text: <<~DOC
      The Byzantine Empire, also referred to as the Eastern Roman Empire, was the continuation of the Roman Empire centred in Constantinople during Late Antiquity and the Middle Ages. The eastern half of the Empire survived for another millennium after the fall of the western half in 476 AD. During most of its existence, the empire remained the most powerful economic, cultural, and military force in the Mediterranean world. The term "Byzantine Empire" was coined after the fall of Constantinople in 1453; its citizens continued to refer to their empire as the Roman Empire and to themselves as Romans—a term Greeks continued to use for themselves into Ottoman times. Although the Roman state continued and its traditions were maintained, modern historians distinguish Byzantium from its earlier incarnation because it was centred on Constantinople, oriented towards Greek rather than Latin culture, and characterised by Eastern Orthodox Christianity.
    DOC
  },
  {
    name: "Machine Learning",
    text: <<~DOC
      Machine learning (ML) is a field of study in artificial intelligence concerned with the development and study of statistical algorithms that can learn from data and generalize to unseen data, and thus perform tasks without explicit instructions. Within a short time, machine learning has become essential in many areas of technology and our everyday lives. It powers a wide range of tasks. Machine learning approaches have been applied to many fields including natural language processing, computer vision, speech recognition, email filtering, agriculture, and medicine. ML is also employed in the design of neural network architectures. The mathematical foundations of ML are provided by mathematical optimization and computational statistics, which both provide methods, theory, and application domains. Data mining is a related field of study, focusing on exploratory data analysis (EDA) through unsupervised learning.
    DOC
  },
  {
    name: "Great Barrier Reef",
    text: <<~DOC
      The Great Barrier Reef is the world's largest coral reef system, composed of over 2,900 individual reefs and 900 islands stretching for over 2,300 kilometres over an area of approximately 344,400 square kilometres. The reef is located in the Coral Sea, off the coast of Queensland, Australia, separated from the coast by a channel 100 miles wide in places and over 200 feet deep. The Great Barrier Reef can be seen from outer space and is the world's biggest single structure made by living organisms. This reef structure is composed of and built by billions of tiny organisms, known as coral polyps. It was selected as a World Heritage Site in 1981. CNN labelled it one of the Seven Natural Wonders of the World. The Queensland National Trust named it a state icon of Queensland. A large part of the reef is protected by the Great Barrier Reef Marine Park, which helps to limit the impact of human use, such as fishing and tourism.
    DOC
  },
  {
    name: "French Revolution",
    text: <<~DOC
      The French Revolution was a period of political and societal change in France that began with the Estates General of 1789, and ended with the coup of 18 Brumaire on November 9, 1799, and the formation of the French Consulate. Many of its ideas are considered fundamental principles of liberal democracy, while the values and institutions it created remain central to French political discourse. Its causes are generally agreed to be a combination of social, political, and economic factors, which the Ancien Régime proved unable to manage. In May 1789, widespread social distress led to the convocation of the Estates General, which was converted into a National Assembly in June. Continuing unrest culminated in the Storming of the Bastille on 14 July, which led to a series of radical measures by the Assembly, including the abolition of feudalism, the imposition of state control over the Catholic Church in France, and extension of the right to vote.
    DOC
  }
].freeze

def run_comparison
  puts "=" * 70
  puts "Summarization Comparison: Predict vs ChainOfThought"
  puts "=" * 70
  puts "Summarizer Model: #{SUMMARIZER_MODEL}"
  puts "Judge Model:      #{JUDGE_MODEL}"
  puts "Examples:         #{WIKIPEDIA_ARTICLES.length} Wikipedia articles"
  puts

  # Create examples (with placeholder expected values for LLM judge)
  examples = WIKIPEDIA_ARTICLES.map do |doc|
    DSPy::Example.new(
      signature_class: Summarize,
      input: { text: doc[:text] },
      expected: { summary: "" }  # LLM judge evaluates absolute quality
    )
  end

  # Create LLM judge metric with stronger model
  judge_lm = DSPy::LM.new(JUDGE_MODEL, api_key: ENV['OPENAI_API_KEY'])
  llm_judge_metric = create_llm_judge_metric(judge_lm)

  # Evaluate Predict
  puts "Evaluating DSPy::Predict..."
  predict = DSPy::Predict.new(Summarize)
  predict_evaluator = DSPy::Evals.new(predict, metric: llm_judge_metric)
  predict_result = predict_evaluator.evaluate(examples, display_progress: true)

  puts
  puts "Evaluating DSPy::ChainOfThought..."
  cot = DSPy::ChainOfThought.new(Summarize)
  cot_evaluator = DSPy::Evals.new(cot, metric: llm_judge_metric)
  cot_result = cot_evaluator.evaluate(examples, display_progress: true)

  # Print results
  puts
  puts "=" * 70
  puts "RESULTS"
  puts "=" * 70

  puts "\n### Predict Results ###"
  print_results(predict_result, WIKIPEDIA_ARTICLES)

  puts "\n### ChainOfThought Results ###"
  print_results(cot_result, WIKIPEDIA_ARTICLES)

  # Comparison
  puts "\n### Comparison ###"
  predict_avg = predict_result.aggregated_metrics[:score_avg]
  cot_avg = cot_result.aggregated_metrics[:score_avg]
  improvement = ((cot_avg - predict_avg) * 100).round(1)

  puts "Predict avg score:        #{(predict_avg * 100).round(1)}%"
  puts "ChainOfThought avg score: #{(cot_avg * 100).round(1)}%"
  puts "Improvement:              #{improvement > 0 ? '+' : ''}#{improvement} percentage points"

  # Per-dimension comparison
  puts "\n### Per-Dimension Comparison ###"
  predict_dims = average_dimensions(predict_result)
  cot_dims = average_dimensions(cot_result)

  %i[faithfulness relevance coherence fluency].each do |dim|
    p_score = predict_dims[dim]
    c_score = cot_dims[dim]
    diff = (c_score - p_score).round(2)
    puts "#{dim.to_s.capitalize.ljust(12)}: Predict #{p_score.round(2)}/5  |  CoT #{c_score.round(2)}/5  |  #{diff >= 0 ? '+' : ''}#{diff}"
  end

  puts
  if improvement > 0
    puts "ChainOfThought outperformed Predict by #{improvement} percentage points!"
  elsif improvement < 0
    puts "Predict outperformed ChainOfThought by #{improvement.abs} percentage points."
  else
    puts "Both predictors performed equally."
  end
end

def average_dimensions(batch_result)
  dims = { faithfulness: [], relevance: [], coherence: [], fluency: [] }

  batch_result.results.each do |result|
    metrics = result.metrics
    next if metrics[:error]

    dims[:faithfulness] << metrics[:faithfulness]
    dims[:relevance] << metrics[:relevance]
    dims[:coherence] << metrics[:coherence]
    dims[:fluency] << metrics[:fluency]
  end

  dims.transform_values { |scores| scores.empty? ? 0.0 : scores.sum.to_f / scores.length }
end

def print_results(batch_result, docs)
  batch_result.results.each_with_index do |result, idx|
    metrics = result.metrics
    puts "\n#{docs[idx][:name]}:"
    puts "  Summary: #{result.prediction.summary[0..100]}..."

    if metrics[:error]
      puts "  Error: #{metrics[:error]}"
    else
      puts "  Faithfulness: #{metrics[:faithfulness]}/5"
      puts "  Relevance:    #{metrics[:relevance]}/5"
      puts "  Coherence:    #{metrics[:coherence]}/5"
      puts "  Fluency:      #{metrics[:fluency]}/5"
      puts "  Overall:      #{(metrics[:score] * 100).round(1)}%"
      puts "  Passed:       #{metrics[:passed] ? 'Yes' : 'No'}"
    end
  end

  puts "\nAggregate:"
  puts "  Pass rate: #{(batch_result.pass_rate * 100).round(1)}%"
  puts "  Avg score: #{(batch_result.aggregated_metrics[:score_avg] * 100).round(1)}%"
end

if $PROGRAM_NAME == __FILE__
  run_comparison
end
