#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Structure-First PDF Summarization (RLM Pattern)
#
# A simpler, more predictable approach than agentic navigation:
# 1. Discover document structure from preview
# 2. Summarize relevant sections (parallelizable)
# 3. Synthesize into final answer
#
# Usage:
#   bundle exec ruby examples/pdf_recursive_summarizer.rb --pdf path/to/file.pdf \
#     --query "What are the key findings?" \
#     --model openai/gpt-4o-mini
#
# Notes:
# - Requires `pdf-reader` gem
# - Uses map-reduce pattern: discover → map(summarize) → reduce(synthesize)
# - Predictable token usage, parallelizable middle step

require 'optparse'
require 'json'
require 'dotenv'
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

begin
  require 'pdf/reader'
rescue LoadError
  warn "Missing dependency: pdf-reader. Add `gem 'pdf-reader'` and run bundle install."
  exit 1
end

# Configure observability for Langfuse tracing
DSPy::Observability.configure!

DEFAULT_MODEL = ENV.fetch('DSPY_PDF_SUMMARIZER_MODEL', 'openai/gpt-4o-mini')
DEFAULT_QUERY = 'Provide a concise summary of the document.'
DEFAULT_MAX_SECTION_CHARS = 8_000
DEFAULT_PREVIEW_LINES = 100

options = {
  pdf_path: nil,
  query: DEFAULT_QUERY,
  model: DEFAULT_MODEL,
  max_section_chars: DEFAULT_MAX_SECTION_CHARS,
  preview_lines: DEFAULT_PREVIEW_LINES,
  output_json: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby examples/pdf_recursive_summarizer.rb --pdf path/to/file.pdf [options]"

  opts.on('--pdf PATH', 'Path to PDF file') { |v| options[:pdf_path] = v }
  opts.on('--query QUERY', 'Focus question for the summary') { |v| options[:query] = v }
  opts.on('--model MODEL_ID', 'Model id (default: openai/gpt-4o-mini)') { |v| options[:model] = v }
  opts.on('--max-section-chars N', Integer, 'Max chars per section (default: 8000)') { |v| options[:max_section_chars] = v }
  opts.on('--preview-lines N', Integer, 'Lines for structure discovery (default: 100)') { |v| options[:preview_lines] = v }
  opts.on('--output-json PATH', 'Write results to JSON') { |v| options[:output_json] = v }
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit 0
  end
end

parser.parse!(ARGV)
options[:pdf_path] ||= ARGV.shift

# Hint about observability
if $PROGRAM_NAME == __FILE__ && $stdout.tty?
  if !ENV['LANGFUSE_PUBLIC_KEY'] && !ENV['LANGFUSE_SECRET_KEY']
    warn "Set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY to stream traces to Langfuse."
  end
end

unless options[:pdf_path] && File.exist?(options[:pdf_path])
  warn "PDF file not found. Use --pdf PATH."
  puts parser
  exit 1
end

provider = options[:model].to_s.split('/', 2).first
required_key = case provider
               when 'openai' then 'OPENAI_API_KEY'
               when 'anthropic' then 'ANTHROPIC_API_KEY'
               when 'gemini', 'google' then 'GEMINI_API_KEY'
               end

if required_key && ENV[required_key].to_s.strip.empty?
  warn "Missing #{required_key}. Set it in .env or your shell before running this example."
  exit 1
end

DSPy.configure do |config|
  api_key = required_key ? ENV[required_key] : nil
  config.lm = DSPy::LM.new(options[:model], api_key: api_key)
end

# --- Signatures ---

class Relevance < T::Enum
  enums do
    High = new('high')
    Medium = new('medium')
    Low = new('low')
    Skip = new('skip')
  end
end

class Section < T::Struct
  const :title, String
  const :start_line, Integer
  const :end_line, Integer
  const :relevance, Relevance
end

class DiscoverStructure < DSPy::Signature
  description <<~DESC
    Identify the logical sections of a document based on its preview.
    Assign relevance scores based on how useful each section is for answering the query.
    Use 'skip' for boilerplate like headers, footers, tables of contents, or irrelevant sections.
  DESC

  input do
    const :document_preview, String, description: 'First N lines of the document with line numbers'
    const :total_lines, Integer, description: 'Total number of lines in the document'
    const :query, String, description: 'What the user wants to know (guides relevance scoring)'
  end

  output do
    const :sections, T::Array[Section], description: 'Identified sections with line ranges and relevance'
  end
end

class SectionSummary < T::Struct
  const :title, String
  const :summary, String
  const :key_facts, T::Array[String], default: []
end

class SummarizeSection < DSPy::Signature
  description 'Summarize a document section, focusing on information relevant to the query.'

  input do
    const :section_title, String, description: 'Title of the section'
    const :section_text, String, description: 'Full text of the section'
    const :query, String, description: 'User query for relevance focus'
  end

  output do
    const :summary, String, description: 'Concise summary of the section'
    const :key_facts, T::Array[String], description: 'Key facts extracted from this section', default: []
  end
end

class SynthesizeSummaries < DSPy::Signature
  description 'Combine section summaries into a coherent answer to the query.'

  input do
    const :query, String, description: 'The original user query'
    const :section_summaries, T::Array[SectionSummary], description: 'Summaries from each section'
  end

  output do
    const :answer, String, description: 'Synthesized answer addressing the query'
    const :key_points, T::Array[String], description: 'Key points from across all sections', default: []
  end
end

# --- Module ---

class RLMSummarizer < DSPy::Module
  extend T::Sig

  sig { void }
  def initialize
    super()
    @discover = DSPy::ChainOfThought.new(DiscoverStructure)
    @summarize = DSPy::Predict.new(SummarizeSection)
    @synthesize = DSPy::Predict.new(SynthesizeSummaries)
  end

  def forward(lines:, query:, preview_lines:, max_section_chars:)
    # Step 1: Build preview with line numbers
    preview = build_preview(lines, preview_lines)

    # Step 2: Discover structure
    puts "Discovering document structure..."
    structure = @discover.call(
      document_preview: preview,
      total_lines: lines.length,
      query: query
    )

    sections = structure.sections
    puts "Found #{sections.length} sections"

    # Step 3: Filter and summarize relevant sections
    relevant_sections = sections.reject { |s| s.relevance == Relevance::Skip }
    puts "Summarizing #{relevant_sections.length} relevant sections..."

    summaries = relevant_sections.map do |section|
      section_text = extract_section(lines, section, max_section_chars)
      puts "  - #{section.title} (lines #{section.start_line}-#{section.end_line}, #{section_text.length} chars)"

      result = @summarize.call(
        section_title: section.title,
        section_text: section_text,
        query: query
      )

      SectionSummary.new(
        title: section.title,
        summary: result.summary,
        key_facts: Array(result.key_facts)
      )
    end

    # Step 4: Synthesize
    puts "Synthesizing final answer..."
    final = @synthesize.call(
      query: query,
      section_summaries: summaries
    )

    {
      answer: final.answer,
      key_points: Array(final.key_points),
      sections: sections.map { |s| { title: s.title, start_line: s.start_line, end_line: s.end_line, relevance: s.relevance.serialize } },
      summaries: summaries.map { |s| { title: s.title, summary: s.summary, key_facts: s.key_facts } }
    }
  end

  private

  def build_preview(lines, preview_lines)
    count = [preview_lines, lines.length].min
    numbered = lines.first(count).map.with_index(1) { |line, idx| "#{idx}: #{line}" }
    numbered.join + "\n...\n[#{lines.length} total lines]"
  end

  def extract_section(lines, section, max_chars)
    start_idx = [(section.start_line - 1), 0].max
    end_idx = [(section.end_line - 1), lines.length - 1].min
    text = lines[start_idx..end_idx].join
    text.length > max_chars ? text[0, max_chars] + "\n[truncated]" : text
  end
end

# --- Main ---

def extract_lines(pdf_path)
  reader = PDF::Reader.new(pdf_path)
  reader.pages.flat_map { |page| page.text.lines }
end

puts "Reading PDF: #{options[:pdf_path]}"
lines = extract_lines(options[:pdf_path])
if lines.empty? || lines.all? { |line| line.strip.empty? }
  warn "No text extracted from PDF."
  exit 1
end
puts "Extracted #{lines.length} lines"

summarizer = RLMSummarizer.new
result = summarizer.call(
  lines: lines,
  query: options[:query],
  preview_lines: options[:preview_lines],
  max_section_chars: options[:max_section_chars]
)

puts "\n=== Answer ==="
puts result[:answer]

unless result[:key_points].empty?
  puts "\n=== Key Points ==="
  result[:key_points].each { |point| puts "- #{point}" }
end

if options[:output_json]
  payload = {
    pdf: options[:pdf_path],
    query: options[:query],
    model: options[:model],
    **result
  }
  File.write(options[:output_json], JSON.pretty_generate(payload))
  puts "\nWrote JSON output to #{options[:output_json]}"
end

DSPy::Observability.flush! if DSPy::Observability.respond_to?(:flush!)
