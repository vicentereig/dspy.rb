#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Cursor-Style PDF Summarization (RLM-lite, no REPL)
#
# Usage:
#   bundle exec ruby examples/pdf_recursive_summarizer.rb --pdf path/to/file.pdf \
#     --query "What are the key findings?" \
#     --model openai/gpt-4o-mini
#
# Notes:
# - Requires `pdf-reader` gem.
# - Uses a navigator signature that decides where to peek/search/summarize next.
# - Outputs a final summary and (optionally) the cursor history to JSON.

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
DEFAULT_MAX_CHARS = 12_000
DEFAULT_GROUP_SIZE = 6
DEFAULT_MAX_STEPS = 8
DEFAULT_MAX_PAGES_PER_STEP = 6
DEFAULT_PREVIEW_PAGES = 3
DEFAULT_TRACE = true

options = {
  pdf_path: nil,
  query: DEFAULT_QUERY,
  model: DEFAULT_MODEL,
  max_chars: DEFAULT_MAX_CHARS,
  group_size: DEFAULT_GROUP_SIZE,
  max_steps: DEFAULT_MAX_STEPS,
  max_pages_per_step: DEFAULT_MAX_PAGES_PER_STEP,
  preview_pages: DEFAULT_PREVIEW_PAGES,
  trace: DEFAULT_TRACE,
  output_json: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby examples/pdf_recursive_summarizer.rb --pdf path/to/file.pdf [options]"

  opts.on('--pdf PATH', 'Path to PDF file') { |v| options[:pdf_path] = v }
  opts.on('--query QUERY', 'Focus question for the summary') { |v| options[:query] = v }
  opts.on('--model MODEL_ID', 'Model id (default: openai/gpt-4o-mini)') { |v| options[:model] = v }
  opts.on('--max-chars N', Integer, 'Max chars per peek/summarize (default: 12000)') { |v| options[:max_chars] = v }
  opts.on('--group-size N', Integer, 'Summaries per merge step (default: 6)') { |v| options[:group_size] = v }
  opts.on('--max-steps N', Integer, 'Max cursor steps (default: 8)') { |v| options[:max_steps] = v }
  opts.on('--max-pages-per-step N', Integer, 'Max pages per peek/summarize (default: 6)') { |v| options[:max_pages_per_step] = v }
  opts.on('--preview-pages N', Integer, 'Pages to include in preview (default: 3)') { |v| options[:preview_pages] = v }
  opts.on('--[no-]trace', 'Print cursor trace (default: true)') { |v| options[:trace] = v }
  opts.on('--output-json PATH', 'Write cursor history to JSON') { |v| options[:output_json] = v }
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit 0
  end
end

parser.parse!(ARGV)
options[:pdf_path] ||= ARGV.shift

# Give users a quick hint when the script is run directly
if $PROGRAM_NAME == __FILE__ && $stdout.tty?
  if !ENV['LANGFUSE_PUBLIC_KEY'] && !ENV['LANGFUSE_SECRET_KEY']
    warn "ℹ️ Set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY to stream traces to Langfuse."
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
               else
                 nil
               end

if required_key && ENV[required_key].to_s.strip.empty?
  warn "Missing #{required_key}. Set it in .env or your shell before running this example."
  exit 1
end

DSPy.configure do |config|
  api_key = required_key ? ENV[required_key] : nil
  config.lm = DSPy::LM.new(options[:model], api_key: api_key)
end

class ChunkSummary < DSPy::Signature
  description 'Summarize a document chunk for a given query, capturing key points succinctly.'

  input do
    const :query, String, description: 'User query guiding the summary'
    const :chunk_range, String, description: 'Page range for the chunk'
    const :chunk_text, String, description: 'Chunk content to summarize'
  end

  output do
    const :summary, String, description: 'Concise summary focusing on the query'
    const :key_points, T::Array[String], description: 'Key bullet points', default: []
  end
end

class SectionSummary < T::Struct
  const :title, String
  const :summary, String
  const :key_points, T::Array[String], default: []
end

class SynthesizeSummaries < DSPy::Signature
  description 'Combine section summaries into a coherent summary.'

  input do
    const :query, String, description: 'User query guiding the synthesis'
    const :summary_scope, String, description: 'Scope or title for the synthesis'
    const :section_summaries, T::Array[SectionSummary], description: 'Section summaries to merge'
  end

  output do
    const :summary, String, description: 'Synthesis that answers the query'
    const :key_points, T::Array[String], description: 'Key points distilled from sections', default: []
  end
end

class CursorAction < T::Enum
  enums do
    Peek = new('peek')
    Search = new('search')
    Summarize = new('summarize')
    Answer = new('answer')
  end
end

class NavigateDocument < DSPy::Signature
  description <<~DESC
    You are a cursor navigating a long PDF. Decide the next action to answer the query.
    Actions: peek (read pages), search (find keyword), summarize (summarize pages or last peek), answer (final response).
    Only choose pages within 1..total_pages. Keep steps minimal.
  DESC

  input do
    const :query, String, description: 'User query'
    const :document_preview, String, description: 'Short preview of the document'
    const :total_pages, Integer, description: 'Total number of pages'
    const :history, String, description: 'Previous cursor actions and results'
    const :last_result, String, description: 'Most recent action result'
  end

  output do
    const :action, CursorAction, description: 'Next action: peek, search, summarize, answer'
    const :start_page, Integer, description: 'Start page for peek/summarize (use 0 to reuse last peek)', default: 1
    const :end_page, Integer, description: 'End page for peek/summarize (use 0 to reuse last peek)', default: 1
    const :search_pattern, T.nilable(String), description: 'Keyword/phrase to search', default: nil
    const :answer, T.nilable(String), description: 'Final answer if action is answer', default: nil
    const :rationale, T.nilable(String), description: 'Short reason for this action', default: nil
  end
end

class CursorSummarizer < DSPy::Module
  extend T::Sig

  sig { void }
  def initialize
    super()
    @navigator = DSPy::Predict.new(NavigateDocument)
    @summarize = DSPy::Predict.new(ChunkSummary)
    @synthesize = DSPy::Predict.new(SynthesizeSummaries)
    reset_token_usage!
    @token_subscription_id = nil
  end

  sig do
    params(
      pages: T::Array[String],
      query: String,
      max_steps: Integer,
      max_pages_per_step: Integer,
      max_chars: Integer,
      preview_pages: Integer,
      group_size: Integer,
      trace: T::Boolean
    ).returns([SectionSummary, T::Array[T::Hash[Symbol, T.untyped]], T::Array[SectionSummary]])
  end
  def forward(pages:, query:, max_steps:, max_pages_per_step:, max_chars:, preview_pages:, group_size:, trace:)
    ensure_token_subscription!
    reset_token_usage!
    history = []
    summaries = []
    last_result = 'none'
    last_chunk_text = nil
    total_pages = pages.length
    preview = build_document_preview(pages, preview_pages: preview_pages)

    begin
      max_steps.times do |step|
        action = @navigator.call(
          query: query,
          document_preview: preview,
          total_pages: total_pages,
          history: format_history(history),
          last_result: truncate(last_result, 1200)
        )

      case action.action
      when CursorAction::Peek
        range = sanitize_range(action.start_page, action.end_page, total_pages, max_pages_per_step)
        chunk_text = extract_range(pages, range[:start], range[:end], max_chars)
        last_chunk_text = chunk_text
        last_result = "Peeked pages #{range[:start]}-#{range[:end]} (#{chunk_text.length} chars)."
        entry = build_history_entry(step + 1, action.action.serialize, range, action.rationale, last_result)
        history << entry
        print_trace(entry) if trace
      when CursorAction::Search
        pattern = action.search_pattern.to_s.strip
        if pattern.empty?
          last_result = 'Search requested but no pattern provided.'
        else
          matches = search_pages(pages, pattern)
          last_result = format_search_result(pattern, matches)
        end
        entry = build_history_entry(step + 1, action.action.serialize, nil, action.rationale, last_result)
        history << entry
        print_trace(entry) if trace
      when CursorAction::Summarize
        range = nil
        chunk_text = nil
        if action.start_page.to_i > 0 && action.end_page.to_i > 0
          range = sanitize_range(action.start_page, action.end_page, total_pages, max_pages_per_step)
          chunk_text = extract_range(pages, range[:start], range[:end], max_chars)
        elsif last_chunk_text
          chunk_text = last_chunk_text
        else
          range = { start: 1, end: [total_pages, max_pages_per_step].min }
          chunk_text = extract_range(pages, range[:start], range[:end], max_chars)
        end

        label = range ? "pages #{range[:start]}-#{range[:end]}" : 'last peek'
        result = @summarize.call(
          query: query,
          chunk_range: label,
          chunk_text: chunk_text
        )
        summary = SectionSummary.new(
          title: label,
          summary: result.summary.to_s,
          key_points: Array(result.key_points)
        )
        summaries << summary
        last_result = "Summary added for #{label}."
        entry = build_history_entry(step + 1, action.action.serialize, range, action.rationale, last_result)
        history << entry
        print_trace(entry) if trace
      when CursorAction::Answer
        final = build_final_answer(action.answer, summaries, query, group_size)
        entry = build_history_entry(step + 1, action.action.serialize, nil, action.rationale, 'Final answer produced.')
        history << entry
        print_trace(entry) if trace
        return [final, history, summaries]
      else
        last_result = 'Unknown action; stopping.'
        entry = build_history_entry(step + 1, 'unknown', nil, action.rationale, last_result)
        history << entry
        print_trace(entry) if trace
        break
      end
      end

      final = build_final_answer(nil, summaries, query, group_size)
      [final, history, summaries]
    ensure
      unsubscribe_token_subscription!
    end
  end

  sig { returns(T::Hash[Symbol, Integer]) }
  def token_usage
    @token_usage.dup
  end

  private

  def build_document_preview(pages, preview_pages:)
    page_count = pages.length
    preview_count = [preview_pages, page_count].min
    lines = []
    lines << "Document length: #{page_count} pages"
    lines << "Preview of first #{preview_count} pages:"
    pages.first(preview_count).each_with_index do |text, idx|
      snippet = text.to_s.gsub(/\s+/, ' ').strip
      snippet = snippet[0, 1200]
      lines << "Page #{idx + 1} preview: #{snippet}"
    end
    lines.join("\n")
  end

  def extract_range(pages, start_page, end_page, max_chars)
    slice = pages[(start_page - 1)..(end_page - 1)] || []
    text = slice.map.with_index do |page_text, idx|
      page_number = start_page + idx
      cleaned = page_text.to_s.strip
      "Page #{page_number}\n#{cleaned}"
    end.join("\n\n")
    truncate(text, max_chars)
  end

  def search_pages(pages, pattern)
    regex = Regexp.new(Regexp.escape(pattern), Regexp::IGNORECASE)
    matches = []
    pages.each_with_index do |text, index|
      next unless text.to_s.match?(regex)
      snippet = text.to_s.gsub(/\s+/, ' ').strip
      snippet = snippet[0, 200]
      matches << { page: index + 1, snippet: snippet }
    end
    matches
  rescue RegexpError
    []
  end

  def format_search_result(pattern, matches)
    return "No matches for '#{pattern}'." if matches.empty?

    lines = ["Matches for '#{pattern}':"]
    matches.first(6).each do |match|
      lines << "- Page #{match[:page]}: #{match[:snippet]}"
    end
    lines.join("\n")
  end

  def sanitize_range(start_page, end_page, total_pages, max_pages_per_step)
    start_page = start_page.to_i
    end_page = end_page.to_i
    start_page = 1 if start_page < 1
    end_page = total_pages if end_page < 1 || end_page > total_pages
    start_page, end_page = [start_page, end_page].minmax
    if (end_page - start_page + 1) > max_pages_per_step
      end_page = start_page + max_pages_per_step - 1
    end
    { start: start_page, end: end_page }
  end

  def build_final_answer(answer_text, summaries, query, group_size)
    if answer_text && !answer_text.to_s.strip.empty?
      return SectionSummary.new(title: 'answer', summary: answer_text.to_s.strip, key_points: [])
    end

    return SectionSummary.new(title: 'answer', summary: '', key_points: []) if summaries.empty?

    final = synthesize_in_rounds(summaries, query, scope: 'document', group_size: group_size)
    SectionSummary.new(title: 'answer', summary: final.summary, key_points: final.key_points)
  end

  def synthesize_in_rounds(summaries, query, scope:, group_size:)
    return SectionSummary.new(title: scope, summary: '', key_points: []) if summaries.empty?

    current = summaries.dup
    round = 0
    while current.length > group_size
      grouped = current.each_slice(group_size).to_a
      current = grouped.map.with_index do |group, idx|
        result = @synthesize.call(
          query: query,
          summary_scope: "#{scope} round #{round + 1} group #{idx + 1}",
          section_summaries: group
        )
        SectionSummary.new(
          title: "#{scope} group #{idx + 1}",
          summary: result.summary.to_s,
          key_points: Array(result.key_points)
        )
      end
      round += 1
    end

    final = @synthesize.call(
      query: query,
      summary_scope: scope,
      section_summaries: current
    )
    SectionSummary.new(
      title: scope,
      summary: final.summary.to_s,
      key_points: Array(final.key_points)
    )
  end

  def truncate(text, max_chars)
    return '' if text.nil?
    return text if text.length <= max_chars

    text[0, max_chars] + "\n[truncated]"
  end

  def format_history(history)
    return 'none' if history.empty?

    history.map do |entry|
      step = entry[:step]
      action = entry[:action]
      range = entry[:range]
      range_text = range ? "pages #{range[:start]}-#{range[:end]}" : 'n/a'
      result = truncate(entry[:result].to_s, 200)
      "Step #{step}: #{action} (#{range_text}) -> #{result}"
    end.join("\n")
  end

  def build_history_entry(step, action, range, rationale, result)
    {
      step: step,
      action: action,
      range: range,
      rationale: rationale.to_s,
      result: result.to_s
    }
  end

  def print_trace(entry)
    range = entry[:range]
    range_text = range ? "pages #{range[:start]}-#{range[:end]}" : 'n/a'
    rationale = entry[:rationale].to_s.strip
    result = truncate(entry[:result].to_s, 140)
    line = "[Step #{entry[:step]}] #{entry[:action]} (#{range_text})"
    line += " | reason: #{truncate(rationale, 80)}" unless rationale.empty?
    line += " | #{result}" unless result.empty?
    puts line
  end

  def reset_token_usage!
    @token_usage = {
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0
    }
  end

  def ensure_token_subscription!
    return if @token_subscription_id

    @token_subscription_id = DSPy.events.subscribe('lm.tokens') do |event_name, attrs|
      track_tokens(event_name, attrs)
    end
  end

  def unsubscribe_token_subscription!
    return unless @token_subscription_id

    DSPy.events.unsubscribe(@token_subscription_id)
    @token_subscription_id = nil
  end

  def track_tokens(_event_name, attrs)
    @token_usage[:input_tokens] += attrs[:input_tokens].to_i
    @token_usage[:output_tokens] += attrs[:output_tokens].to_i
    @token_usage[:total_tokens] += attrs[:total_tokens].to_i
  end
end

def extract_pages(pdf_path)
  reader = PDF::Reader.new(pdf_path)
  reader.pages.map(&:text)
end

puts "Reading PDF: #{options[:pdf_path]}"
pages = extract_pages(options[:pdf_path])
if pages.empty? || pages.all? { |text| text.to_s.strip.empty? }
  warn "No text extracted from PDF."
  exit 1
end

summarizer = CursorSummarizer.new
final_summary, history, summaries = summarizer.call(
  pages: pages,
  query: options[:query],
  max_steps: options[:max_steps],
  max_pages_per_step: options[:max_pages_per_step],
  max_chars: options[:max_chars],
  preview_pages: options[:preview_pages],
  group_size: options[:group_size],
  trace: options[:trace]
)

puts "\n=== Final Summary ==="
puts final_summary.summary

unless Array(final_summary.key_points).empty?
  puts "\n=== Key Points ==="
  final_summary.key_points.each { |point| puts "- #{point}" }
end

usage = summarizer.token_usage
puts "\n=== Token Usage ==="
puts "Input tokens:  #{usage[:input_tokens]}"
puts "Output tokens: #{usage[:output_tokens]}"
puts "Total tokens:  #{usage[:total_tokens]}"

if options[:output_json]
  payload = {
    pdf: options[:pdf_path],
    query: options[:query],
    model: options[:model],
    final_summary: final_summary.summary,
    final_key_points: final_summary.key_points,
    summaries: summaries.map { |summary| { title: summary.title, summary: summary.summary, key_points: summary.key_points } },
    cursor_history: history,
    token_usage: usage
  }

  File.write(options[:output_json], JSON.pretty_generate(payload))
  puts "\nWrote JSON output to #{options[:output_json]}"
end

DSPy::Observability.flush! if DSPy::Observability.respond_to?(:flush!)
