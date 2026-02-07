#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'optparse'
require 'uri'

require 'dspy'
require 'cli/ui'
require 'dotenv'

require 'dspy/deep_research'
require 'dspy/deep_search'
require 'dspy/observability'

Dotenv.load(File.expand_path('../../.env', __dir__))

module Examples
  module DeepResearchCLI
    DEFAULT_MODEL = ENV.fetch('DEEP_RESEARCH_MODEL', 'openai/gpt-4.1')

    class StatusBoard
      extend T::Sig

      sig { params(updater: T.proc.params(arg0: String).void).void }
      def initialize(updater)
        @updater = updater
        @status = "Starting"
        @input_tokens = 0
        @output_tokens = 0
        @start_time = Time.now
        @subscriptions = []
      end

      attr_reader :input_tokens, :output_tokens, :status

      def subscribe
        @subscriptions << DSPy.events.subscribe('deep_research.section.started') do |_, attrs|
          update_status("Section #{truncate(value_for(attrs, :title))} (attempt #{value_for(attrs, :attempt)})")
        end

        @subscriptions << DSPy.events.subscribe('deep_research.section.qa_retry') do |_, attrs|
          update_status("Retrying #{truncate(value_for(attrs, :title))}")
        end

        @subscriptions << DSPy.events.subscribe('deep_research.section.approved') do |_, attrs|
          update_status("Approved #{truncate(value_for(attrs, :title))}")
        end

        @subscriptions << DSPy.events.subscribe('deep_research.report.ready') do |_, attrs|
          update_status("Report ready (#{value_for(attrs, :section_count)} sections)")
        end

        @subscriptions << DSPy.events.subscribe('deep_search.loop.started') do |_, attrs|
          update_status("Searching #{truncate(value_for(attrs, :query))}")
        end

        @subscriptions << DSPy.events.subscribe('deep_search.fetch.started') do |_, attrs|
          update_status("Fetching #{host_for(value_for(attrs, :url))}")
        end

        @subscriptions << DSPy.events.subscribe('deep_search.fetch.completed') do |_, attrs|
          update_status("Fetched (notes +#{value_for(attrs, :notes_added)})")
        end

        @subscriptions << DSPy.events.subscribe('deep_search.fetch.failed') do |_, attrs|
          update_status("Fetch failed #{host_for(value_for(attrs, :url))}")
        end

        @subscriptions << DSPy.events.subscribe('deep_search.reason.decision') do |_, attrs|
          decision = value_for(attrs, :decision)
          next unless decision

          update_status("Decision: #{decision}")
        end

        @subscriptions << DSPy.events.subscribe('lm.tokens') do |_, attrs|
          next unless relevant_module?(attrs)

          @input_tokens += value_for(attrs, :input_tokens).to_i
          @output_tokens += value_for(attrs, :output_tokens).to_i
          refresh
        end
      end

      def unsubscribe
        @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
        @subscriptions.clear
      end

      def relevant_module?(attrs)
        root = value_for(attrs, :module_root) || {}
        klass = value_for(root, :class)
        return false unless klass

        klass.to_s.include?('DeepSearch') || klass.to_s.include?('DeepResearch')
      end

      def value_for(hash, key)
        return nil unless hash

        hash[key] || hash[key.to_s]
      end

      def update_status(text)
        @status = text
        refresh
      end

      def refresh
        @updater.call(label)
      end

      def label
        "Status: #{@status} | In: #{@input_tokens} Out: #{@output_tokens} | Elapsed: #{formatted_elapsed}"
      end

      def elapsed_string
        formatted_elapsed
      end

      def mark_completed
        update_status("Completed")
      end

      def mark_error(message)
        update_status(message)
      end

      private

      def truncate(text, length = 40)
        str = text.to_s
        return str if str.length <= length

        str[0, length - 1] + "…"
      end

      def host_for(url)
        URI(url).host || truncate(url, 30)
      rescue URI::InvalidURIError
        truncate(url, 30)
      end

      def formatted_elapsed
        seconds = (Time.now - @start_time).to_i
        hrs = seconds / 3600
        mins = (seconds % 3600) / 60
        secs = seconds % 60

        parts = []
        parts << "#{hrs}h" if hrs.positive?
        parts << "#{mins}m" if mins.positive? || hrs.positive?
        parts << "#{secs}s"
        parts.join(' ')
      end
    end

    class DryRunDeepResearch < DSPy::Module
      extend T::Sig

      sig { void }
      def initialize
        super()
        @counter = 0
      end

      sig do
        override
          .params(input_values: T.untyped)
          .returns(DSPy::DeepResearch::Module::Result)
      end
      def forward_untyped(**input_values)
        brief = input_values[:brief]
        unless brief.is_a?(String)
          raise ArgumentError, "DryRunDeepResearch expects keyword argument :brief"
        end

        @counter += 1
        citation = format("https://dry.run/%<id>d", id: @counter)
        section = DSPy::DeepResearch::Module::SectionResult.new(
          identifier: "dry-#{@counter}",
          title: "Summary",
          draft: "Key findings for #{brief}",
          citations: [citation],
          attempt: 0
        )

        DSPy::DeepResearch::Module::Result.new(
          report: "Dry-run report for #{brief}",
          sections: [section],
          citations: [citation]
        )
      end
    end

    module_function

    def parse_options(argv)
      options = {
        dry_run: false
      }

      OptionParser.new do |parser|
        parser.banner = 'Usage: chat.rb [options]'
        parser.on('--dry-run', 'Run with stubbed DeepResearch module (no network requests)') do
          options[:dry_run] = true
        end
        parser.on('-h', '--help', 'Show this message') do
          puts parser
          exit
        end
      end.parse!(argv)

      options
    end

    def ensure_configuration!(dry_run:)
      if dry_run
        CLI::UI.puts(CLI::UI.fmt("{{yellow:Running in dry-run mode. No external API calls will be made.}}"))
        return
      end

      configure_lm!

      unless ENV['EXA_API_KEY']
        CLI::UI.puts(CLI::UI.fmt("{{red:Missing EXA_API_KEY.}} Add it to .env or your shell environment."))
        exit 1
      end
    end

    def configure_lm!
      if ENV['OPENAI_API_KEY']
        DSPy.configure do |config|
          config.lm = DSPy::LM.new(
            DEFAULT_MODEL,
            api_key: ENV['OPENAI_API_KEY']
          )
        end
      elsif ENV['ANTHROPIC_API_KEY']
        DSPy.configure do |config|
          config.lm = DSPy::LM.new(
            ENV.fetch('DEEP_RESEARCH_MODEL', 'anthropic/claude-3-5-sonnet-20241022'),
            api_key: ENV['ANTHROPIC_API_KEY']
          )
        end
      else
        CLI::UI.puts(CLI::UI.fmt("{{red:Missing LLM API key.}} Set OPENAI_API_KEY or ANTHROPIC_API_KEY."))
        exit 1
      end

      DSPy::Observability.configure!
    end

    def build_agent(dry_run:)
      if dry_run
        DryRunDeepResearch.new
      else
        DSPy::DeepResearch::Module.new
      end
    end

    def render_result(result, brief)
      CLI::UI::Frame.open("Deep Research Report") do
        CLI::UI::Frame.divider("Brief")
        puts CLI::UI.fmt("{{cyan:#{brief}}}")

        CLI::UI::Frame.divider("Report")
        puts CLI::UI.fmt(truncate_text(result.report, 500))

        CLI::UI::Frame.divider("Citations")
        if result.citations.empty?
          puts "– No citations returned"
        else
          result.citations.each { |citation| puts "• #{citation}" }
        end
      end

      render_sections(result)
    end

    def render_sections(result)
      result.sections.each do |section|
        CLI::UI::Frame.open("Section: #{section.title}") do
          puts CLI::UI.fmt(truncate_text(section.draft, 400))
          next if section.citations.empty?

          CLI::UI::Frame.divider("Section Citations")
          section.citations.each { |citation| puts "• #{citation}" }
        end
      end
    end

    def prompt_loop(agent)
      CLI::UI::Frame.open("DSPy Deep Research CLI") do
        loop do
          brief = CLI::UI::Prompt.ask(
            'What research brief would you like to explore? (blank or exit to quit)',
            allow_empty: true
          )

          break if brief.nil? || brief.strip.empty? || brief.strip.casecmp('exit').zero?

          run_research(agent, brief.strip)
        end
      end
    end

    def run_research(agent, brief)
      result = nil
      error = nil
      status_board = nil

      CLI::UI::Spinner.spin("Status: Initializing | In: 0 Out: 0 | Elapsed: 0s") do |spinner|
        status_board = StatusBoard.new(->(label) { spinner.update_title(label) })
        begin
          spinner.update_title(status_board.label)
          status_board.subscribe
          result = agent.call(brief: brief)
          status_board.mark_completed
        rescue DSPy::DeepSearch::Module::TokenBudgetExceeded => e
          error = e
          status_board.mark_error("Budget exceeded")
        ensure
          status_board.unsubscribe if status_board
        end
      end

      if result
        render_result(result, brief)
      else
        CLI::UI.puts(CLI::UI.fmt("{{red:Token budget exceeded before an answer was synthesized.}}"))
      end
    end

    def truncate_text(text, limit = 80)
      str = text.to_s.strip
      return str if str.length <= limit

      str[0, limit - 1] + "…"
    end
  end
end

options = Examples::DeepResearchCLI.parse_options(ARGV)

CLI::UI::StdoutRouter.enable
CLI::UI.frame_style = :box

Examples::DeepResearchCLI.ensure_configuration!(dry_run: options[:dry_run])
agent = Examples::DeepResearchCLI.build_agent(dry_run: options[:dry_run])

Examples::DeepResearchCLI.prompt_loop(agent)

CLI::UI.puts(CLI::UI.fmt("{{green:Goodbye!}}"))
