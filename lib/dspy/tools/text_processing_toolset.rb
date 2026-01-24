# frozen_string_literal: true

require 'sorbet-runtime'
require 'tempfile'
require 'set'
require_relative 'toolset'

module DSPy
  module Tools
    # Text processing toolset that provides text analysis and manipulation tools
    # Includes grep, word count, ripgrep, and other text processing utilities
    class TextProcessingToolset < Toolset
      extend T::Sig

      toolset_name "text"

      # Expose methods as tools with descriptions
      tool :grep, description: "Search for patterns in text using grep"
      tool :word_count, tool_name: "text_wc", description: "Count lines, words, and characters in text"
      tool :ripgrep, tool_name: "text_rg", description: "Fast text search using ripgrep"
      tool :extract_lines, description: "Extract specific line ranges from text"
      tool :filter_lines, description: "Filter lines matching or not matching a pattern"
      tool :unique_lines, description: "Get unique lines from text"
      tool :sort_lines, description: "Sort lines in text"
      tool :summarize_text, description: "Generate statistical summary of text content"

      sig { void }
      def initialize
        # No persistent state needed for text processing
      end

      sig { params(text: String, pattern: String, ignore_case: T::Boolean, count_only: T::Boolean).returns(String) }
      def grep(text:, pattern:, ignore_case: true, count_only: false)
        # Create temporary file to use with grep
        temp_file = Tempfile.new('text_processing')
        temp_file.write(text)
        temp_file.close

        flags = []
        flags << '-i' if ignore_case
        flags << '-c' if count_only

        cmd = "grep #{flags.join(' ')} '#{pattern}' '#{temp_file.path}'"
        result = `#{cmd} 2>/dev/null`
        
        temp_file.unlink
        
        if count_only
          "Found #{result.strip} matches for pattern '#{pattern}'"
        elsif result.empty?
          "No matches found for pattern '#{pattern}'"
        else
          result
        end
      rescue StandardError => e
        "Error running grep: #{e.message}"
      end

      sig { params(text: String, lines_only: T::Boolean, words_only: T::Boolean, chars_only: T::Boolean).returns(String) }
      def word_count(text:, lines_only: false, words_only: false, chars_only: false)
        lines = text.lines.count
        words = text.split(/\s+/).reject(&:empty?).count
        chars = text.length

        if lines_only
          "Lines: #{lines}"
        elsif words_only
          "Words: #{words}"
        elsif chars_only
          "Characters: #{chars}"
        else
          "Lines: #{lines}, Words: #{words}, Characters: #{chars}"
        end
      end

      sig { params(text: String, pattern: String, context: Integer).returns(String) }
      def ripgrep(text:, pattern:, context: 0)
        temp_file = Tempfile.new('text_processing')
        temp_file.write(text)
        temp_file.close

        cmd = "rg"
        cmd += " -C #{context}" if context > 0
        cmd += " '#{pattern}' '#{temp_file.path}'"
        
        result = `#{cmd} 2>/dev/null`
        
        temp_file.unlink
        
        if result.empty?
          "No matches found for pattern '#{pattern}'"
        else
          result
        end
      rescue StandardError => e
        "Error running ripgrep: #{e.message}"
      end

      sig { params(text: String, start_line: Integer, end_line: T.nilable(Integer)).returns(String) }
      def extract_lines(text:, start_line:, end_line: nil)
        lines = text.lines
        start_idx = [start_line - 1, 0].max  # Convert to 0-based, ensure >= 0
        
        if end_line
          end_idx = [end_line - 1, lines.length - 1].min  # Convert to 0-based, ensure <= last line
          extracted = lines[start_idx..end_idx]
        else
          extracted = lines[start_idx, 1]  # Just one line
        end
        
        extracted&.join || ""
      end

      sig { params(text: String, pattern: String, invert: T::Boolean).returns(String) }
      def filter_lines(text:, pattern:, invert: false)
        lines = text.lines
        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        
        filtered = if invert
          lines.reject { |line| line.match?(regex) }
        else
          lines.select { |line| line.match?(regex) }
        end
        
        filtered.join
      end

      sig { params(text: String, preserve_order: T::Boolean).returns(String) }
      def unique_lines(text:, preserve_order: true)
        lines = text.lines.map(&:chomp)
        
        unique = if preserve_order
          lines.uniq
        else
          lines.to_set.to_a.sort
        end
        
        unique.map { |line| "#{line}\n" }.join
      end

      sig { params(text: String, reverse: T::Boolean, numeric: T::Boolean).returns(String) }
      def sort_lines(text:, reverse: false, numeric: false)
        lines = text.lines.map(&:chomp)
        
        sorted = if numeric
          lines.sort_by { |line| line.to_f }
        else
          lines.sort
        end
        
        sorted.reverse! if reverse
        sorted.map { |line| "#{line}\n" }.join
      end

      sig { params(text: String).returns(String) }
      def summarize_text(text:)
        lines = text.lines
        words = text.split(/\s+/).reject(&:empty?)
        chars = text.length
        
        # Find most common words (simple analysis)
        word_freq = words.each_with_object(Hash.new(0)) { |word, hash| hash[word.downcase.gsub(/[^\w]/, '')] += 1 }
        top_words = word_freq.reject { |word, _| word.length < 3 }.sort_by { |_, count| -count }.first(5)
        
        # Basic text statistics
        avg_line_length = lines.empty? ? 0 : (chars.to_f / lines.count).round(2)
        avg_word_length = words.empty? ? 0 : (words.sum(&:length).to_f / words.count).round(2)
        
        summary = []
        summary << "Text Summary:"
        summary << "  Lines: #{lines.count}"
        summary << "  Words: #{words.count}"
        summary << "  Characters: #{chars}"
        summary << "  Average line length: #{avg_line_length}"
        summary << "  Average word length: #{avg_word_length}"
        
        unless top_words.empty?
          summary << "  Most frequent words:"
          top_words.each { |word, count| summary << "    #{word}: #{count}" }
        end
        
        summary.join("\n")
      end
    end
  end
end