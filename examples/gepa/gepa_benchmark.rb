#!/usr/bin/env ruby
# frozen_string_literal: true

# GEPA Benchmark Example - Compare GEPA vs MIPROv2 optimization
# This example demonstrates how to use GEPA to optimize a DSPy program
# and compare its performance against MIPROv2

require_relative '../../lib/dspy'
require 'dotenv'
Dotenv.load(File.join(File.dirname(__FILE__), '..', '..', '.env'))


# Configure DSPy with your preferred LM
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
end

# Define a signature for math word problem solving
class MathProblemSignature < DSPy::Signature
  description "Solve math word problems step by step"

  input do
    const :problem, String, description: "A math word problem to solve"
  end

  output do
    const :answer, String, description: "Final numerical answer"
  end
end

# Create a simple program to be optimized
class MathSolver < DSPy::Module
  def initialize
    @solver = DSPy::ChainOfThought.new(MathProblemSignature)
  end

  def call(problem:)
    @solver.call(problem: problem)
  end
  
  def signature_class
    MathProblemSignature
  end
end

# Define training examples
def create_training_examples
  [
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "Sarah has 15 apples. She gives 7 to her friend and buys 3 more. How many apples does she have now?" },
      expected: { answer: "11" }
    ),
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "A rectangle has length 8 cm and width 5 cm. What is its area?" },
      expected: { answer: "40" }
    ),
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "Tom runs 3 miles per day for 5 days. How many miles does he run in total?" },
      expected: { answer: "15" }
    ),
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "A pizza is cut into 8 slices. If 3 people eat 2 slices each, how many slices are left?" },
      expected: { answer: "2" }
    ),
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "Lisa saves $5 per week. How much money will she have after 6 weeks?" },
      expected: { answer: "30" }
    )
  ]
end

# Define validation examples
def create_validation_examples
  [
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "John has 12 marbles. He loses 4 and finds 7 more. How many marbles does he have?" },
      expected: { answer: "15" }
    ),
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "A triangle has sides of 3, 4, and 5 units. What is its perimeter?" },
      expected: { answer: "12" }
    ),
    DSPy::Example.new(
      signature_class: MathProblemSignature,
      input: { problem: "Amy reads 2 chapters per day for 4 days. How many chapters does she read total?" },
      expected: { answer: "8" }
    )
  ]
end

# Define evaluation metric
def create_math_metric
  proc do |example, prediction|
    expected = example.expected_values[:answer].to_s.strip
    actual = prediction.answer.to_s.strip

    # Extract numbers from the answers for comparison
    expected_num = expected.scan(/\d+/).first
    actual_num = actual.scan(/\d+/).first

    if expected_num && actual_num && expected_num == actual_num
      1.0
    else
      0.0
    end
  end
end

# Enhanced metric with feedback for GEPA (simplified to proc)
def create_gepa_feedback_metric
  create_math_metric  # Use the same simple metric for now
end

def run_benchmark
  puts "🚀 GEPA vs MIPROv2 Benchmark"
  puts "=" * 50

  # Create data
  trainset = create_training_examples
  valset = create_validation_examples
  metric = create_math_metric
  gepa_metric = create_gepa_feedback_metric

  puts "📊 Dataset:"
  puts "  Training examples: #{trainset.size}"
  puts "  Validation examples: #{valset.size}"
  puts

  # Test baseline performance
  puts "🔍 Baseline Performance:"
  baseline = MathSolver.new
  baseline_result = DSPy::Evaluate.new(
    baseline,
    metric: metric,
    num_threads: 1
  ).evaluate(valset, display_progress: false)
  baseline_score = baseline_result.pass_rate
  puts "  Baseline accuracy: #{(baseline_score * 100).round(1)}%"
  puts

  # Optimize with MIPROv2
  puts "⚡ Optimizing with MIPROv2..."
  mipro_start_time = Time.now

  mipro = DSPy::Teleprompt::MIPROv2.new(
    metric: metric
  )

  mipro_result = mipro.compile(baseline, trainset: trainset, valset: valset)
  mipro_optimized = mipro_result.optimized_program
  mipro_duration = Time.now - mipro_start_time

  mipro_result = DSPy::Evaluate.new(
    mipro_optimized,
    metric: metric,
    num_threads: 1
  ).evaluate(valset, display_progress: false)
  mipro_score = mipro_result.pass_rate

  puts "  MIPROv2 accuracy: #{(mipro_score * 100).round(1)}%"
  puts "  MIPROv2 optimization time: #{mipro_duration.round(2)}s"
  puts

  # Optimize with GEPA
  puts "🧬 Optimizing with GEPA..."
  gepa_start_time = Time.now

  gepa = DSPy::Teleprompt::GEPA.new(
    metric: gepa_metric
  )

  gepa_result = gepa.compile(baseline, trainset: trainset, valset: valset)
  gepa_optimized = gepa_result.optimized_program
  gepa_duration = Time.now - gepa_start_time

  gepa_result = DSPy::Evaluate.new(
    gepa_optimized,
    metric: metric,
    num_threads: 1
  ).evaluate(valset, display_progress: false)
  gepa_score = gepa_result.pass_rate

  puts "  GEPA accuracy: #{(gepa_score * 100).round(1)}%"
  puts "  GEPA optimization time: #{gepa_duration.round(2)}s"
  puts

  # Results comparison
  puts "📈 Results Summary:"
  puts "=" * 50
  printf "  %-15s %8s %12s %15s\n", "Optimizer", "Accuracy", "Time (s)", "Improvement"
  puts "-" * 50
  printf "  %-15s %7.1f%% %11s %14s\n", "Baseline", baseline_score * 100, "-", "-"
  printf "  %-15s %7.1f%% %11.2f %13.1f%%\n", "MIPROv2", mipro_score * 100, mipro_duration, ((mipro_score - baseline_score) / baseline_score * 100)
  printf "  %-15s %7.1f%% %11.2f %13.1f%%\n", "GEPA", gepa_score * 100, gepa_duration, ((gepa_score - baseline_score) / baseline_score * 100)
  puts

  # Determine winner
  if gepa_score > mipro_score
    improvement = ((gepa_score - mipro_score) / mipro_score * 100).round(1)
    puts "🏆 GEPA wins! #{improvement}% better accuracy than MIPROv2"
  elsif mipro_score > gepa_score
    improvement = ((mipro_score - gepa_score) / gepa_score * 100).round(1)
    puts "🏆 MIPROv2 wins! #{improvement}% better accuracy than GEPA"
  else
    puts "🤝 Tie! Both optimizers achieved the same accuracy"
  end

  # Show optimized instructions
  puts
  puts "🔧 Optimized Instructions:"
  puts "=" * 50

  if mipro_optimized.respond_to?(:signature_class) && mipro_optimized.signature_class.respond_to?(:description)
    puts "MIPROv2: #{mipro_optimized.signature_class.description}"
  end

  if gepa_optimized.respond_to?(:signature_class) && gepa_optimized.signature_class.respond_to?(:description)
    puts "GEPA: #{gepa_optimized.signature_class.description}"
  end

  puts
  puts "✅ Benchmark completed!"
end

# Run the benchmark
if __FILE__ == $0
  begin
    run_benchmark
  rescue => e
    puts "❌ Error running benchmark: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end
