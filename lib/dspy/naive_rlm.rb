# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'timeout'
require_relative 'module'
require_relative 'signature'
require_relative 'predict'
require_relative 'chain_of_thought'

module DSPy
  # Naive RLM (Recursive Language Model) implementation
  #
  # Implements context selection primitives as structured output instead of code execution.
  # The LLM outputs actions (peek, grep, partition, finish) and Ruby executes them.
  #
  # See ADR-017 for design rationale.
  #
  # @example
  #   rlm = DSPy::NaiveRLM.new
  #   lines = File.readlines("large_document.txt")
  #   result = rlm.call(lines: lines, query: "What are the key findings?")
  #
  module NaiveRLM
    # Discriminated union action types - each struct represents one action primitive
    module Actions
      class Peek < T::Struct
        const :start_line, Integer, description: 'Start line (1-indexed)'
        const :end_line, Integer, description: 'End line (1-indexed)'
      end

      class Grep < T::Struct
        const :pattern, String, description: 'Regex pattern to search for'
      end

      class Partition < T::Struct
        const :chunk_size, Integer, default: 500, description: 'Lines per chunk for parallel summarization'
      end

      class Finish < T::Struct
        const :answer, String, description: 'Final answer to the query'
      end
    end

    # Type-safe result from Navigator.forward
    class Result < T::Struct
      const :answer, String
      const :iterations, Integer
      const :history, T::Array[String], default: []
      const :max_iterations_reached, T::Boolean, default: false
    end

    # Relevance scoring for summarized chunks
    class Relevance < T::Enum
      enums do
        High = new('high')
        Medium = new('medium')
        Low = new('low')
        None = new('none')
      end
    end

    # Signature for LLM to select next action
    class SelectAction < DSPy::Signature
      description "Select next action to navigate a document and answer a query."

      input do
        const :query, String, description: 'What the user wants to know'
        const :document_stats, String, description: 'Document metadata: total lines, etc.'
        const :context_window, String, description: 'Currently visible content (preview or last action result)'
        const :history, T::Array[String], default: [], description: 'Previous actions and their results (summaries)'
      end

      output do
        const :reasoning, String, description: 'Why this action will help answer the query'
        const :action, T.any(Actions::Peek, Actions::Grep, Actions::Partition, Actions::Finish)
      end
    end

    # Signature for summarizing extracted chunks
    class SummarizeChunk < DSPy::Signature
      description 'Summarize a chunk of document content, focusing on information relevant to the query.'

      input do
        const :query, String, description: 'What the user wants to know'
        const :chunk_context, String, description: 'Where this chunk is from (e.g., Lines 450-480)'
        const :chunk_text, String, description: 'The extracted text to summarize'
      end

      output do
        const :summary, String, description: 'Concise summary of relevant information found'
        const :relevance, Relevance, description: 'How relevant this chunk is to the query'
      end
    end

    # Main NaiveRLM module
    class Navigator < DSPy::Module
      extend T::Sig

      DEFAULT_MAX_ITERATIONS = 10
      DEFAULT_PREVIEW_LINES = 100
      DEFAULT_GREP_CONTEXT = 10
      DEFAULT_MAX_GREP_MATCHES = 5
      DEFAULT_PARTITION_SIZE = 500
      SUMMARIZE_THRESHOLD = 500

      sig { returns(Integer) }
      attr_reader :max_iterations

      sig { params(max_iterations: Integer).void }
      def initialize(max_iterations: DEFAULT_MAX_ITERATIONS)
        super()
        @max_iterations = max_iterations
        @selector = T.let(DSPy::ChainOfThought.new(SelectAction), DSPy::ChainOfThought)
        @summarizer = T.let(DSPy::Predict.new(SummarizeChunk), DSPy::Predict)
      end

      sig { override.returns(T::Array[[String, DSPy::Module]]) }
      def named_predictors
        [
          ['selector', @selector],
          ['summarizer', @summarizer]
        ]
      end

      sig { params(kwargs: T.untyped).returns(T.untyped).override }
      def forward(**kwargs)
        lines = T.let(kwargs.fetch(:lines), T::Array[String])
        query = T.let(kwargs.fetch(:query), String)
        preview = build_preview(lines, DEFAULT_PREVIEW_LINES)
        current_window = preview
        history = T.let([], T::Array[String])
        iterations = 0

        while iterations < @max_iterations
          iterations += 1

          decision = @selector.call(
            query: query,
            document_stats: "Total lines: #{lines.length}",
            context_window: current_window,
            history: history
          )

          action = decision.action

          case action
          when Actions::Finish
            return Result.new(
              answer: action.answer,
              iterations: iterations,
              history: history
            )

          when Actions::Peek
            result = execute_peek(lines, action.start_line, action.end_line)
            current_window = result[:text]
            summary = summarize_if_large(result[:text], query, result[:context])
            history << "PEEK #{result[:context]}: #{summary}"

          when Actions::Grep
            pattern = action.pattern
            matches = execute_grep(lines, pattern)

            if matches.empty?
              history << "GREP '#{pattern}': No matches found"
              current_window = preview
            else
              summaries = matches.map do |match|
                chunk_result = @summarizer.call(
                  query: query,
                  chunk_context: match[:context],
                  chunk_text: match[:text]
                )
                "[#{match[:context]}] #{chunk_result.summary} (#{chunk_result.relevance.serialize})"
              end
              history << "GREP '#{pattern}': #{matches.length} matches\n  #{summaries.join("\n  ")}"
              current_window = format_grep_results(matches)
            end

          when Actions::Partition
            chunk_size = action.chunk_size
            chunks = partition_lines(lines, chunk_size)

            summaries = chunks.filter_map do |chunk|
              chunk_result = @summarizer.call(
                query: query,
                chunk_context: chunk[:context],
                chunk_text: chunk[:text]
              )
              "[#{chunk[:context]}] #{chunk_result.summary}" unless chunk_result.relevance == Relevance::None
            end

            history << "PARTITION (#{chunk_size} lines/chunk, #{chunks.length} chunks):\n  #{summaries.join("\n  ")}"
            current_window = summaries.join("\n")
          end
        end

        # Max iterations reached
        Result.new(
          answer: synthesize_from_history(history),
          iterations: iterations,
          history: history,
          max_iterations_reached: true
        )
      end

      private

      sig { params(lines: T::Array[String], count: Integer).returns(String) }
      def build_preview(lines, count)
        actual = [count, lines.length].min
        numbered = lines.first(actual).map.with_index(1) { |l, i| "#{i}: #{l.chomp}" }
        "#{numbered.join("\n")}\n...\n[#{lines.length} total lines]"
      end

      sig { params(lines: T::Array[String], start_line: Integer, end_line: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def execute_peek(lines, start_line, end_line)
        start_idx = [[start_line - 1, 0].max, lines.length - 1].min
        end_idx = [[end_line - 1, 0].max, lines.length - 1].min

        # Swap if reversed
        start_idx, end_idx = end_idx, start_idx if start_idx > end_idx

        text = lines[start_idx..end_idx].map.with_index(start_idx + 1) { |l, i| "#{i}: #{l.chomp}" }.join("\n")

        {
          text: text,
          context: "[#{start_idx + 1}-#{end_idx + 1}]",
          start: start_idx + 1,
          end: end_idx + 1
        }
      end

      REGEX_TIMEOUT_SECONDS = 0.1

      sig { params(lines: T::Array[String], pattern: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def execute_grep(lines, pattern)
        return [] if pattern.empty?

        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        matches = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
        seen_ranges = T.let([], T::Array[Range])

        lines.each_with_index do |line, idx|
          # ReDoS protection: timeout on regex match since pattern comes from LLM
          matched = begin
            Timeout.timeout(REGEX_TIMEOUT_SECONDS) { line.match?(regex) }
          rescue Timeout::Error
            false
          end
          next unless matched

          start_idx = [idx - DEFAULT_GREP_CONTEXT, 0].max
          end_idx = [idx + DEFAULT_GREP_CONTEXT, lines.length - 1].min
          range = start_idx..end_idx

          next if seen_ranges.any? { |r| ranges_overlap?(r, range) }

          seen_ranges << range
          text = lines[start_idx..end_idx].map.with_index(start_idx + 1) { |l, i| "#{i}: #{l.chomp}" }.join("\n")

          matches << {
            context: "Lines #{start_idx + 1}-#{end_idx + 1}, matched '#{pattern}'",
            text: text,
            match_line: idx + 1
          }

          break if matches.length >= DEFAULT_MAX_GREP_MATCHES
        end

        matches
      rescue RegexpError
        [] # Invalid pattern
      end

      sig { params(lines: T::Array[String], chunk_size: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def partition_lines(lines, chunk_size)
        lines.each_slice(chunk_size).with_index.map do |chunk, i|
          start_line = i * chunk_size + 1
          end_line = start_line + chunk.length - 1
          {
            context: "Lines #{start_line}-#{end_line}",
            text: chunk.map(&:chomp).join("\n")
          }
        end
      end

      sig { params(r1: Range, r2: Range).returns(T::Boolean) }
      def ranges_overlap?(r1, r2)
        r1.cover?(r2.begin) || r1.cover?(r2.end) || r2.cover?(r1.begin)
      end

      sig { params(matches: T::Array[T::Hash[Symbol, T.untyped]]).returns(String) }
      def format_grep_results(matches)
        matches.map { |m| "--- #{m[:context]} ---\n#{m[:text]}" }.join("\n\n")
      end

      sig { params(text: String, query: String, context: String).returns(String) }
      def summarize_if_large(text, query, context)
        return text if text.length < SUMMARIZE_THRESHOLD

        result = @summarizer.call(
          query: query,
          chunk_context: context,
          chunk_text: text
        )
        result.summary
      end

      sig { params(history: T::Array[String]).returns(String) }
      def synthesize_from_history(history)
        return 'No information gathered' if history.empty?

        "Based on exploration: #{history.last(3).join(' | ')}"
      end
    end
  end
end
