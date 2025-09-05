# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GEPA Minimal Optimization (Python Parity)', vcr: { cassette_name: 'gepa_minimal_optimization' } do
  # 1) Simple Q&A signature - mirrors Python's 'q -> a'
  class QASignature < DSPy::Signature
    description "Answer the question"
    
    input do
      const :q, String
    end
    
    output do
      const :a, String  
    end
  end

  # 2) Exact-match metric (simple proc format for Ruby)
  let(:exact_match) do
    proc do |example, prediction|
      prediction.a == example.expected_values[:a] ? 1.0 : 0.0
    end
  end

  it 'mirrors the Python GEPA example exactly' do
    skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
    
    # 1) Configure the base LM for generation (using GPT-4o-mini for reliability)
    DSPy.configure do |config|
      config.lm = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
    end

    # 3) Define the tiny program and a one-shot train example
    program = DSPy::Predict.new(QASignature)
    trainset = [
      DSPy::Example.new(
        signature_class: QASignature,
        input: { q: '2+2?' },
        expected: { a: '4' }
      )
    ]
    
    # Add validation set (required by GEPA)
    valset = [
      DSPy::Example.new(
        signature_class: QASignature,
        input: { q: '3+3?' },
        expected: { a: '6' }
      )
    ]

    # 4) Instantiate GEPA and compile (optimize) the program  
    config = DSPy::Teleprompt::GEPA::GEPAConfig.new
    config.reflection_lm = "openai/gpt-4o-mini"
    config.simple_mode = true  # Match Python's auto='light'
    config.population_size = 2
    config.num_generations = 1
    
    gepa = DSPy::Teleprompt::GEPA.new(
      metric: exact_match,
      config: config
    )
    
    result = gepa.compile(program, trainset: trainset, valset: valset)
    
    # Verify optimization completed
    expect(result).to be_a(DSPy::Teleprompt::Teleprompter::OptimizationResult)
    expect(result.optimized_program).not_to be_nil
    
    # 5) Run the optimized program
    optimized = result.optimized_program
    answer = optimized.call(q: '2+2?')
    
    # Verify the answer
    expect(answer.a).to eq('4')
    
    # Log for screenshot (matches Python GEPA workflow)
    puts "✨ GEPA Optimization Complete!"
    puts "  Program: DSPy::Predict.new(QASignature)"  
    puts "  Trainset: [q='2+2?', a='4']"
    puts "  Input: '2+2?'"
    puts "  Output: '#{answer.a}'"  # -> '4'
    puts "  Score: #{result.best_score_value}"
  end
end