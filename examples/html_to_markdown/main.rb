#!/usr/bin/env ruby
# frozen_string_literal: true

# HTML to Markdown AST Experiment
#
# This example compares two approaches for converting HTML to Markdown:
#   Approach A: HTML -> Structured AST (typed) -> Render to Markdown
#   Approach B: HTML -> Markdown string directly
#
# The hypothesis: Do structured output types help produce better Markdown,
# or is simple String -> String conversion just as good?
#
# Usage:
#   ANTHROPIC_API_KEY=your-key ruby examples/html_to_markdown/main.rb

require 'bundler/setup'
require 'dspy'
require 'dotenv/load'

require_relative 'types'
require_relative 'renderer'
require_relative 'signatures'

module HtmlToMarkdown
  class Experiment
    def initialize
      @renderer = MarkdownRenderer.new
      setup_dspy
    end

    def run(html)
      puts "\n#{'=' * 70}"
      puts "HTML to Markdown Experiment"
      puts '=' * 70
      puts "\n📄 Input HTML:"
      puts '-' * 70
      puts html
      puts '-' * 70

      puts "\n🔬 Running both approaches..."
      puts

      ast_result = run_approach_a(html)
      direct_result = run_approach_b(html)

      compare_results(ast_result, direct_result)
    end

    private

    def setup_dspy
      api_key = ENV.fetch('ANTHROPIC_API_KEY') do
        raise 'ANTHROPIC_API_KEY environment variable required'
      end

      DSPy.configure do |c|
        c.lm = DSPy::LM.new(
          'anthropic/claude-haiku-4-5-20251001',
          api_key: api_key
        )
      end
    end

    def run_approach_a(html)
      puts "🅰️  Approach A: HTML -> AST -> Markdown"
      puts '   (Structured output with typed nodes)'

      parser = DSPy::Predict.new(ParseHtmlToAst)

      start_time = Time.now
      result = parser.call(html: html)
      parse_time = Time.now - start_time

      rendered = @renderer.render(result.document)

      {
        name: 'AST (Structured)',
        markdown: rendered,
        time: parse_time,
        node_count: count_nodes(result.document),
        document: result.document
      }
    end

    def run_approach_b(html)
      puts "🅱️  Approach B: HTML -> Markdown"
      puts '   (Direct string conversion)'

      converter = DSPy::Predict.new(ConvertHtmlToMarkdown)

      start_time = Time.now
      result = converter.call(html: html)
      convert_time = Time.now - start_time

      {
        name: 'Direct (String)',
        markdown: result.markdown,
        time: convert_time,
        node_count: nil,
        document: nil
      }
    end

    def count_nodes(document)
      count = 0
      document.nodes.each { |node| count += count_node_recursive(node) }
      count
    end

    def count_node_recursive(node)
      count = 1
      if node.children
        node.children.each { |child| count += count_node_recursive(child) }
      end
      count
    end

    def compare_results(ast_result, direct_result)
      puts "\n#{'=' * 70}"
      puts "Results Comparison"
      puts '=' * 70

      puts "\n📊 Metrics:"
      puts '-' * 70
      puts format("%-25s %15s %15s", '', ast_result[:name], direct_result[:name])
      puts format("%-25s %15.3fs %15.3fs", 'Time:', ast_result[:time], direct_result[:time])
      puts format("%-25s %15d %15s", 'AST Nodes:', ast_result[:node_count] || 0, 'N/A')
      puts format("%-25s %15d %15d", 'Output Length:', ast_result[:markdown].length, direct_result[:markdown].length)

      puts "\n📝 AST Approach Output:"
      puts '-' * 70
      puts ast_result[:markdown]

      puts "\n📝 Direct Approach Output:"
      puts '-' * 70
      puts direct_result[:markdown]

      puts "\n🔍 Analysis:"
      puts '-' * 70
      analyze_differences(ast_result[:markdown], direct_result[:markdown])

      puts "\n#{'=' * 70}"
    end

    def analyze_differences(ast_md, direct_md)
      if ast_md.strip == direct_md.strip
        puts "✅ Both approaches produced identical output!"
      else
        puts "⚠️  Outputs differ. Analyzing..."

        # Check for key elements
        checks = [
          ['Headers (#)', ->(md) { md.scan(/^#+\s/).count }],
          ['Bold (**)', ->(md) { md.scan(/\*\*[^*]+\*\*/).count }],
          ['Italic (*)', ->(md) { md.scan(/(?<!\*)\*[^*]+\*(?!\*)/).count }],
          ['Code blocks (```)', ->(md) { md.scan(/```/).count / 2 }],
          ['Inline code (`)', ->(md) { md.scan(/(?<!`)`[^`]+`(?!`)/).count }],
          ['Links ([...])', ->(md) { md.scan(/\[[^\]]+\]\([^)]+\)/).count }],
          ['List items', ->(md) { md.scan(/^[\s]*[-*\d.]+\s/).count }]
        ]

        puts format("\n%-20s %10s %10s", 'Element', 'AST', 'Direct')
        checks.each do |name, counter|
          ast_count = counter.call(ast_md)
          direct_count = counter.call(direct_md)
          status = ast_count == direct_count ? '✓' : '✗'
          puts format("%-20s %10d %10d %s", name, ast_count, direct_count, status)
        end
      end
    end
  end
end

# Sample HTML for testing
SAMPLE_HTML = <<~HTML
  <article>
    <h1>Introduction to DSPy.rb</h1>
    <p>DSPy.rb is a <strong>type-safe</strong> framework for building LLM applications in Ruby.</p>

    <h2>Key Features</h2>
    <ul>
      <li>Structured outputs with <em>Sorbet</em> types</li>
      <li>Union types for flexible responses</li>
      <li>Built-in prompt optimization</li>
    </ul>

    <h2>Quick Example</h2>
    <pre><code class="language-ruby">
class Summarize < DSPy::Signature
  input do
    const :text, String
  end

  output do
    const :summary, String
  end
end

summarizer = DSPy::Predict.new(Summarize)
result = summarizer.call(text: "Long article...")
puts result.summary
    </code></pre>

    <p>Learn more at <a href="https://github.com/vicentereig/dspy.rb">the GitHub repository</a>.</p>

    <hr>

    <blockquote>
      <p>DSPy.rb brings the power of structured prompting to Ruby developers.</p>
    </blockquote>
  </article>
HTML

if __FILE__ == $PROGRAM_NAME
  experiment = HtmlToMarkdown::Experiment.new
  experiment.run(SAMPLE_HTML)
end
