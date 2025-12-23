# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'

module DSPy
  module Scores
    # Built-in evaluators for common evaluation patterns
    # Each evaluator returns a ScoreEvent that can be exported to Langfuse
    module Evaluators
      extend T::Sig

      # Exact string match evaluator
      # Returns 1.0 if output exactly matches expected, 0.0 otherwise
      sig do
        params(
          output: String,
          expected: String,
          name: String,
          ignore_case: T::Boolean,
          comment: T.nilable(String),
          trace_id: T.nilable(String),
          observation_id: T.nilable(String),
          emit: T::Boolean
        ).returns(ScoreEvent)
      end
      def self.exact_match(
        output:,
        expected:,
        name: 'exact_match',
        ignore_case: false,
        comment: nil,
        trace_id: nil,
        observation_id: nil,
        emit: true
      )
        match = if ignore_case
                  output.downcase == expected.downcase
                else
                  output == expected
                end

        DSPy::Scores.create(
          name: name,
          value: match ? 1.0 : 0.0,
          data_type: DataType::Numeric,
          comment: comment || (match ? 'Exact match' : 'No match'),
          trace_id: trace_id,
          observation_id: observation_id,
          emit: emit
        )
      end

      # Substring containment evaluator
      # Returns 1.0 if output contains expected, 0.0 otherwise
      sig do
        params(
          output: String,
          expected: String,
          name: String,
          ignore_case: T::Boolean,
          comment: T.nilable(String),
          trace_id: T.nilable(String),
          observation_id: T.nilable(String),
          emit: T::Boolean
        ).returns(ScoreEvent)
      end
      def self.contains(
        output:,
        expected:,
        name: 'contains',
        ignore_case: false,
        comment: nil,
        trace_id: nil,
        observation_id: nil,
        emit: true
      )
        match = if ignore_case
                  output.downcase.include?(expected.downcase)
                else
                  output.include?(expected)
                end

        DSPy::Scores.create(
          name: name,
          value: match ? 1.0 : 0.0,
          data_type: DataType::Numeric,
          comment: comment || (match ? 'Contains expected' : 'Does not contain expected'),
          trace_id: trace_id,
          observation_id: observation_id,
          emit: emit
        )
      end

      # Regular expression match evaluator
      # Returns 1.0 if output matches pattern, 0.0 otherwise
      sig do
        params(
          output: String,
          pattern: T.any(Regexp, String),
          name: String,
          comment: T.nilable(String),
          trace_id: T.nilable(String),
          observation_id: T.nilable(String),
          emit: T::Boolean
        ).returns(ScoreEvent)
      end
      def self.regex_match(
        output:,
        pattern:,
        name: 'regex_match',
        comment: nil,
        trace_id: nil,
        observation_id: nil,
        emit: true
      )
        regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
        match = regex.match?(output)

        DSPy::Scores.create(
          name: name,
          value: match ? 1.0 : 0.0,
          data_type: DataType::Numeric,
          comment: comment || (match ? 'Regex matched' : 'Regex did not match'),
          trace_id: trace_id,
          observation_id: observation_id,
          emit: emit
        )
      end

      # Length check evaluator
      # Returns 1.0 if output length is within range, 0.0 otherwise
      sig do
        params(
          output: String,
          min_length: T.nilable(Integer),
          max_length: T.nilable(Integer),
          name: String,
          comment: T.nilable(String),
          trace_id: T.nilable(String),
          observation_id: T.nilable(String),
          emit: T::Boolean
        ).returns(ScoreEvent)
      end
      def self.length_check(
        output:,
        min_length: nil,
        max_length: nil,
        name: 'length_check',
        comment: nil,
        trace_id: nil,
        observation_id: nil,
        emit: true
      )
        length = output.length
        valid = true
        valid = false if min_length && length < min_length
        valid = false if max_length && length > max_length

        DSPy::Scores.create(
          name: name,
          value: valid ? 1.0 : 0.0,
          data_type: DataType::Numeric,
          comment: comment || "Length: #{length} (min: #{min_length || 'none'}, max: #{max_length || 'none'})",
          trace_id: trace_id,
          observation_id: observation_id,
          emit: emit
        )
      end

      # Levenshtein similarity evaluator
      # Returns normalized similarity score between 0.0 and 1.0
      sig do
        params(
          output: String,
          expected: String,
          name: String,
          comment: T.nilable(String),
          trace_id: T.nilable(String),
          observation_id: T.nilable(String),
          emit: T::Boolean
        ).returns(ScoreEvent)
      end
      def self.similarity(
        output:,
        expected:,
        name: 'similarity',
        comment: nil,
        trace_id: nil,
        observation_id: nil,
        emit: true
      )
        distance = levenshtein_distance(output, expected)
        max_length = [output.length, expected.length].max
        score = max_length.zero? ? 1.0 : 1.0 - (distance.to_f / max_length)

        DSPy::Scores.create(
          name: name,
          value: score.round(4),
          data_type: DataType::Numeric,
          comment: comment || "Levenshtein distance: #{distance}",
          trace_id: trace_id,
          observation_id: observation_id,
          emit: emit
        )
      end

      # JSON validity evaluator
      # Returns 1.0 if output is valid JSON, 0.0 otherwise
      sig do
        params(
          output: String,
          name: String,
          comment: T.nilable(String),
          trace_id: T.nilable(String),
          observation_id: T.nilable(String),
          emit: T::Boolean
        ).returns(ScoreEvent)
      end
      def self.json_valid(
        output:,
        name: 'json_valid',
        comment: nil,
        trace_id: nil,
        observation_id: nil,
        emit: true
      )
        valid = begin
          JSON.parse(output)
          true
        rescue JSON::ParserError
          false
        end

        DSPy::Scores.create(
          name: name,
          value: valid ? 1.0 : 0.0,
          data_type: DataType::Numeric,
          comment: comment || (valid ? 'Valid JSON' : 'Invalid JSON'),
          trace_id: trace_id,
          observation_id: observation_id,
          emit: emit
        )
      end

      # Levenshtein distance implementation
      sig { params(str1: String, str2: String).returns(Integer) }
      def self.levenshtein_distance(str1, str2)
        m = str1.length
        n = str2.length

        return n if m.zero?
        return m if n.zero?

        # Create distance matrix
        d = Array.new(m + 1) { Array.new(n + 1, 0) }

        # Initialize first column
        (0..m).each { |i| d[i][0] = i }
        # Initialize first row
        (0..n).each { |j| d[0][j] = j }

        # Fill in the rest of the matrix
        (1..m).each do |i|
          (1..n).each do |j|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            d[i][j] = [
              d[i - 1][j] + 1,     # deletion
              d[i][j - 1] + 1,     # insertion
              d[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        d[m][n]
      end
    end
  end
end
