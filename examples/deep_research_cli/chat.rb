#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'optparse'
require 'uri'

require 'dspy'
require 'cli/ui'
require 'cli/ui/truncater'
require 'dotenv'

require 'dspy/deep_research'
require 'dspy/deep_research_with_memory'
require 'dspy/deep_search'
require 'dspy/observability'

Dotenv.load(File.expand_path('../../.env', __dir__))

module Examples
  module DeepResearchCLI
    DEFAULT_MODEL = ENV.fetch('DEEP_RESEARCH_MODEL', 'openai/gpt-4o-mini')
    MEMORY_LIMIT  = 5

    class SpinnerSubscriber < DSPy::Events::BaseSubscriber
      def initialize(spinner)
        super()
        @spinner = spinner
      end

      def subscribe
        add_subscription('deep_search.loop.started') do |_, attrs|
          update("Searching: #{truncate(attrs[:query])}")
        end

        add_subscription('deep_search.fetch.started') do |_, attrs|
          update("Fetching: #{host_for(attrs[:url])}")
        end

        add_subscription('deep_search.reason.decision') do |_, attrs|
          next unless attrs[:decision]

          update("Decision: #{attrs[:decision]}")
        end

        add_subscription('deep_research.section.started') do |_, attrs|
          update("Section: #{truncate(attrs[:title])}")
        end

        add_subscription('deep_research.section.qa_retry') do |_, attrs|
          update("Retry #{attrs[:attempt]}: #{truncate(attrs[:follow_up_prompt])}")
        end

        add_subscription('deep_research.report.ready') do |_, attrs|
          update("Synthesizing report (#{attrs[:section_count]} sections)")
        end
      end

      private

      def update(text)
        @spinner.update_title(text)
      end

      def truncate(text, length = 40)
        CLI::UI::Truncater.truncate(text.to_s, length)
      end

      def host_for(url)
        URI(url).host || truncate(url, 30)
      rescue URI::InvalidURIError
        truncate(url, 30)
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
        dry_run: false,
        memory_limit: MEMORY_LIMIT
      }

      OptionParser.new do |parser|
        parser.banner = 'Usage: chat.rb [options]'
        parser.on('--dry-run', 'Run with stubbed DeepResearch module (no network requests)') do
          options[:dry_run] = true
        end
        parser.on('--memory-limit=COUNT', Integer, 'Number of transcripts to keep in memory') do |value|
          options[:memory_limit] = value
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

    def build_agent(dry_run:, memory_limit:)
      module_instance =
        if dry_run
          DryRunDeepResearch.new
        else
          DSPy::DeepResearch::Module.new
        end

      DSPy::DeepResearchWithMemory.new(
        deep_research_module: module_instance,
        memory_limit: memory_limit
      )
    end

    def render_result(result, agent, brief)
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
      render_memory(agent)
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

    def render_memory(agent)
      history = agent.memory
      return if history.empty?

      CLI::UI::Frame.open("Recent Memory (#{history.length}/#{agent.memory_limit})") do
        history.reverse.each_with_index do |entry, index|
          CLI::UI::Frame.divider("Run ##{history.length - index}")
          puts CLI::UI.fmt("{{bold:Brief}}: #{entry[:brief]}")
          puts CLI::UI.fmt("{{bold:Report}}: #{truncate_text(entry[:report], 200)}")
          unless entry[:citations].empty?
            puts CLI::UI.fmt("{{bold:Citations}}: #{entry[:citations].join(', ')}")
          end
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
      CLI::UI::SpinGroup.new do |spin_group|
        spin_group.add('Starting DeepResearch') do |spinner|
          subscriber = SpinnerSubscriber.new(spinner)
          subscriber.subscribe
          result = agent.call(brief: brief)
          spinner.update_title('Report ready')
          subscriber.unsubscribe
        end
      end

      render_result(result, agent, brief)
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
agent = Examples::DeepResearchCLI.build_agent(
  dry_run: options[:dry_run],
  memory_limit: options[:memory_limit]
)

Examples::DeepResearchCLI.prompt_loop(agent)

CLI::UI.puts(CLI::UI.fmt("{{green:Goodbye!}}"))
