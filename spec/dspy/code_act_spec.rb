# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'dspy/code_act'

class MathProblem < DSPy::Signature
  description "Solve mathematical problems using Ruby code"

  input do
    const :problem, String
  end

  output do
    const :solution, String
  end
end

RSpec.describe 'DSPy::CodeAct' do
  describe 'when solving a mathematical problem using Ruby code execution' do
    let(:problem) { "Calculate the sum of numbers from 1 to 10" }
    let(:agent) { DSPy::CodeAct.new(MathProblem, max_iterations: 5) }
    let(:prediction) do
      VCR.use_cassette('openai/gpt4o-mini/codeact_math_problem') do
        agent.forward(problem: problem)
      end
    end

    before(:all) do # Configure DSPy once for this describe block
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
    end

    it 'includes the input fields in the combined output struct' do
      expect(prediction.problem).to include(problem)
    end

    it 'provides a solution' do
      expect(prediction.solution).to be_a(String)
      expect(prediction.solution).not_to be_empty
    end

    it 'responds to :history' do
      expect(prediction).to respond_to(:history)
    end

    it 'has history as an array of hashes' do
      expect(prediction.history).to be_an(Array)
    end

    it 'has history entries as hashes' do
      prediction.history.each do |entry|
        expect(entry).to be_a(Hash)
      end
    end

    it 'has history entries with :step key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:step)
      end
    end

    it 'has history entries with :thought key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:thought)
      end
    end

    it 'has history entries with :ruby_code key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:ruby_code)
      end
    end

    it 'has history entries with :execution_result key' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:execution_result)
      end
    end

    it 'responds to :iterations' do
      expect(prediction).to respond_to(:iterations)
    end

    it 'has iterations as an integer' do
      expect(prediction.iterations).to be > 0
    end

    it 'responds to :execution_context' do
      expect(prediction).to respond_to(:execution_context)
    end

    it 'has execution_context as a hash' do
      expect(prediction.execution_context).to be_a(Hash)
    end

    it 'validates that the enhanced output struct is accessible' do
      expect(prediction.class.superclass).to eq(T::Struct)
    end

    it 'creates result instances of the enhanced output struct' do
      expect(prediction.class.superclass.name).to eq("T::Struct")
    end

    it 'history contains expected fields' do
      expect(prediction.history).not_to be_empty
    end

    it 'history entries have thought as a string' do
      prediction.history.each do |entry|
        expect(entry[:thought]).to be_a(String)
      end
    end

    it 'history entries have ruby_code as a string' do
      prediction.history.each do |entry|
        expect(entry[:ruby_code]).to be_a(String)
      end
    end

    it 'history entries have execution_result as a string or nil' do
      prediction.history.each do |entry|
        expect(entry[:execution_result]).to satisfy { |val| val.is_a?(String) || val.nil? }
      end
    end

    it 'history entries have step as an integer' do
      prediction.history.each do |entry|
        expect(entry[:step]).to be_an(Integer)
      end
    end

    it 'generates valid Ruby code in history' do
      ruby_codes = prediction.history.map { |entry| entry[:ruby_code] }.compact
      expect(ruby_codes).not_to be_empty
      
      # Basic validation - code should not be empty and should contain some Ruby syntax
      ruby_codes.each do |code|
        expect(code).not_to be_empty
        expect(code).to be_a(String)
      end
    end

    it 'executes Ruby code and produces results' do
      execution_results = prediction.history.map { |entry| entry[:execution_result] }.compact
      expect(execution_results).not_to be_empty
    end

    it 'provides reasoning in the thought process' do
      thoughts = prediction.history.map { |entry| entry[:thought] }
      expect(thoughts.any? { |thought| thought.length > 10 }).to be(true), "Expected substantial reasoning in thoughts"
    end

    it 'has error_message field in history entries' do
      prediction.history.each do |entry|
        expect(entry).to have_key(:error_message)
      end
    end

    it 'handles code execution errors gracefully' do
      prediction.history.each do |entry|
        # error_message should be nil for successful executions, string for errors
        expect(entry[:error_message]).to satisfy { |val| val.is_a?(String) || val.nil? }
      end
    end
  end

  describe 'code execution safety' do
    let(:agent) { DSPy::CodeAct.new(MathProblem, max_iterations: 3) }

    it 'can execute basic arithmetic operations' do
      result, error = agent.send(:execute_ruby_code_safely, "2 + 2")
      expect(error).to eq("")
      expect(result).to eq("4")
    end

    it 'can execute variable assignments and retrieval' do
      result, error = agent.send(:execute_ruby_code_safely, "x = 5; x * 2")
      expect(error).to eq("")
      expect(result).to eq("10")
    end

    it 'captures puts output' do
      result, error = agent.send(:execute_ruby_code_safely, "puts 'Hello World'")
      expect(error).to eq("")
      expect(result).to eq("Hello World")
    end

    it 'handles syntax errors gracefully' do
      result, error = agent.send(:execute_ruby_code_safely, "invalid ruby syntax {")
      expect(result).to be_nil
      expect(error).to include("Error:")
    end

    it 'handles runtime errors gracefully' do
      result, error = agent.send(:execute_ruby_code_safely, "1 / 0")
      expect(result).to be_nil
      expect(error).to include("Error:")
    end

    it 'can execute array and hash operations' do
      result, error = agent.send(:execute_ruby_code_safely, "[1, 2, 3].sum")
      expect(error).to eq("")
      expect(result).to eq("6")
    end

    it 'can execute simple loops and calculations' do
      code = <<~RUBY
        sum = 0
        (1..5).each { |i| sum += i }
        sum
      RUBY
      result, error = agent.send(:execute_ruby_code_safely, code)
      expect(error).to eq("")
      expect(result).to eq("15")
    end
  end

  describe 'signature and struct creation' do
    let(:agent) { DSPy::CodeAct.new(MathProblem) }

    it 'creates RubyCodeGeneration signature correctly' do
      expect(DSPy::RubyCodeGeneration).to be < DSPy::Signature
    end

    it 'creates RubyCodeObservation signature correctly' do
      expect(DSPy::RubyCodeObservation).to be < DSPy::Signature
    end

    it 'creates CodeActHistoryEntry struct correctly' do
      entry = DSPy::CodeActHistoryEntry.new(
        step: 1,
        thought: "test thought",
        ruby_code: "2 + 2",
        execution_result: "4",
        error_message: ""
      )
      expect(entry.step).to eq(1)
      expect(entry.thought).to eq("test thought")
      expect(entry.ruby_code).to eq("2 + 2")
      expect(entry.execution_result).to eq("4")
      expect(entry.error_message).to eq("")
    end

    it 'serializes CodeActHistoryEntry to hash correctly' do
      entry = DSPy::CodeActHistoryEntry.new(
        step: 1,
        thought: "test thought",
        ruby_code: "2 + 2",
        execution_result: "4",
        error_message: ""
      )
      hash = entry.to_h
      expect(hash).to eq({
        step: 1,
        thought: "test thought",
        ruby_code: "2 + 2",
        execution_result: "4",
        error_message: ""
      })
    end

    it 'handles CodeActNextStep enum correctly' do
      expect(DSPy::CodeActNextStep::Continue.serialize).to eq("continue")
      expect(DSPy::CodeActNextStep::Finish.serialize).to eq("finish")
    end
  end

  describe 'enhanced output struct validation' do
    let(:agent) { DSPy::CodeAct.new(MathProblem) }

    it 'validates enhanced output struct has required fields' do
      # Test that validation method exists and works
      expect(agent.private_methods).to include(:validate_output_schema!)
    end

    it 'generates example output with correct structure' do
      example = agent.send(:generate_example_output)
      expect(example).to have_key(:history)
      expect(example).to have_key(:iterations)
      expect(example).to have_key(:execution_context)
      expect(example[:history]).to be_an(Array)
      expect(example[:iterations]).to be_an(Integer)
      expect(example[:execution_context]).to be_a(Hash)
    end
  end

  describe 'private method unit tests' do
    let(:agent) { DSPy::CodeAct.new(MathProblem, max_iterations: 2) }
    let(:task) { "Calculate 2 + 2" }
    let(:history) { [] }
    let(:context) { "previous calculations available" }
    let(:iteration) { 1 }

    before do
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
    end

    describe '#execute_think_code_step' do
      it 'generates code, executes it, and updates history', vcr: { cassette_name: 'openai/gpt4o-mini/codeact_math_problem' } do
        result = agent.send(:execute_think_code_step, task, context, history, iteration)
        
        expect(result).to have_key(:history)
        expect(result).to have_key(:thought)
        expect(result).to have_key(:ruby_code)
        expect(result).to have_key(:execution_result)
        expect(result).to have_key(:error_message)
        
        expect(result[:history].size).to eq(1)
        expect(result[:thought]).to be_a(String)
        expect(result[:ruby_code]).to be_a(String)
      end
    end

    describe '#finalize_iteration' do
      it 'builds context and returns continuation state' do
        execution_state = {
          history: [DSPy::CodeActHistoryEntry.new(step: 1, thought: "test", ruby_code: "2+2", execution_result: "4", error_message: "")],
          thought: "test thought",
          ruby_code: "2 + 2",
          execution_result: "4", 
          error_message: ""
        }

        result = agent.send(:finalize_iteration, execution_state, iteration)
        
        expect(result).to eq({
          should_finish: false,
          history: execution_state[:history],
          context: "Step 1 result: 4"
        })
      end
    end
  end

  describe 'logger subscriber integration' do
    let(:log_output) { StringIO.new }
    let(:test_logger) { Logger.new(log_output) }
    
    before do
      # Configure DSPy for testing
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
      
      # Create logger subscriber manually
      @logger_subscriber = DSPy::Subscribers::LoggerSubscriber.new(logger: test_logger)
    end

    after do
      # Clean up
      @logger_subscriber = nil
    end

    it 'logs CodeAct agent events when running actual agent operations' do
      VCR.use_cassette('openai/gpt4o-mini/codeact_math_problem') do
        problem = "Calculate 5 + 3"
        agent = DSPy::CodeAct.new(MathProblem, max_iterations: 3)
        result = agent.forward(problem: problem)

        log_content = log_output.string
        
        # Check for CodeAct-specific events
        expect(log_content).to include("event=codeact")
        expect(log_content).to include("signature=MathProblem")
        expect(log_content).to include("status=success")
        expect(log_content).to include("event=code_execution")
      end
    end
  end
end