#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "psych"

module EconomicalWritingAudit
  Finding = Data.define(:path, :line, :category, :rule_id, :message) do
    def sort_key
      [path, line, category, rule_id]
    end

    def to_h
      {path: path, line: line, category: category, rule_id: rule_id, message: message}
    end

    def to_s
      "#{path}:#{line}: #{category}: #{rule_id}: #{message}"
    end
  end

  Diagnostic = Data.define(:path, :line, :rule_id, :message) do
    def to_s
      "#{path}:#{line}: parse: #{rule_id}: #{message}"
    end
  end

  class Corpus
    FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB

    attr_reader :root

    def initialize(root:, manifest: nil)
      @root = Pathname(root).expand_path
      manifest_path = Pathname(manifest || "docs/editorial/public-doc-corpus.yml")
      @manifest_path = (manifest_path.absolute? ? manifest_path : @root.join(manifest_path)).expand_path
      document = Psych.safe_load_file(@manifest_path, aliases: false)
      @rules = document.fetch("rules")
      validate_rules!
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception, KeyError => error
      raise ArgumentError, "cannot load corpus manifest #{@manifest_path}: #{error.message}"
    end

    def default_paths
      all_repository_files.filter_map do |relative|
        rule = record(relative)
        relative if eligible?(rule)
      end.sort
    end

    def record(relative)
      rule = classification(relative)
      return unless rule

      rule.merge(rule.fetch("overrides", {}).fetch(relative, {})).except("overrides")
    end

    def explicit_paths(arguments)
      raise ArgumentError, "at least one path is required" if arguments.empty?

      arguments.map { |argument| normalize_explicit_path(argument) }.uniq.sort.each do |relative|
        rule = record(relative)
        if rule.nil?
          raise ArgumentError, "#{relative}: path is not classified by the public documentation corpus"
        end
        if rule.fetch("kind") == "excluded"
          raise ArgumentError, "#{relative}: path is excluded by corpus rule #{rule.fetch('id')}"
        end
        if rule["owner_type"] == "derived"
          raise ArgumentError, "#{relative}: derived/generated source cannot be audited directly"
        end
        unless %w[public history].include?(rule.fetch("kind"))
          raise ArgumentError, "#{relative}: unsupported corpus kind #{rule.fetch('kind').inspect}"
        end
      end
    end

    def read(relative)
      absolute = @root.join(relative)
      bytes = File.binread(absolute)
      text = bytes.force_encoding(Encoding::UTF_8)
      raise ArgumentError, "#{relative}: input is not valid UTF-8" unless text.valid_encoding?

      text
    rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR => error
      raise ArgumentError, "#{relative}: cannot read input: #{error.message}"
    end

    private

    def validate_rules!
      ids = @rules.map { |rule| rule.fetch("id") }
      raise ArgumentError, "corpus rule ids must be unique" unless ids.uniq.length == ids.length

      @rules.each do |rule|
        selectors = [rule.key?("path"), rule.key?("glob")].count(true)
        raise ArgumentError, "#{rule.fetch('id')}: specify exactly one of path or glob" unless selectors == 1
        raise ArgumentError, "#{rule.fetch('id')}: missing kind" unless rule["kind"]
      end
    end

    def all_repository_files
      Dir.glob("**/*", File::FNM_DOTMATCH, base: @root.to_s).select do |relative|
        next false if relative == "." || relative.start_with?(".git/")

        File.file?(@root.join(relative))
      end
    end

    def classification(relative)
      matches = @rules.select { |rule| matches?(rule, relative) }
      raise ArgumentError, "#{relative}: matched multiple corpus rules: #{matches.map { _1.fetch('id') }.join(', ')}" if matches.length > 1

      matches.first
    end

    def matches?(rule, relative)
      selected = if rule["path"]
                   relative == rule["path"]
                 else
                   File.fnmatch?(rule.fetch("glob"), relative, FLAGS)
                 end
      selected && !Array(rule["except"]).include?(relative)
    end

    def eligible?(rule)
      rule && %w[public history].include?(rule["kind"]) && rule["owner_type"] != "derived"
    end

    def normalize_explicit_path(argument)
      candidate = Pathname(argument)
      absolute = candidate.absolute? ? candidate.cleanpath : @root.join(candidate).cleanpath
      relative = absolute.relative_path_from(@root).to_s
      raise ArgumentError, "#{argument}: path escapes the repository root" if relative == ".." || relative.start_with?("../")
      raise ArgumentError, "#{relative}: path is not a regular file" unless File.file?(absolute)

      relative
    end
  end

  class Masker
    Result = Data.define(:text, :diagnostics)

    def initialize(path, text)
      @path = path
      @lines = text.lines
      @lines = [text] if @lines.empty? && !text.empty?
      @diagnostics = []
    end

    def call
      masked = mask_blocks
      masked = mask_inline_code(masked) if @diagnostics.empty?
      masked = mask_destinations_and_urls(masked)
      Result.new(masked.join, @diagnostics)
    end

    private

    def mask_blocks
      output = @lines.dup
      index = 0

      if @lines.first&.sub(/^\uFEFF/, "")&.match?(/\A---\s*(?:\r?\n)?\z/)
        closing = (1...@lines.length).find { |line| @lines[line].match?(/\A(?:---|\.\.\.)\s*(?:\r?\n)?\z/) }
        unless closing
          @diagnostics << Diagnostic.new(@path, 1, "frontmatter-unterminated", "unterminated frontmatter; suppressed remainder")
          return output.map { |line| blank(line) }
        end
        (0..closing).each { |line| output[line] = blank(output[line]) }
        index = closing + 1
      end

      fence = nil
      while index < @lines.length
        line = @lines[index]
        body = line.delete_suffix("\n").delete_suffix("\r")
        if fence
          output[index] = blank(line)
          if body.match?(/\A {0,3}#{Regexp.escape(fence.fetch(:character))}{#{fence.fetch(:length)},}\s*\z/)
            fence = nil
          end
        elsif (opening = body.match(/\A {0,3}(?<delimiter>`{3,}|~{3,}).*\z/))
          delimiter = opening[:delimiter]
          fence = {character: delimiter[0], length: delimiter.length, line: index + 1}
          output[index] = blank(line)
        elsif body.match?(/\A {0,3}>/)
          output[index] = blank(line)
        elsif body.match?(/\A(?: {4,}|\t)/)
          output[index] = blank(line)
        end
        index += 1
      end

      if fence
        @diagnostics << Diagnostic.new(@path, fence.fetch(:line), "fence-unterminated", "unterminated #{fence.fetch(:character)} fence; suppressed remainder")
        (fence.fetch(:line) - 1...output.length).each { |line| output[line] = blank(output[line]) }
      end

      output
    end

    def mask_inline_code(lines)
      delimiter = nil
      opening_line = nil
      output = []

      lines.each_with_index do |line, line_index|
        characters = line.chars
        index = 0
        while index < characters.length
          if characters[index] == "`"
            finish = index
            finish += 1 while finish < characters.length && characters[finish] == "`"
            run_length = finish - index
            if delimiter.nil?
              delimiter = run_length
              opening_line = line_index + 1
              (index...finish).each { |position| characters[position] = " " }
            elsif run_length == delimiter
              (index...finish).each { |position| characters[position] = " " }
              delimiter = nil
              opening_line = nil
            elsif delimiter
              (index...finish).each { |position| characters[position] = " " }
            end
            index = finish
          elsif delimiter
            characters[index] = " " unless ["\n", "\r"].include?(characters[index])
            index += 1
          else
            index += 1
          end
        end
        output << characters.join
      end

      if delimiter
        @diagnostics << Diagnostic.new(@path, opening_line, "inline-code-unterminated", "unterminated #{delimiter}-backtick code span; suppressed remainder")
      end
      output
    end

    def mask_destinations_and_urls(lines)
      text = lines.join
      text = text.gsub(/\]\((?:\\.|[^()\\]|\((?:\\.|[^()\\])*\))*\)/m) do |match|
        "](#{blank(match[2...-1])})"
      end
      text = text.gsub(/<(?:https?:\/\/|mailto:)[^>\r\n]+>/i) { |match| blank(match) }
      text = text.gsub(%r{https?://[^\s<>)\]]+}i) { |match| blank(match) }
      text.lines
    end

    def blank(text)
      text.each_char.map { |character| ["\n", "\r"].include?(character) ? character : " " }.join
    end
  end

  class Rules
    CATEGORIES = [
      "AI aphorism", "synthetic flourish", "chatbot cadence", "empty contrast",
      "tutorial patter", "generic heading", "vague praise", "throat-clearing",
      "narrating comments", "elegant variation"
    ].freeze

    GENERIC_HEADING = /\A(?:overview|introduction|getting started|how it works|why it matters|next steps|putting it all together|conclusion|summary|background|configuration|setup|usage|features|concepts|details|examples|reference|resources)\z/i
    TECHNICAL_CONTRAST = /\b(?:
      apis?|sdks?|schemas?|typed|types?|validation|correctness|native|json|react|codeact|
      predict(?:ors?)?|signatures?|modules?|agents?|tools?|toolsets?|examples?|metrics?|
      evaluations?|optimizers?|traces?|permissions?|timeouts?|budgets?|providers?|models?|
      registr(?:y|ies)|applications?|task\s+boundar(?:y|ies)|failures?|errors?|inputs?|outputs?|
      deadlines?|subprocess(?:es)?|networks?|operations?|deployment\s+polic(?:y|ies)
    )\b/ix
    CONTRAST_EVIDENCE = /\b(?:because|whereas|while|when|requires?|uses?|handles?|owns?|supports?|within|only|versus|vs\.?|measured|evaluated)\b/i
    VARIATIONS = {
      /\bsignature\b/i => /\b(?:contract class|schema object)\b/i,
      /\bpredictor\b/i => /\b(?:generator object|inference engine)\b/i,
      /\bmodule\b/i => /\b(?:workflow component|orchestration object)\b/i,
      /\bmetric\b/i => /\b(?:scoring gadget|quality function object)\b/i,
      /\blanguage model\b/i => /\b(?:AI engine|intelligence backend)\b/i,
      /\btyped program\b/i => /\b(?:smart workflow|AI pipeline object)\b/i
    }.freeze

    def initialize(outcome: nil)
      @outcome = outcome.to_s
    end

    def scan(path, text)
      findings = []
      text.lines.each_with_index do |line, index|
        line_number = index + 1
        body = line.delete_suffix("\n").delete_suffix("\r")
        next if body.strip.empty?

        add(findings, path, line_number, "AI aphorism", "aphorism-portable-maxim",
            "portable maxim lacks a local mechanism or boundary") if ai_aphorism?(body)
        add(findings, path, line_number, "synthetic flourish", "flourish-stock-metaphor",
            "stock flourish carries no observable behavior") if synthetic_flourish?(body)
        add(findings, path, line_number, "chatbot cadence", "cadence-ready-dive",
            "question-and-invitation cadence delays the task") if chatbot_cadence?(body)
        add(findings, path, line_number, "empty contrast", "contrast-abstract-reversal",
            "contrast names no technical alternative or decision evidence") if empty_contrast?(body)
        add(findings, path, line_number, "tutorial patter", "patter-lesson-narration",
            "lesson narration does not advance the instruction") if tutorial_patter?(body)
        add(findings, path, line_number, "generic heading", "heading-no-task-value",
            "heading has no task value for the source's declared outcome") if generic_heading?(body)
        add(findings, path, line_number, "vague praise", "praise-stacked-unscoped",
            "quality claim stacks evaluative modifiers without a named dimension or evidence") if vague_praise?(body)
        add(findings, path, line_number, "throat-clearing", "preface-note-that",
            "preface postpones the claim") if throat_clearing?(body)
        add(findings, path, line_number, "narrating comments", "comment-repeats-visible-step",
            "comment narrates the adjacent material without a boundary or rationale") if narrating_comment?(body)
        add(findings, path, line_number, "elegant variation", "terminology-canonical-rotation",
            "nearby references rotate terminology for one canonical concept") if elegant_variation?(body)
      end
      findings
    end

    private

    def add(findings, path, line, category, rule_id, message)
      findings << Finding.new(path, line, category, rule_id, message)
    end

    def ai_aphorism?(line)
      return false if line.match?(CONTRAST_EVIDENCE)

      line.match?(/\b(?:AI|software|prompt engineering|the future)\b[^.!?]{0,100}\b(?:is (?:just|really|simply)|needs (?:its|a|an)|isn't about|is not about)\b/i)
    end

    def synthetic_flourish?(line)
      line.match?(/\b(?:where|when) (?:the )?(?:real )?magic happens\b|\b(?:the )?(?:journey|adventure) (?:begins|starts)\b|\bwelcome to (?:the future|a new era)\b/i)
    end

    def chatbot_cadence?(line)
      line.match?(/\bready to [^?]{1,80}\?\s*(?:let['’]s|we(?:'ll| will))\s+(?:dive|jump|explore|get started)\b/i)
    end

    def empty_contrast?(line)
      contrast = line.match?(/\bnot\s+[^,.;:]{1,50}[,;:]\s*(?:but\s+)?[^,.;:]{1,50}/i) ||
        line.match?(/\b(?:isn't|is not|aren't|are not)\s+[^.;:]{1,50}[.;:]\s*(?:it(?:'s| is)|they(?:'re| are)|but)\s+[^.;:]{1,50}/i)
      technical_terms = line.scan(TECHNICAL_CONTRAST).map { _1.downcase }.uniq
      contrast && technical_terms.length < 2 && !line.match?(CONTRAST_EVIDENCE)
    end

    def tutorial_patter?(line)
      line.match?(/\bnow that [^,]{1,100},\s*(?:let['’]s|we can)\b|\b(?:first|next|finally),?\s+(?:let['’]s|we(?:'ll| will))\b|\bin this (?:section|guide|tutorial),?\s+(?:we|you)(?:'ll| will| can)\b/i)
    end

    def generic_heading?(line)
      match = line.match(/\A {0,3}\#{1,6}\s+(.+?)\s*#*\s*\z/)
      return false unless match

      heading = match[1].gsub(/\{#[^}]+\}\z/, "").strip
      return false if heading_has_task_value?(heading) || heading_matches_outcome?(heading)

      heading.match?(GENERIC_HEADING)
    end

    def vague_praise?(line)
      return false if line.match?(/\b(?:because|by|through|when|for)\b/i)

      line.split(/[.!?]+/).any? do |sentence|
        evaluative_modifier_count(sentence) >= 2 && quality_claim_structure?(sentence)
      end
    end

    def heading_has_task_value?(heading)
      heading.match?(/\b(?:choose|configure|define|build|run|evaluate|measure|optimize|operate|extend|diagnose|debug|fix|migrate|compare|handle|prevent|verify|inspect|install|create|add|use|understand|learn|failure|error|timeout|boundary|decision|result)\b/i)
    end

    def heading_matches_outcome?(heading)
      return false if @outcome.empty?

      heading_terms = normalized_terms(heading)
      outcome_terms = normalized_terms(@outcome)
      !(heading_terms & outcome_terms).empty?
    end

    def normalized_terms(text)
      stop_words = %w[a an and for from how in of on or the to with]
      text.downcase.scan(/[\p{L}\p{N}]+/).filter_map do |term|
        next if stop_words.include?(term)

        term.sub(/(?:ations?|ing|ed|es|s)\z/, "")
      end
    end

    def evaluative_modifier_count(sentence)
      sentence.scan(/\b(?:automatic|powerful|flexible|seamless|intuitive|elegant|effortless|easy|simple|robust|production-ready)\b/i).length
    end

    def quality_claim_structure?(sentence)
      subject_predicate = sentence.match?(/\b(?:experience|framework|api|tool|library|solution|integration|workflow|system|approach)\b\s+(?:is|are)\b/i)
      predicate_object = sentence.match?(/\b(?:provides?|offers?|delivers?)\b.+\b(?:experience|framework|api|tool|library|solution|integration|workflow|system|approach)\b/i)
      stacked_subject = sentence.match?(/\A\s*(?:an?|the)\s+.+\b(?:experience|framework|api|tool|library|solution|integration|workflow|system|approach)\b/i)
      subject_predicate || predicate_object || stacked_subject
    end

    def throat_clearing?(line)
      line.match?(/\b(?:it is|it's) (?:(?:important|helpful|interesting) to (?:note|remember|understand|keep in mind)|worth (?:noting|remembering|understanding)) that\b|\bbefore we [^,]{1,80},\s*let['’]s take a moment\b/i)
    end

    def narrating_comment?(line)
      comment = line.match(/<!--\s*(.*?)\s*-->/)&.[](1)
      comment&.match?(/\A(?:this|the following|below|here) (?:section|example|code|snippet) (?:shows|demonstrates|explains|walks through)\b/i)
    end

    def elegant_variation?(line)
      VARIATIONS.any? { |canonical, variant| line.match?(canonical) && line.match?(variant) }
    end
  end

  class Runner
    def initialize(root:, stdout: $stdout, stderr: $stderr)
      @root = Pathname(root).expand_path
      @stdout = stdout
      @stderr = stderr
    end

    def run(arguments)
      options = {format: "text"}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby docs/scripts/audit_economical_writing.rb [--jsonl] [PATH ...]"
        opts.on("--jsonl", "Emit one JSON object per candidate") { options[:format] = "jsonl" }
        opts.on("--manifest PATH", "Use an alternate corpus manifest") { |path| options[:manifest] = path }
      end
      paths = parser.parse(arguments)
      corpus = Corpus.new(root: @root, manifest: options[:manifest])
      selected = paths.empty? ? corpus.default_paths : corpus.explicit_paths(paths)
      findings = []
      diagnostics = []

      selected.each do |path|
        result = scan_text(path, corpus.read(path), outcome: corpus.record(path).fetch("outcome", ""))
        findings.concat(result.fetch(:findings))
        diagnostics.concat(result.fetch(:diagnostics))
      end

      diagnostics.sort_by { [_1.path, _1.line, _1.rule_id] }.each { @stderr.puts(_1) }
      return 2 unless diagnostics.empty?

      findings.sort_by(&:sort_key).each do |finding|
        @stdout.puts(options[:format] == "jsonl" ? JSON.generate(finding.to_h) : finding)
      end
      0
    rescue OptionParser::ParseError, ArgumentError => error
      @stderr.puts("economical-writing audit failed: #{error.message}")
      2
    end

    def scan_text(path, text, outcome: nil)
      masked = Masker.new(path, text).call
      findings = Rules.new(outcome: outcome).scan(path, masked.text)
      {findings: findings, diagnostics: masked.diagnostics}
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = Pathname(__dir__).join("../..").expand_path
  exit EconomicalWritingAudit::Runner.new(root: root).run(ARGV)
end
