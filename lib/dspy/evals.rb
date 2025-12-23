# frozen_string_literal: true

require 'json'
require 'concurrent'
require 'sorbet-runtime'
require_relative 'example'
require_relative 'callbacks'

module DSPy
  # Core evaluation framework for DSPy programs
  # Supports single evaluations, batch evaluations, and optimization workflows
  class Evals
    extend T::Sig

    # Result of evaluating a single example
    class EvaluationResult
      extend T::Sig

      sig { returns(T.untyped) }
      attr_reader :example

      sig { returns(T.untyped) }
      attr_reader :prediction

      sig { returns(T.untyped) }
      attr_reader :trace

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :metrics

      sig { returns(T::Boolean) }
      attr_reader :passed

      sig do
        params(
          example: T.untyped,
          prediction: T.untyped,
          trace: T.untyped,
          metrics: T::Hash[Symbol, T.untyped],
          passed: T::Boolean
        ).void
      end
      def initialize(example:, prediction:, trace:, metrics:, passed:)
        @example = example
        @prediction = prediction
        @trace = trace
        @metrics = metrics
        @passed = passed
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          example: @example,
          prediction: @prediction.respond_to?(:to_h) ? @prediction.to_h : @prediction,
          trace: @trace,
          metrics: @metrics,
          passed: @passed
        }
      end
    end

    # Batch evaluation results with aggregated metrics
    class BatchEvaluationResult
      extend T::Sig

      sig { returns(T::Array[EvaluationResult]) }
      attr_reader :results

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :aggregated_metrics

      sig { returns(Integer) }
      attr_reader :total_examples

      sig { returns(Integer) }
      attr_reader :passed_examples

      sig { returns(Float) }
      attr_reader :pass_rate

      sig { returns(Float) }
      attr_reader :score

      sig do
        params(
          results: T::Array[EvaluationResult],
          aggregated_metrics: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(results:, aggregated_metrics:)
        @results = results.freeze
        @aggregated_metrics = aggregated_metrics.freeze
        @total_examples = results.length
        @passed_examples = results.count(&:passed)
        @pass_rate = @total_examples > 0 ? @passed_examples.to_f / @total_examples : 0.0
        score_avg = aggregated_metrics[:score_avg] || @pass_rate
        @score = (score_avg * 100).round(2)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          total_examples: @total_examples,
          passed_examples: @passed_examples,
          pass_rate: @pass_rate,
          score: @score,
          aggregated_metrics: @aggregated_metrics,
          results: @results.map(&:to_h)
        }
      end

      if defined?(Polars::DataFrame)
        sig { returns(Polars::DataFrame) }
      else
        sig { returns(T.untyped) }
      end
      def to_polars
        ensure_polars!

        rows = @results.each_with_index.map do |result, index|
          {
            "index" => index,
            "passed" => result.passed,
            "score" => result.metrics[:score],
            "example" => serialize_for_polars(result.example),
            "prediction" => serialize_for_polars(result.prediction),
            "metrics" => serialize_for_polars(result.metrics),
            "trace" => serialize_for_polars(result.trace)
          }
        end

        Polars::DataFrame.new(rows)
      end

      private

      POLARS_MISSING_ERROR = <<~MSG
        Polars is required to export evaluation results. Add `gem 'polars'`
        (or enable the `dspy-datasets` gem / `DSPY_WITH_DATASETS=1`) before
        calling `DSPy::Evals::BatchEvaluationResult#to_polars`.
      MSG

      def ensure_polars!
        return if defined?(Polars::DataFrame)

        require 'polars'
      rescue LoadError => e
        raise LoadError, "#{POLARS_MISSING_ERROR}\n\n#{e.message}"
      end

      def serialize_for_polars(value)
        case value
        when NilClass, TrueClass, FalseClass, Numeric, String
          value
        when Hash
          JSON.generate(value)
        when Array
          JSON.generate(value)
        else
          if value.respond_to?(:to_h)
            JSON.generate(value.to_h)
          else
            value.to_s
          end
        end
      end
    end

    sig { returns(T.untyped) }
    attr_reader :program

    sig { returns(T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))) }
    attr_reader :metric

    sig { returns(T.nilable(Integer)) }
    attr_reader :num_threads

    sig { returns(T.nilable(Integer)) }
    attr_reader :max_errors

    sig { returns(T::Boolean) }
    attr_reader :provide_traceback

    sig { returns(Float) }
    attr_reader :failure_score

    sig { returns(T.nilable(EvaluationResult)) }
    attr_reader :last_example_result

    sig { returns(T.nilable(BatchEvaluationResult)) }
    attr_reader :last_batch_result

    sig { returns(T::Boolean) }
    attr_reader :export_scores

    sig { returns(String) }
    attr_reader :score_name

    include DSPy::Callbacks

    create_before_callback :call, wrap: false
    create_after_callback :call, wrap: false
    create_before_callback :evaluate, wrap: false
    create_after_callback :evaluate, wrap: false

    class << self
      def before_example(callback = nil, &block)
        before(callback, target: :call, &block)
      end

      def after_example(callback = nil, &block)
        after(callback, target: :call, &block)
      end

      def before_batch(callback = nil, &block)
        before(callback, target: :evaluate, &block)
      end

      def after_batch(callback = nil, &block)
        after(callback, target: :evaluate, &block)
      end

      def reset_callbacks!
        @callbacks = {}
      end
    end

    sig do
      params(
        program: T.untyped,
        metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean)),
        num_threads: T.nilable(Integer),
        max_errors: T.nilable(Integer),
        failure_score: T.nilable(Numeric),
        provide_traceback: T::Boolean,
        export_scores: T::Boolean,
        score_name: String
      ).void
    end
    def initialize(program, metric: nil, num_threads: 1, max_errors: 5, failure_score: 0.0, provide_traceback: true, export_scores: false, score_name: 'evaluation')
      @program = program
      @metric = metric
      @num_threads = num_threads || 1
      @max_errors = max_errors || 5
      @provide_traceback = provide_traceback
      @failure_score = failure_score ? failure_score.to_f : 0.0
      @export_scores = export_scores
      @score_name = score_name
      @last_example_result = nil
      @last_batch_result = nil
    end

    # Evaluate program on a single example
    sig { params(example: T.untyped, trace: T.nilable(T.untyped)).returns(EvaluationResult) }
    def call(example, trace: nil)
      run_callbacks(:before, :call, example: example)

      DSPy::Context.with_span(
        operation: 'evaluation.example',
        'dspy.module' => 'Evaluator',
        'evaluation.program' => @program.class.name,
        'evaluation.has_metric' => !@metric.nil?
      ) do
        begin
          perform_call(example, trace: trace)
        rescue => e
          build_error_result(example, e, trace: trace)
        end
      end.then do |result|
        @last_example_result = result
        emit_example_observation(example, result)
        run_callbacks(:after, :call, example: example, result: result)
        result
      end
    end

    # Evaluate program on multiple examples
    sig do
      params(
        devset: T::Array[T.untyped],
        display_progress: T::Boolean,
        display_table: T::Boolean,
        return_outputs: T::Boolean
      ).returns(BatchEvaluationResult)
    end
    def evaluate(devset, display_progress: true, display_table: false, return_outputs: true)
      run_callbacks(:before, :evaluate, devset: devset)

      DSPy::Context.with_span(
        operation: 'evaluation.batch',
        'dspy.module' => 'Evaluator',
        'evaluation.program' => @program.class.name,
        'evaluation.num_examples' => devset.length,
        'evaluation.has_metric' => !@metric.nil?,
        'evaluation.num_threads' => @num_threads
      ) do
        if display_progress
          puts "Evaluating #{devset.length} examples..."
        end

        results = if parallel_execution?
          evaluate_in_parallel(devset, display_progress: display_progress)
        else
          evaluate_sequential(devset, display_progress: display_progress)
        end

        # Aggregate metrics
        aggregated_metrics = aggregate_metrics(results)

        batch_result = BatchEvaluationResult.new(
          results: results,
          aggregated_metrics: aggregated_metrics
        )

        if display_table
          display_results_table(batch_result)
        end

        # Emit batch completion event
        DSPy.log('evaluation.batch_complete', **{
          'evaluation.program_class' => @program.class.name,
          'evaluation.total_examples' => batch_result.total_examples,
          'evaluation.passed_examples' => batch_result.passed_examples,
          'evaluation.pass_rate' => batch_result.pass_rate,
          'evaluation.aggregated_metrics' => aggregated_metrics
        })

        if display_progress
          puts "Evaluation complete: #{batch_result.passed_examples}/#{batch_result.total_examples} passed (#{(batch_result.pass_rate * 100).round(1)}%)"
        end

        batch_result
      end.then do |batch_result|
        @last_batch_result = batch_result
        emit_batch_observation(devset, batch_result)
        run_callbacks(:after, :evaluate, devset: devset, result: batch_result)
        batch_result
      end
    end

    private

    def parallel_execution?
      (@num_threads || 1) > 1
    end

    def evaluate_sequential(devset, display_progress:)
      results = []
      errors = 0
      passed_count = 0

      devset.each_with_index do |example, index|
        break if errors >= @max_errors

        result = safe_call(example)
        results << result

        if result.passed
          passed_count += 1
        else
          errors += 1
        end

        if display_progress && (index + 1) % 10 == 0
          log_progress(index + 1, devset.length, passed_count)
        end
      end

      results
    end

    def evaluate_in_parallel(devset, display_progress:)
      total = devset.length
      results = Array.new(total)
      errors = 0
      processed = 0
      passed_count = 0

      executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: @num_threads,
        max_threads: @num_threads,
        max_queue: [total, 1].max,
        idletime: 60
      )

      enumerator = devset.each_with_index

      loop do
        break if errors >= @max_errors

        batch = []
        @num_threads.times do
          begin
            example = enumerator.next
            batch << { example: example[0], index: example[1] }
          rescue StopIteration
            break
          end
        end

        break if batch.empty?

        futures = batch.map do |item|
          Concurrent::Promises.future_on(executor) do
            [:ok, item[:index], safe_call(item[:example])]
          rescue => e
            [:error, item[:index], e]
          end
        end

        futures.each do |future|
          status, index, payload = future.value!
          example = batch.find { |entry| entry[:index] == index }[:example]

          result = if status == :ok
            payload
          else
            errors += 1
            puts "Error processing example #{index}: #{payload.message}" if display_progress
            build_error_result(example, payload)
          end

          results[index] = result
          processed += 1
          if result.passed
            passed_count += 1
          else
            errors += 1 unless status == :error
          end

          if display_progress && (processed % 10).zero?
            log_progress(processed, total, passed_count)
          end
        end
      end

      executor.shutdown
      executor.wait_for_termination

      results.compact
    end

    def safe_call(example)
      call(example)
    rescue => e
      build_error_result(example, e)
    end

    def perform_call(example, trace:)
      # Extract input from example - support both hash and object formats
      input_values = extract_input_values(example)

      # Run prediction
      prediction = @program.call(**input_values)

      # Calculate metrics if provided
      metrics = {}
      passed = true

      if @metric
        begin
          metric_result = @metric.call(example, prediction)
          if metric_result.is_a?(Hash)
            metrics = symbolize_keys(metric_result)
            passed_flag = metrics.key?(:passed) ? metrics[:passed] : metrics['passed']
            passed = passed_flag.nil? ? true : !!passed_flag
          else
            passed = !!metric_result
            metrics[:passed] = passed
          end
        rescue => e
          passed = false
          metrics[:error] = e.message
          metrics[:passed] = false
          metrics[:score] = @failure_score
        end
      end

      metrics[:passed] = passed unless metrics.key?(:passed)
      metrics[:score] = normalize_score(metrics[:score], passed) if metrics.key?(:score)
      metrics[:score] ||= passed ? 1.0 : 0.0

      EvaluationResult.new(
        example: example,
        prediction: prediction,
        trace: trace,
        metrics: metrics,
        passed: passed
      )
    end

    def build_error_result(example, error, trace: nil)
      metrics = {
        error: error.message,
        passed: false,
        score: @failure_score
      }
      metrics[:traceback] = error.backtrace&.first(10) || [] if @provide_traceback

      EvaluationResult.new(
        example: example,
        prediction: nil,
        trace: trace,
        metrics: metrics,
        passed: false
      )
    end

    def log_progress(processed, total, passed_count)
      puts "Processed #{processed}/#{total} examples (#{passed_count} passed)"
    end

    # Extract input values from example in various formats
    sig { params(example: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def extract_input_values(example)
      case example
      when DSPy::Example
        # Preferred format: DSPy::Example object with type safety
        example.input_values
      when Hash
        # Check if it has an :input key (structured format)
        if example.key?(:input)
          input_data = example[:input]
          input_data.is_a?(Hash) ? input_data.transform_keys(&:to_sym) : input_data
        elsif example.key?('input')
          input_data = example['input']
          input_data.is_a?(Hash) ? input_data.transform_keys(&:to_sym) : input_data
        else
          # Legacy format - assume the whole hash is input
          if example.keys.first.is_a?(String)
            example.transform_keys(&:to_sym)
          else
            example
          end
        end
      when ->(ex) { ex.respond_to?(:input_values) }
        # Object with input_values method (Example-like)
        example.input_values
      when ->(ex) { ex.respond_to?(:input) }
        # Object with input method
        input_data = example.input
        input_data.is_a?(Hash) ? input_data.transform_keys(&:to_sym) : input_data
      when ->(ex) { ex.respond_to?(:to_h) }
        # Object that can be converted to hash
        hash = example.to_h
        if hash.key?(:input)
          input_data = hash[:input]
          input_data.is_a?(Hash) ? input_data.transform_keys(&:to_sym) : input_data
        elsif hash.key?('input')
          input_data = hash['input']
          input_data.is_a?(Hash) ? input_data.transform_keys(&:to_sym) : input_data
        else
          hash.is_a?(Hash) ? hash.transform_keys(&:to_sym) : hash
        end
      else
        # Try to extract by introspection
        if example.respond_to?(:instance_variables)
          vars = {}
          example.instance_variables.each do |var|
            key = var.to_s.delete('@').to_sym
            vars[key] = example.instance_variable_get(var)
          end
          vars
        else
          raise ArgumentError, "Cannot extract input values from example: #{example.class}"
        end
      end
    end

    # Extract expected values for metric comparison (used internally)
    sig { params(example: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def extract_expected_values(example)
      case example
      when DSPy::Example
        example.expected_values
      when Hash
        if example.key?(:expected)
          expected_data = example[:expected]
          expected_data.is_a?(Hash) ? expected_data.transform_keys(&:to_sym) : expected_data
        elsif example.key?('expected')
          expected_data = example['expected']
          expected_data.is_a?(Hash) ? expected_data.transform_keys(&:to_sym) : expected_data
        else
          # Legacy format - no separate expected values
          nil
        end
      when ->(ex) { ex.respond_to?(:expected_values) }
        example.expected_values
      when ->(ex) { ex.respond_to?(:expected) }
        expected_data = example.expected
        expected_data.is_a?(Hash) ? expected_data.transform_keys(&:to_sym) : expected_data
      else
        nil
      end
    end

    # Aggregate metrics across all results
    sig { params(results: T::Array[EvaluationResult]).returns(T::Hash[Symbol, T.untyped]) }
    def aggregate_metrics(results)
      return {} if results.empty?
      
      total = results.length
      passed = results.count(&:passed)

      aggregated = {
        total_examples: total,
        passed_examples: passed,
        failed_examples: results.count { |r| !r.passed }
      }

      score_values = results.filter_map do |result|
        score = result.metrics[:score]
        score if score.is_a?(Numeric)
      end

      if score_values.any?
        aggregated[:score_sum] = score_values.sum
        aggregated[:score_avg] = score_values.sum.to_f / score_values.length
        aggregated[:score_min] = score_values.min
        aggregated[:score_max] = score_values.max
      else
        aggregated[:score_avg] = passed.positive? && total.positive? ? passed.to_f / total : 0.0
      end

      # Aggregate other numeric metrics
      numeric_metrics = {}
      results.each do |result|
        result.metrics.each do |key, value|
          next if [:error, :traceback, :passed, :score].include?(key)
          next unless value.is_a?(Numeric)

          numeric_metrics[key] ||= []
          numeric_metrics[key] << value
        end
      end

      numeric_metrics.each do |key, values|
        aggregated[:"#{key}_avg"] = values.sum.to_f / values.length
        aggregated[:"#{key}_min"] = values.min
        aggregated[:"#{key}_max"] = values.max
      end

      aggregated[:pass_rate] = total.positive? ? passed.to_f / total : 0.0

      aggregated
    end

    # Display results in a table format
    sig { params(batch_result: BatchEvaluationResult).void }
    def display_results_table(batch_result)
      puts "\nEvaluation Results:"
      puts "=" * 50
      puts "Total Examples: #{batch_result.total_examples}"
      puts "Passed: #{batch_result.passed_examples}"
      puts "Failed: #{batch_result.total_examples - batch_result.passed_examples}"
      puts "Pass Rate: #{(batch_result.pass_rate * 100).round(1)}%"
      
      if batch_result.aggregated_metrics.any?
        puts "\nAggregated Metrics:"
        batch_result.aggregated_metrics.each do |key, value|
          next if [:total_examples, :passed_examples, :failed_examples, :pass_rate].include?(key)
          puts "  #{key}: #{value.is_a?(Float) ? value.round(3) : value}"
        end
      end
      
      puts "=" * 50
    end

    def emit_example_observation(example, result)
      DSPy.event('evals.example.complete', {
        program: @program.class.name,
        example_id: extract_example_id(example),
        passed: result.passed,
        score: result.metrics[:score],
        error: result.metrics[:error]
      })

      # Export score to Langfuse if enabled
      if @export_scores
        export_example_score(example, result)
      end
    rescue => e
      DSPy.log('evals.example.observation_error', error: e.message)
    end

    def emit_batch_observation(devset, batch_result)
      DSPy.event('evals.batch.complete', {
        program: @program.class.name,
        dataset_size: devset.length,
        total_examples: batch_result.total_examples,
        passed_examples: batch_result.passed_examples,
        pass_rate: batch_result.pass_rate,
        score: batch_result.score
      })

      # Export batch score to Langfuse if enabled
      if @export_scores
        export_batch_score(batch_result)
      end
    rescue => e
      DSPy.log('evals.batch.observation_error', error: e.message)
    end

    def export_example_score(example, result)
      score_value = result.metrics[:score] || (result.passed ? 1.0 : 0.0)
      example_id = extract_example_id(example)

      DSPy.score(
        @score_name,
        score_value,
        comment: "Example: #{example_id || 'unknown'}, passed: #{result.passed}"
      )
    rescue => e
      DSPy.log('evals.score_export_error', error: e.message)
    end

    def export_batch_score(batch_result)
      DSPy.score(
        "#{@score_name}_batch",
        batch_result.pass_rate,
        comment: "Batch: #{batch_result.passed_examples}/#{batch_result.total_examples} passed"
      )
    rescue => e
      DSPy.log('evals.batch_score_export_error', error: e.message)
    end

    def extract_example_id(example)
      if example.respond_to?(:id)
        example.id
      elsif example.is_a?(Hash)
        example[:id] || example['id']
      else
        nil
      end
    rescue
      nil
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), memo|
        memo[key.respond_to?(:to_sym) ? key.to_sym : key] = value
      end
    end

    def normalize_score(value, passed)
      case value
      when Numeric
        value.to_f
      when TrueClass, FalseClass
        value ? 1.0 : 0.0
      else
        passed ? 1.0 : 0.0
      end
    end

  end

  # Common metric functions for evaluation
  module Metrics
    extend T::Sig

    # Exact match metric - checks if prediction exactly matches expected output
    sig do
      params(
        field: Symbol,
        case_sensitive: T::Boolean
      ).returns(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
    end
    def self.exact_match(field: :answer, case_sensitive: true)
      proc do |example, prediction|
        expected = extract_field(example, field)
        actual = extract_field(prediction, field)
        
        next false if expected.nil? || actual.nil?
        
        if case_sensitive
          expected.to_s == actual.to_s
        else
          expected.to_s.downcase == actual.to_s.downcase
        end
      end
    end

    # Contains metric - checks if prediction contains expected substring
    sig do
      params(
        field: Symbol,
        case_sensitive: T::Boolean
      ).returns(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
    end
    def self.contains(field: :answer, case_sensitive: false)
      proc do |example, prediction|
        expected = extract_field(example, field)
        actual = extract_field(prediction, field)
        
        next false if expected.nil? || actual.nil?
        
        if case_sensitive
          actual.to_s.include?(expected.to_s)
        else
          actual.to_s.downcase.include?(expected.to_s.downcase)
        end
      end
    end

    # Numeric difference metric - checks if prediction is within tolerance of expected value
    sig do
      params(
        field: Symbol,
        tolerance: Float
      ).returns(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Hash[Symbol, T.untyped]))
    end
    def self.numeric_difference(field: :answer, tolerance: 0.01)
      proc do |example, prediction|
        expected = extract_field(example, field)
        actual = extract_field(prediction, field)
        
        next { passed: false, error: "Missing values" } if expected.nil? || actual.nil?
        
        begin
          expected_num = Float(expected)
          actual_num = Float(actual)
          difference = (expected_num - actual_num).abs
          passed = difference <= tolerance
          
          {
            passed: passed,
            difference: difference,
            expected: expected_num,
            actual: actual_num,
            tolerance: tolerance
          }
        rescue ArgumentError
          { passed: false, error: "Non-numeric values" }
        end
      end
    end

    # Composite metric - combines multiple metrics with AND logic
    def self.composite_and(*metrics)
      proc do |example, prediction|
        results = {}
        all_passed = true
        
        metrics.each_with_index do |metric, index|
          result = metric.call(example, prediction)
          
          if result.is_a?(Hash)
            results[:"metric_#{index}"] = result
            all_passed &&= result[:passed] || result['passed'] || false
          else
            passed = !!result
            results[:"metric_#{index}"] = { passed: passed }
            all_passed &&= passed
          end
        end
        
        results[:passed] = all_passed
        results
      end
    end

    private

    # Extract field value from example or prediction
    sig { params(obj: T.untyped, field: Symbol).returns(T.untyped) }
    def self.extract_field(obj, field)
      case obj
      when Hash
        obj[field] || obj[field.to_s]
      when ->(o) { o.respond_to?(field) }
        obj.send(field)
      when ->(o) { o.respond_to?(:to_h) }
        hash = obj.to_h
        hash[field] || hash[field.to_s]
      else
        nil
      end
    end
  end
end
