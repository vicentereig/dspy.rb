require 'spec_helper'
require 'ostruct'
require 'benchmark'
require 'concurrent'
require 'polars'
require 'dspy/evaluate'
require 'dspy/signature'
require 'dspy/predict'

# Test signatures for evaluation
class SimpleMath < DSPy::Signature
  description "Solve basic arithmetic problems."

  input do
    const :problem, String, description: "An arithmetic problem"
  end

  output do
    const :answer, String, description: "The numerical answer"
  end
end

class QuestionAnswer < DSPy::Signature
  description "Answer questions based on context."

  input do
    const :question, String
    const :context, String
  end

  output do
    const :answer, String
    const :confidence, Float
  end
end

# Mock program for testing - doesn't make real API calls
class EvaluateMockMathProgram
  attr_accessor :responses

  def initialize
    @responses = {
      "2 + 3" => "5",
      "10 - 4" => "6", 
      "3 × 4" => "12",
      "15 ÷ 3" => "5",
      "7 + 8" => "15",
      "20 - 12" => "8",
      "error_case" => nil  # Will trigger an error
    }
  end

  def call(problem:)
    if problem == "error_case"
      raise "Simulated prediction error"
    end
    
    answer = @responses[problem] || "unknown"
    # Simulate a struct-like response
    result = OpenStruct.new(problem: problem, answer: answer)
    # Add explanation for unknown cases to match test expectation
    result.explanation = "Cannot solve" if answer == "unknown"
    result
  end
end

# Mock program that returns structured responses
class MockQAProgram
  def call(question:, context:)
    # Simple mock logic based on question content
    answer = case question.downcase
             when /what.*color/
               "blue"
             when /how.*many/
               "42"
             when /where/
               "San Francisco"
             else
               "I don't know"
             end
    
    confidence = question.include?("?") ? 0.9 : 0.5
    
    OpenStruct.new(
      question: question,
      context: context,
      answer: answer,
      confidence: confidence
    )
  end
end

RSpec.describe DSPy::Evaluate do
  let(:mock_program) { EvaluateMockMathProgram.new }
  let(:mock_qa_program) { MockQAProgram.new }

  # Dummy training sets for testing - with separate input and expected output
  let(:math_examples) do
    [
      { input: { problem: "2 + 3" }, expected: { answer: "5" } },
      { input: { problem: "10 - 4" }, expected: { answer: "6" } },
      { input: { problem: "3 × 4" }, expected: { answer: "12" } },
      { input: { problem: "15 ÷ 3" }, expected: { answer: "5" } },
      { input: { problem: "7 + 8" }, expected: { answer: "15" } }
    ]
  end

  let(:qa_examples) do
    [
      {
        input: { question: "What color is the sky?", context: "The sky appears blue during clear weather." },
        expected: { answer: "blue", confidence: 0.95 }
      },
      {
        input: { question: "How many days in a week?", context: "A week consists of seven consecutive days." },
        expected: { answer: "7", confidence: 0.99 }
      },
      {
        input: { question: "Where is Silicon Valley?", context: "Silicon Valley is located in California." },
        expected: { answer: "California", confidence: 0.85 }
      }
    ]
  end

  let(:mixed_quality_examples) do
    [
      { input: { problem: "2 + 3" }, expected: { answer: "5" } },      # Should pass
      { input: { problem: "10 - 4" }, expected: { answer: "6" } },     # Should pass
      { input: { problem: "20 - 12" }, expected: { answer: "8" } },    # Should pass
      { input: { problem: "unknown_problem" }, expected: { answer: "42" } },  # Should fail - program returns "unknown"
      { input: { problem: "error_case" }, expected: { answer: "0" } }   # Should fail - program throws error
    ]
  end

  before do
    DSPy.configure do |c|
      c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
    end
  end

  describe 'initialization' do
    it 'creates evaluator with program only' do
      evaluator = DSPy::Evaluate.new(mock_program)
      
      expect(evaluator.program).to eq(mock_program)
      expect(evaluator.metric).to be_nil
    end

    it 'creates evaluator with program and metric' do
      metric = DSPy::Metrics.exact_match(field: :answer)
      evaluator = DSPy::Evaluate.new(mock_program, metric: metric)
      
      expect(evaluator.program).to eq(mock_program)
      expect(evaluator.metric).to eq(metric)
    end

    it 'sets default parameters' do
      evaluator = DSPy::Evaluate.new(mock_program)
      
      expect(evaluator.num_threads).to eq(1)
      expect(evaluator.max_errors).to eq(5)
      expect(evaluator.provide_traceback).to be(true)
    end

    it 'accepts custom parameters' do
      evaluator = DSPy::Evaluate.new(mock_program, num_threads: 4, max_errors: 10, provide_traceback: false)
      
      expect(evaluator.num_threads).to eq(4)
      expect(evaluator.max_errors).to eq(10)
      expect(evaluator.provide_traceback).to be(false)
    end
  end

  describe '#call - single example evaluation' do
    # Custom metric that knows about our example format
    let(:metric) do
      proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
    end
    let(:evaluator) { DSPy::Evaluate.new(mock_program, metric: metric) }

    it 'evaluates successful example', :aggregate_failures do
      # Use a completely inline mock to avoid any state pollution
      inline_program = Class.new do
        def call(problem:)
          case problem
          when "2 + 3"
            OpenStruct.new(problem: problem, answer: "5")
          else
            OpenStruct.new(problem: problem, answer: "unknown")
          end
        end
      end.new
      
      inline_metric = lambda { |example, prediction| 
        expected = example[:expected] || example['expected']
        expected[:answer] == prediction.answer 
      }
      
      inline_evaluator = DSPy::Evaluate.new(inline_program, metric: inline_metric)
      
      example = { input: { problem: "2 + 3" }, expected: { answer: "5" } }
      result = inline_evaluator.call(example)
      
      expect(result).to be_a(DSPy::Evaluate::EvaluationResult)
      expect(result.example).to eq(example)
      expect(result.prediction.answer).to eq("5")
      expect(result.passed).to be(true)
      expect(result.metrics[:passed]).to be(true)
    end

    it 'evaluates failed example' do
      example = { input: { problem: "unknown_problem" }, expected: { answer: "42" } }
      result = evaluator.call(example)
      
      expect(result.passed).to be(false)
      expect(result.metrics[:passed]).to be(false)
    end

    it 'handles prediction errors gracefully' do
      # Create isolated mock that definitely raises an error
      error_mock = Class.new do
        def call(problem:)
          if problem == "error_case"
            raise "Simulated prediction error"
          end
          OpenStruct.new(problem: problem, answer: "unknown")
        end
      end.new
      
      error_evaluator = DSPy::Evaluate.new(error_mock, metric: metric)
      example = { input: { problem: "error_case" }, expected: { answer: "0" } }
      result = error_evaluator.call(example)
      
      expect(result.passed).to be(false)
      expect(result.prediction).to be_nil
      expect(result.metrics[:error]).to include("Simulated prediction error")
    end

    it 'works without metric' do
      evaluator_no_metric = DSPy::Evaluate.new(mock_program)
      example = { input: { problem: "2 + 3" }, expected: { answer: "5" } }
      result = evaluator_no_metric.call(example)
      
      expect(result.passed).to be(true)
      expect(result.metrics).to include(passed: true, score: 1.0)
    end

    it 'includes traceback when enabled' do
      # Create isolated mock that definitely raises an error
      error_mock = Class.new do
        def call(problem:)
          if problem == "error_case"
            raise "Simulated prediction error"
          end
          OpenStruct.new(problem: problem, answer: "unknown")
        end
      end.new
      
      evaluator = DSPy::Evaluate.new(error_mock, provide_traceback: true)
      example = { input: { problem: "error_case" }, expected: { answer: "0" } }
      result = evaluator.call(example)
      
      expect(result.metrics[:traceback]).to be_a(Array)
      expect(result.metrics[:traceback]).not_to be_empty
    end

    it 'excludes traceback when disabled' do
      # Create isolated mock that definitely raises an error
      error_mock = Class.new do
        def call(problem:)
          if problem == "error_case"
            raise "Simulated prediction error"
          end
          OpenStruct.new(problem: problem, answer: "unknown")
        end
      end.new
      
      evaluator = DSPy::Evaluate.new(error_mock, provide_traceback: false)
      example = { input: { problem: "error_case" }, expected: { answer: "0" } }
      result = evaluator.call(example)
      
      expect(result.metrics).not_to have_key(:traceback)
    end
  end

  describe '#evaluate - batch evaluation' do
    let(:metric) do
      proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
    end
    let(:evaluator) { DSPy::Evaluate.new(mock_program, metric: metric) }

    it 'evaluates multiple examples successfully' do
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        attr_accessor :responses

        def initialize
          @responses = {
            "2 + 3" => "5",
            "10 - 4" => "6", 
            "3 × 4" => "12",
            "15 ÷ 3" => "5",
            "7 + 8" => "15",
            "20 - 12" => "8"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      fresh_mock = isolated_mock_class.new
      fresh_metric = proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
      fresh_evaluator = DSPy::Evaluate.new(fresh_mock, metric: fresh_metric)
      result = fresh_evaluator.evaluate(math_examples, display_progress: false)
      
      expect(result).to be_a(DSPy::Evaluate::BatchEvaluationResult)
      expect(result.total_examples).to eq(5)
      expect(result.passed_examples).to eq(5)
      expect(result.pass_rate).to eq(1.0)
    end

    it 'handles mixed success and failure examples' do
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        attr_accessor :responses

        def initialize
          @responses = {
            "2 + 3" => "5",
            "10 - 4" => "6", 
            "3 × 4" => "12",
            "15 ÷ 3" => "5",
            "7 + 8" => "15",
            "20 - 12" => "8"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      fresh_mock = isolated_mock_class.new
      fresh_metric = proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
      fresh_evaluator = DSPy::Evaluate.new(fresh_mock, metric: fresh_metric)
      result = fresh_evaluator.evaluate(mixed_quality_examples, display_progress: false)
      
      expect(result.total_examples).to eq(5)
      expect(result.passed_examples).to eq(3)  # 3 should pass, 2 should fail
      expect(result.pass_rate).to eq(0.6)
    end

    it 'aggregates metrics correctly' do
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        attr_accessor :responses

        def initialize
          @responses = {
            "2 + 3" => "5",
            "10 - 4" => "6", 
            "3 × 4" => "12",
            "15 ÷ 3" => "5",
            "7 + 8" => "15",
            "20 - 12" => "8"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      fresh_mock = isolated_mock_class.new
      fresh_metric = proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
      fresh_evaluator = DSPy::Evaluate.new(fresh_mock, metric: fresh_metric)
      result = fresh_evaluator.evaluate(math_examples, display_progress: false)
      
      metrics = result.aggregated_metrics
      expect(metrics[:total_examples]).to eq(5)
      expect(metrics[:passed_examples]).to eq(5)
      expect(metrics[:failed_examples]).to eq(0)
      expect(metrics[:pass_rate]).to eq(1.0)
    end

    it 'stops at max errors' do
      # Create examples that will all fail
      failing_examples = [
        { problem: "error_case", answer: "0" },
        { problem: "error_case", answer: "0" },
        { problem: "error_case", answer: "0" },
        { problem: "error_case", answer: "0" },
        { problem: "error_case", answer: "0" },
        { problem: "error_case", answer: "0" },  # This should not be processed
        { problem: "error_case", answer: "0" }   # This should not be processed
      ]
      
      evaluator_strict = DSPy::Evaluate.new(mock_program, metric: metric, max_errors: 3)
      result = evaluator_strict.evaluate(failing_examples, display_progress: false)
      
      # Should stop at 3 errors, but may process more due to non-error failures
      expect(result.results.length).to be <= 5
    end
  end

  describe 'input extraction' do
    let(:evaluator) { DSPy::Evaluate.new(mock_program) }

    it 'extracts from hash with symbol keys' do
      example = { input: { problem: "2 + 3" }, expected: { answer: "5" } }
      result = evaluator.call(example)
      
      expect(result.prediction.problem).to eq("2 + 3")
    end

    it 'extracts from hash with string keys' do
      example = { "input" => { "problem" => "2 + 3" }, "expected" => { "answer" => "5" } }
      result = evaluator.call(example)
      
      expect(result.prediction.problem).to eq("2 + 3")
    end

    it 'extracts from object with input method' do
      example = OpenStruct.new(
        input: { problem: "2 + 3" },
        expected: { answer: "5" }
      )
      result = evaluator.call(example)
      
      expect(result.prediction.problem).to eq("2 + 3")
    end

    it 'extracts from object with to_h method' do
      example = OpenStruct.new(input: { problem: "2 + 3" }, expected: { answer: "5" })
      result = evaluator.call(example)
      
      expect(result.prediction.problem).to eq("2 + 3")
    end
  end

  describe 'serialization' do
    let(:metric) do
      proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
    end
    let(:evaluator) { DSPy::Evaluate.new(mock_program, metric: metric) }

    it 'serializes evaluation result to hash' do
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        def initialize
          @responses = {
            "2 + 3" => "5",
            "10 - 4" => "6", 
            "3 × 4" => "12",
            "15 ÷ 3" => "5",
            "7 + 8" => "15"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      fresh_mock = isolated_mock_class.new
      fresh_metric = proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
      fresh_evaluator = DSPy::Evaluate.new(fresh_mock, metric: fresh_metric)
      
      example = { input: { problem: "2 + 3" }, expected: { answer: "5" } }
      result = fresh_evaluator.call(example)
      hash = result.to_h
      
      expect(hash[:example]).to eq(example)
      expect(hash[:passed]).to be(true)
      expect(hash[:metrics]).to be_a(Hash)
    end

    it 'serializes batch result to hash' do
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        def initialize
          @responses = {
            "2 + 3" => "5",
            "10 - 4" => "6", 
            "3 × 4" => "12",
            "15 ÷ 3" => "5",
            "7 + 8" => "15"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      fresh_mock = isolated_mock_class.new
      fresh_metric = proc do |example, prediction|
        expected = example[:expected][:answer] 
        actual = prediction&.answer
        expected == actual
      end
      fresh_evaluator = DSPy::Evaluate.new(fresh_mock, metric: fresh_metric)
      
      result = fresh_evaluator.evaluate(math_examples.first(2), display_progress: false)
      hash = result.to_h
      
      expect(hash[:total_examples]).to eq(2)
      expect(hash[:passed_examples]).to eq(2)
      expect(hash[:pass_rate]).to eq(1.0)
      expect(hash[:results]).to be_a(Array)
      expect(hash[:results].length).to eq(2)
    end
  end

  describe 'with DSPy::Example objects' do
    let(:evaluator) { DSPy::Evaluate.new(mock_program) }
    
    it 'works with Example objects' do
      example = DSPy::Example.new(
        signature_class: SimpleMath,
        input: { problem: "3 + 3" },
        expected: { answer: "6" }
      )
      
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        def initialize
          @responses = {
            "3 + 3" => "6",
            "4 + 4" => "8",
            "5 + 5" => "10",
            "9 + 1" => "10"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      test_mock = isolated_mock_class.new
      evaluator = DSPy::Evaluate.new(test_mock)
      
      result = evaluator.call(example)
      
      expect(result.example).to eq(example)
      expect(result.prediction.answer).to eq("6")
      expect(result.passed).to be(true)
    end

    it 'evaluates batch of Example objects' do
      examples = [
        DSPy::Example.new(
          signature_class: SimpleMath,
          input: { problem: "4 + 4" },
          expected: { answer: "8" }
        ),
        DSPy::Example.new(
          signature_class: SimpleMath,
          input: { problem: "5 + 5" },
          expected: { answer: "10" }
        )
      ]
      
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        def initialize
          @responses = {
            "3 + 3" => "6",
            "4 + 4" => "8",
            "5 + 5" => "10",
            "9 + 1" => "10"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      test_mock = isolated_mock_class.new
      
      # Use built-in matching for Examples
      evaluator_with_matching = DSPy::Evaluate.new(test_mock, metric: proc { |example, prediction|
        example.is_a?(DSPy::Example) ? example.matches_prediction?(prediction) : false
      })
      
      result = evaluator_with_matching.evaluate(examples, display_progress: false)
      
      expect(result.total_examples).to eq(2)
      expect(result.passed_examples).to eq(2)
      expect(result.pass_rate).to eq(1.0)
    end

    it 'extracts input values correctly from Example objects' do
      example = DSPy::Example.new(
        signature_class: SimpleMath,
        input: { problem: "9 + 1" },
        expected: { answer: "10" }
      )
      
      # Create completely isolated instances to avoid ANY state pollution
      isolated_mock_class = Class.new do
        def initialize
          @responses = {
            "3 + 3" => "6",
            "4 + 4" => "8",
            "5 + 5" => "10",
            "9 + 1" => "10"
          }
        end

        def call(problem:)
          answer = @responses[problem] || "unknown"
          OpenStruct.new(problem: problem, answer: answer)
        end
      end
      
      test_mock = isolated_mock_class.new
      evaluator = DSPy::Evaluate.new(test_mock)
      result = evaluator.call(example)
      
      expect(result.prediction.problem).to eq("9 + 1")
      expect(result.prediction.answer).to eq("10")
    end
  end

  describe 'with real Predict program' do
    let(:predictor) { DSPy::Predict.new(SimpleMath) }
    let(:metric) { DSPy::Metrics.exact_match(field: :answer, case_sensitive: false) }
    
    before do
      # Skip this if no API key available
      skip "No OpenAI API key available" unless ENV['OPENAI_API_KEY']
      
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
        c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
      end
    end

    it 'evaluates with real LLM predictions', :vcr do
      VCR.use_cassette('evaluate/simple_math_evaluation') do
        evaluator = DSPy::Evaluate.new(predictor, metric: metric)
        simple_examples = [
          { input: { problem: "What is 5 + 3?" }, expected: { answer: "8" } },
          { input: { problem: "What is 10 - 7?" }, expected: { answer: "3" } }
        ]
        
        result = evaluator.evaluate(simple_examples, display_progress: false)
        
        expect(result.total_examples).to eq(2)
        expect(result.passed_examples).to be >= 0  # May vary based on LLM response
        expect(result.pass_rate).to be_between(0, 1)
      end
    end
  end

  describe 'callback hooks' do
    let(:metric) do
      proc do |example, prediction|
        expected = example[:expected][:answer]
        predicted = prediction&.answer
        expected == predicted
      end
    end

    let(:example) { math_examples.first }

    class CallbackAwareEvaluator < DSPy::Evaluate
      before_example :record_before_call
      after_example :record_after_call
      after_batch :record_after_evaluate

      attr_reader :events

      def initialize(program, **options)
        super
        @events = []
      end

      private

      def record_before_call
        @events << [:before_call, Thread.current.object_id]
      end

      def record_after_call
        @events << [:after_call, Thread.current.object_id]
      end

      def record_after_evaluate
        @events << [:after_evaluate, Thread.current.object_id]
      end
    end

    let(:evaluator) { CallbackAwareEvaluator.new(mock_program, metric: metric) }

    it 'runs before and after callbacks for #call' do
      evaluator.call(example)

      expect(evaluator.events.map(&:first)).to eq([:before_call, :after_call])
    end

    it 'runs evaluate callbacks when evaluating a batch' do
      evaluator.evaluate([example], display_progress: false, display_table: false)

      expect(evaluator.events.map(&:first)).to include(:after_evaluate)
    end
  end

  describe 'parallel execution' do
    let(:examples) do
      Array.new(6) do |index|
        { input: { problem: "sleep_#{index}" }, expected: { answer: "done" } }
      end
    end

    let(:thread_ids) { Concurrent::Array.new }

    let(:program) do
      Class.new do
        def initialize(thread_ids)
          @thread_ids = thread_ids
        end

        def call(problem:)
          @thread_ids << Thread.current.object_id
          sleep 0.1
          OpenStruct.new(problem: problem, answer: "done")
        end
      end.new(thread_ids)
    end

    let(:metric) do
      proc do |example, prediction|
        prediction.answer == example[:expected][:answer]
      end
    end

    it 'utilizes multiple threads when num_threads > 1' do
      evaluator = DSPy::Evaluate.new(program, metric: metric, num_threads: 4)

      elapsed = Benchmark.realtime do
        evaluator.evaluate(examples, display_progress: false, display_table: false)
      end

      expect(thread_ids.uniq.size).to be > 1
      expect(elapsed).to be < 0.4
    end
  end

  describe 'batch result scoring' do
    let(:metric) do
      proc do |example, prediction|
        prediction.answer == example[:expected][:answer]
      end
    end

    let(:passing_examples) do
      [
        { input: { problem: "2 + 3" }, expected: { answer: "5" } },
        { input: { problem: "10 - 4" }, expected: { answer: "6" } },
        { input: { problem: "3 × 4" }, expected: { answer: "12" } },
        { input: { problem: "20 - 12" }, expected: { answer: "8" } }
      ]
    end

    it 'exposes a percentage score on batch results' do
      evaluator = DSPy::Evaluate.new(mock_program, metric: metric)
      result = evaluator.evaluate(passing_examples, display_progress: false, display_table: false)

      expect(result).to respond_to(:score)
      expect(result.score).to eq(100.0)
    end

    it 'uses failure_score when predictions raise errors' do
      failing_program = Class.new do
        def call(**)
          raise "boom"
        end
      end.new

      evaluator = DSPy::Evaluate.new(failing_program, metric: metric, failure_score: 0.25, provide_traceback: false)
      result = evaluator.evaluate(passing_examples, display_progress: false, display_table: false)

      expect(result.score).to eq(25.0)
      expect(result.results.count).to eq(passing_examples.size)
      expect(result.results.map(&:metrics)).to all(include(:score))
    end
  end

  describe 'polars export' do
    let(:metric) do
      proc do |example, prediction|
        prediction.answer == example[:expected][:answer]
      end
    end

    let(:examples) do
      [
        { input: { problem: "2 + 3" }, expected: { answer: "5" } },
        { input: { problem: "10 - 4" }, expected: { answer: "6" } }
      ]
    end

    it 'converts batch results to a Polars DataFrame' do
      evaluator = DSPy::Evaluate.new(mock_program, metric: metric)
      result = evaluator.evaluate(examples, display_progress: false, display_table: false)

      dataframe = result.to_polars

      expect(dataframe).to be_a(Polars::DataFrame)
      expect(dataframe.shape).to eq([examples.size, dataframe.width])
      expect(dataframe.columns).to include("passed")
    end
  end
end

RSpec.describe DSPy::Metrics do
  let(:example) { { question: "What is 2+2?", answer: "4" } }
  let(:correct_prediction) { OpenStruct.new(question: "What is 2+2?", answer: "4") }
  let(:incorrect_prediction) { OpenStruct.new(question: "What is 2+2?", answer: "5") }
  let(:case_different_prediction) { OpenStruct.new(question: "What is 2+2?", answer: "Four") }

  describe '.exact_match' do
    it 'passes for exact matches' do
      metric = DSPy::Metrics.exact_match(field: :answer)
      
      expect(metric.call(example, correct_prediction)).to be(true)
    end

    it 'fails for non-matches' do
      metric = DSPy::Metrics.exact_match(field: :answer)
      
      expect(metric.call(example, incorrect_prediction)).to be(false)
    end

    it 'handles case sensitivity' do
      example_text = { answer: "four" }
      
      case_sensitive_metric = DSPy::Metrics.exact_match(field: :answer, case_sensitive: true)
      case_insensitive_metric = DSPy::Metrics.exact_match(field: :answer, case_sensitive: false)
      
      expect(case_sensitive_metric.call(example_text, case_different_prediction)).to be(false)
      expect(case_insensitive_metric.call(example_text, case_different_prediction)).to be(true)
    end
  end

  describe '.contains' do
    it 'passes when prediction contains expected value' do
      metric = DSPy::Metrics.contains(field: :answer)
      long_prediction = OpenStruct.new(answer: "The answer is 4 and here's why...")
      
      expect(metric.call(example, long_prediction)).to be(true)
    end

    it 'fails when prediction does not contain expected value' do
      metric = DSPy::Metrics.contains(field: :answer)
      
      expect(metric.call(example, incorrect_prediction)).to be(false)
    end
  end

  describe '.numeric_difference' do
    let(:numeric_example) { { value: "10.5" } }
    let(:close_prediction) { OpenStruct.new(value: "10.6") }  # 0.1 difference
    let(:far_prediction) { OpenStruct.new(value: "12.0") }   # 1.5 difference

    it 'passes for values within tolerance' do
      metric = DSPy::Metrics.numeric_difference(field: :value, tolerance: 0.2)
      result = metric.call(numeric_example, close_prediction)
      
      expect(result[:passed]).to be(true)
      expect(result[:difference]).to be_within(0.001).of(0.1)
    end

    it 'fails for values outside tolerance' do
      metric = DSPy::Metrics.numeric_difference(field: :value, tolerance: 0.2)
      result = metric.call(numeric_example, far_prediction)
      
      expect(result[:passed]).to be(false)
      expect(result[:difference]).to eq(1.5)
    end

    it 'handles non-numeric values' do
      non_numeric_example = { answer: "hello" }
      non_numeric_prediction = OpenStruct.new(answer: "world") 
      metric = DSPy::Metrics.numeric_difference(field: :answer, tolerance: 0.1)
      result = metric.call(non_numeric_example, non_numeric_prediction)
      
      expect(result[:passed]).to be(false)
      expect(result[:error]).to eq("Non-numeric values")
    end
  end

  describe '.composite_and' do
    let(:exact_metric) { DSPy::Metrics.exact_match(field: :answer) }
    let(:contains_metric) { DSPy::Metrics.contains(field: :answer) }

    it 'passes when all metrics pass' do
      composite = DSPy::Metrics.composite_and(exact_metric, contains_metric)
      result = composite.call(example, correct_prediction)
      
      expect(result[:passed]).to be(true)
    end

    it 'fails when any metric fails' do
      composite = DSPy::Metrics.composite_and(exact_metric, contains_metric)
      result = composite.call(example, incorrect_prediction)
      
      expect(result[:passed]).to be(false)
    end

    it 'includes individual metric results' do
      composite = DSPy::Metrics.composite_and(exact_metric, contains_metric)
      result = composite.call(example, correct_prediction)
      
      expect(result[:metric_0]).to have_key(:passed)
      expect(result[:metric_1]).to have_key(:passed)
    end
  end

  describe 'field extraction' do
    it 'extracts from hash with symbol keys' do
      metric = DSPy::Metrics.exact_match(field: :answer)
      hash_prediction = { answer: "4" }
      
      expect(metric.call(example, hash_prediction)).to be(true)
    end

    it 'extracts from hash with string keys' do
      metric = DSPy::Metrics.exact_match(field: :answer)
      hash_prediction = { "answer" => "4" }
      
      expect(metric.call(example, hash_prediction)).to be(true)
    end

    it 'extracts from object with method' do
      metric = DSPy::Metrics.exact_match(field: :answer)
      
      expect(metric.call(example, correct_prediction)).to be(true)
    end

    it 'extracts from object with to_h method' do
      metric = DSPy::Metrics.exact_match(field: :answer)
      obj_prediction = OpenStruct.new(answer: "4")
      
      expect(metric.call(example, obj_prediction)).to be(true)
    end
  end

end
