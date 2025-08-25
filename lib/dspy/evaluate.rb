# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'example'

module DSPy
  # Core evaluation framework for DSPy programs
  # Supports single evaluations, batch evaluations, and optimization workflows
  class Evaluate
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
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          total_examples: @total_examples,
          passed_examples: @passed_examples,
          pass_rate: @pass_rate,
          aggregated_metrics: @aggregated_metrics,
          results: @results.map(&:to_h)
        }
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

    sig do
      params(
        program: T.untyped,
        metric: T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean)),
        num_threads: T.nilable(Integer),
        max_errors: T.nilable(Integer),
        provide_traceback: T::Boolean
      ).void
    end
    def initialize(program, metric: nil, num_threads: 1, max_errors: 5, provide_traceback: true)
      @program = program
      @metric = metric
      @num_threads = num_threads || 1
      @max_errors = max_errors || 5
      @provide_traceback = provide_traceback
    end

    # Evaluate program on a single example
    sig { params(example: T.untyped, trace: T.nilable(T.untyped)).returns(EvaluationResult) }
    def call(example, trace: nil)
      DSPy::Context.with_span(
        operation: 'evaluation.example',
        'dspy.module' => 'Evaluator',
        'evaluation.program' => @program.class.name,
        'evaluation.has_metric' => !@metric.nil?
      ) do
        begin
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
                metrics = metric_result
                passed = metrics[:passed] || metrics['passed'] || true
              else
                passed = !!metric_result
                metrics[:passed] = passed
              end
            rescue => e
              passed = false
              metrics[:error] = e.message
              metrics[:passed] = false
            end
          end
          
          EvaluationResult.new(
            example: example,
            prediction: prediction,
            trace: trace,
            metrics: metrics,
            passed: passed
          )
        rescue => e
          # Return failed evaluation result
          error_metrics = {
            error: e.message,
            passed: false
          }
          
          if @provide_traceback
            error_metrics[:traceback] = e.backtrace&.first(10) || []
          end
          
          EvaluationResult.new(
            example: example,
            prediction: nil,
            trace: trace,
            metrics: error_metrics,
            passed: false
          )
        end
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
      DSPy::Context.with_span(
        operation: 'evaluation.batch',
        'dspy.module' => 'Evaluator',
        'evaluation.program' => @program.class.name,
        'evaluation.num_examples' => devset.length,
        'evaluation.has_metric' => !@metric.nil?,
        'evaluation.num_threads' => @num_threads
      ) do
        results = []
        errors = 0
        
        if display_progress
          puts "Evaluating #{devset.length} examples..."
        end
        
        devset.each_with_index do |example, index|
          break if errors >= @max_errors
          
          begin
            result = call(example)
            results << result
            
            unless result.passed
              errors += 1
            end
            
            if display_progress && (index + 1) % 10 == 0
              puts "Processed #{index + 1}/#{devset.length} examples (#{results.count(&:passed)} passed)"
            end
            
          rescue => e
            errors += 1
            puts "Error processing example #{index}: #{e.message}" if display_progress
            
            # Create error result
            error_result = EvaluationResult.new(
              example: example,
              prediction: nil,
              trace: nil,
              metrics: { error: e.message, passed: false },
              passed: false
            )
            results << error_result
          end
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
      end
    end

    private

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
      
      # Start with basic metrics
      aggregated = {
        total_examples: results.length,
        passed_examples: results.count(&:passed),
        failed_examples: results.count { |r| !r.passed }
      }
      
      # Aggregate numeric metrics
      numeric_metrics = {}
      results.each do |result|
        result.metrics.each do |key, value|
          next if [:error, :traceback, :passed].include?(key)
          next unless value.is_a?(Numeric)
          
          numeric_metrics[key] ||= []
          numeric_metrics[key] << value
        end
      end
      
      # Calculate averages for numeric metrics
      numeric_metrics.each do |key, values|
        aggregated[:"#{key}_avg"] = values.sum.to_f / values.length
        aggregated[:"#{key}_min"] = values.min
        aggregated[:"#{key}_max"] = values.max
      end
      
      # Calculate pass rate
      aggregated[:pass_rate] = aggregated[:total_examples] > 0 ? 
        aggregated[:passed_examples].to_f / aggregated[:total_examples] : 0.0
      
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
        
        return false if expected.nil? || actual.nil?
        
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
        
        return false if expected.nil? || actual.nil?
        
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
        
        return { passed: false, error: "Missing values" } if expected.nil? || actual.nil?
        
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