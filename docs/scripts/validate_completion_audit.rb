#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "open3"
require "optparse"
require "pathname"
require "set"
require "time"
require "yaml"

module DocumentationQuality
  class CompletionAudit
    TAXONOMY = %w[factual structural ordinary-copy voice].freeze
    STATUSES = %w[resolved retained blocked].freeze
    VERDICTS = %w[preserved retired blocked].freeze
    ACTIONS = %w[aligned-copy retained-distinction preserved-boundary redirect-notice].freeze
    REQUIRED_FOCUS = %w[
      docs/src/build/index.md
      docs/src/getting-started/packages.md
      docs/src/advanced/concurrent-predictions.md
      docs/src/advanced/module-lifecycle-callbacks.md
      docs/src/production/score-reporting.md
      docs/src/getting-started/first-program.md
      docs/src/getting-started/core-concepts.md
      docs/src/core-concepts/toolsets-guide.md
      docs/src/core-concepts/codeact.md
      docs/src/core-concepts/module-runtime-context.md
      lib/dspy/code_act/README.md
      docs/src/llms.txt.erb
      docs/src/llms-full.txt.erb
    ].freeze
    REQUIRED_HIGH_TRAFFIC = %w[
      README.md
      docs/src/index.md
      docs/src/getting-started/index.md
      docs/src/getting-started/installation.md
      docs/src/getting-started/packages.md
      docs/src/getting-started/quick-start.md
      docs/src/core-concepts/index.md
      docs/src/core-concepts/predictors.md
      docs/src/core-concepts/toolsets.md
      docs/src/build/index.md
      docs/src/advanced/index.md
      docs/src/optimization/index.md
      docs/src/production/index.md
      examples/README.md
      docs/src/blog/index.md
      docs/src/llms.txt.erb
      docs/src/llms-full.txt.erb
    ].freeze
    RECORDED_BLIND_SAMPLE = %w[
      docs/src/build/index.md
      docs/src/core-concepts/events.md
      docs/src/core-concepts/signatures.md
      docs/src/advanced/module-lifecycle-callbacks.md
      docs/src/advanced/complex-types.md
      docs/src/optimization/evaluation.md
      docs/src/production/registry.md
      examples/ade_optimizer_miprov2/README.md
      lib/dspy/ruby_llm/README.md
      docs/src/core-concepts/module-runtime-context.md
      docs/src/_articles/react-agent-tutorial.md
      docs/src/_articles/json-parsing-reliability.md
      docs/src/_articles/does-chain-of-thought-improve-summaries.md
      docs/src/production/index.md
      docs/src/getting-started/index.md
    ].freeze

    def initialize(root:, audit: nil)
      @root = Pathname(root).expand_path
      @audit_path = audit ? Pathname(audit).expand_path : @root.join("docs/editorial/completion-audit.yml")
    end

    def errors
      audit = load_yaml(@audit_path)
      corpus = load_yaml(@root.join("docs/editorial/public-doc-corpus.yml"))
      anchors = load_yaml(@root.join("docs/editorial/semantic-anchors.yml"))
      voice = load_yaml(@root.join("docs/editorial/house-voice-samples.yml"))
      failures = []
      failures << "completion audit version must be 1" unless audit["version"] == 1
      failures << "completion audit taxonomy must be exactly #{TAXONOMY.join(', ')}" unless audit["taxonomy"] == TAXONOMY

      sources = effective_public_sources(corpus, failures)
      validate_sources(audit, sources, failures)
      validate_findings(audit, sources, failures)
      validate_anchors(audit, anchors, failures)
      validate_duplicates(audit, anchors, failures)
      validate_exceptions(audit, voice, failures)
      validate_focus(audit, sources, failures)
      validate_aggregate_provenance(audit, corpus, failures)
      validate_blind_review(audit, sources, failures)
      failures
    rescue Psych::Exception, KeyError, TypeError => error
      ["completion audit could not be parsed: #{error.message}"]
    end

    private

    def load_yaml(path)
      YAML.safe_load_file(path, permitted_classes: [Date, Time], aliases: false)
    end

    def tracked_prose
      output, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", chdir: @root.to_s)
      raise "git ls-files failed" unless status.success?

      output.lines(chomp: true).select do |path|
        path.end_with?(".md") || path.match?(%r{(^|/)llms(?:-full)?\.txt\.erb\z})
      end
    end

    def matches?(record, path)
      patterns = [record["path"], record["glob"]].compact
      patterns.any? { File.fnmatch?(_1, path, File::FNM_EXTGLOB | File::FNM_PATHNAME) } &&
        !Array(record["except"]).include?(path)
    end

    def effective_public_sources(corpus, failures)
      rules = corpus.fetch("rules")
      tracked_prose.to_h do |path|
        matched = rules.select { matches?(_1, path) }
        failures << "#{path}: completion audit corpus match count is #{matched.length}" unless matched.length == 1
        effective = matched.first&.merge(matched.first.fetch("overrides", {}).fetch(path, {}))
        [path, effective]
      end.select { |_path, rule| rule && %w[public history].include?(rule["kind"]) }
    end

    def validate_sources(audit, sources, failures)
      rows = audit.fetch("source_audits")
      paths = rows.map { _1["path"] }
      failures << "source audit paths are duplicated" unless paths.uniq.length == paths.length
      missing = sources.keys - paths
      extra = paths - sources.keys
      failures << "source audits missing: #{missing.join(', ')}" unless missing.empty?
      failures << "source audits contain non-corpus paths: #{extra.join(', ')}" unless extra.empty?

      rows.each do |row|
        path = row.fetch("path")
        rule = sources[path]
        next unless rule

        failures << "#{path}: audit kind must be #{rule['kind']}" unless row["kind"] == rule["kind"]
        failures << "#{path}: all four taxonomy dimensions must be reviewed" unless row["dimensions"] == TAXONOMY
        expected_metadata = metadata_expected?(path) ? "reviewed" : "not-applicable"
        failures << "#{path}: metadata must be #{expected_metadata}" unless row["metadata"] == expected_metadata
        failures << "#{path}: finding_ids must be a list" unless row["finding_ids"].is_a?(Array)
      end
    end

    def metadata_expected?(path)
      text = @root.join(path).read(encoding: "UTF-8")
      return false unless text.start_with?("---\n")

      frontmatter = text[/\A---\n(.*?)\n---\n/m, 1]
      return false unless frontmatter

      data = YAML.safe_load(frontmatter, permitted_classes: [Date, Time], aliases: false) || {}
      %w[title description].any? { !data[_1].to_s.empty? }
    rescue Psych::Exception
      false
    end

    def validate_findings(audit, sources, failures)
      findings = audit.fetch("findings")
      ids = findings.map { _1["id"] }
      failures << "finding ids are duplicated" unless ids.uniq.length == ids.length
      by_id = findings.to_h { [_1.fetch("id"), _1] }

      audit.fetch("source_audits").each do |row|
        Array(row["finding_ids"]).each do |id|
          failures << "#{row['path']}: unknown finding #{id}" unless by_id.key?(id)
        end
      end

      findings.each do |finding|
        id = finding.fetch("id")
        failures << "#{id}: invalid category" unless TAXONOMY.include?(finding["category"])
        failures << "#{id}: invalid status" unless STATUSES.include?(finding["status"])
        failures << "#{id}: missing reason" if finding["reason"].to_s.strip.empty?
        failures << "#{id}: blocked finding needs owner" if finding["status"] == "blocked" && finding["owner"].to_s.strip.empty?
        verification = finding["verification"]
        unless verification.is_a?(Array) && !verification.empty?
          failures << "#{id}: needs action verification"
          next
        end
        verification.each do |check|
          path = @root.join(check.fetch("path"))
          unless path.file?
            failures << "#{id}: verification source missing: #{check['path']}"
            next
          end
          text = path.read(encoding: "UTF-8")
          failures << "#{id}: verification must specify present or absent text" if check["present"].to_s.empty? && check["absent"].to_s.empty?
          failures << "#{id}: expected text is absent from #{check['path']}" unless check["present"].to_s.empty? || text.include?(check["present"])
          failures << "#{id}: retired text remains in #{check['path']}" unless check["absent"].to_s.empty? || !text.include?(check["absent"])
        end
      end

      category_rows = audit.fetch("category_results")
      categories = category_rows.map { _1["category"] }
      failures << "category results must cover the four finding categories exactly" unless categories.sort == TAXONOMY.sort && categories.uniq.length == TAXONOMY.length
      category_rows.each do |row|
        expected = findings.select { _1["category"] == row["category"] }.map { _1["id"] }.sort
        actual = Array(row["finding_ids"]).sort
        failures << "#{row['category']}: category finding ids do not match findings" unless actual == expected
      end

      referenced = audit.fetch("source_audits").flat_map { Array(_1["finding_ids"]) }.uniq
      corpus_findings = findings.select do |finding|
        finding.fetch("verification").any? { sources.key?(_1["path"]) }
      end.map { _1["id"] }
      missing_references = corpus_findings - referenced
      failures << "corpus findings are not attached to source audits: #{missing_references.join(', ')}" unless missing_references.empty?
    end

    def validate_anchors(audit, ledger, failures)
      expected = ledger.fetch("anchors").to_h { [_1.fetch("id"), _1] }
      rows = audit.fetch("anchor_audits")
      ids = rows.map { _1["id"] }
      failures << "anchor audit ids are duplicated" unless ids.uniq.length == ids.length
      failures << "anchor audits must disposition every semantic anchor" unless ids.sort == expected.keys.sort

      rows.each do |row|
        id = row.fetch("id")
        anchor = expected[id]
        next unless anchor
        verdict = row["verdict"]
        failures << "#{id}: invalid audit verdict" unless VERDICTS.include?(verdict)
        failures << "#{id}: missing verdict reason" if row["reason"].to_s.strip.empty?
        if verdict == "preserved"
          destination = anchor.fetch("canonical_destination")
          failures << "#{id}: preserved path does not match canonical destination" unless row["path"] == destination["path"]
          failures << "#{id}: preserved locator does not match canonical destination" unless row["locator"] == destination["locator"]
          failures << "#{id}: preserved locator is absent" unless contains?(row["path"], row["locator"])
        elsif verdict == "retired"
          failures << "#{id}: retired verdict requires retired ledger lifecycle" unless anchor["lifecycle"] == "retired"
        elsif row["owner"].to_s.strip.empty?
          failures << "#{id}: blocked anchor needs owner"
        end
      end
    end

    def validate_duplicates(audit, ledger, failures)
      expected = ledger.fetch("anchors").flat_map do |anchor|
        Array(anchor["duplicates"]).map { |duplicate| [[anchor.fetch("id"), duplicate.fetch("path")], duplicate] }
      end.to_h
      rows = audit.fetch("duplicate_decisions")
      identities = rows.map { [_1["anchor"], _1["source"]] }
      failures << "duplicate decision rows are duplicated" unless identities.uniq.length == identities.length
      failures << "duplicate decisions must cover every ledger duplicate" unless identities.sort == expected.keys.sort

      rows.each do |row|
        identity = [row["anchor"], row["source"]]
        duplicate = expected[identity]
        next unless duplicate
        failures << "#{identity.join('/')}: duplicate disposition drifted" unless row["disposition"] == duplicate["disposition"]
        failures << "#{identity.join('/')}: duplicate distinction is missing" if row["distinction"].to_s.strip.empty?
        failures << "#{identity.join('/')}: invalid action verification" unless ACTIONS.include?(row["action_verification"])
        failures << "#{identity.join('/')}: action locator is absent" unless contains?(duplicate["path"], duplicate["locator"])
      end
    end

    def validate_exceptions(audit, voice, failures)
      samples = voice.fetch("samples").select { _1["requires_exception"] }.to_h { [_1.fetch("id"), _1] }
      rows = audit.fetch("rhetorical_exceptions")
      ids = rows.map { _1["sample_id"] }
      failures << "rhetorical exceptions must cover every required sample" unless ids.sort == samples.keys.sort && ids.uniq.length == ids.length
      rows.each do |row|
        sample = samples[row["sample_id"]]
        next unless sample
        exception = sample.fetch("exception")
        %w[evidence evidence_locator scope editor reviewed_on].each do |field|
          failures << "#{row['sample_id']}: exception #{field} is missing or drifted" unless row[field].to_s == exception[field].to_s && !row[field].to_s.strip.empty?
        end
        failures << "#{row['sample_id']}: exception action must verify the excerpt" unless row["action_verification"] == "excerpt-present"
        failures << "#{row['sample_id']}: approved rhetorical excerpt is absent" unless contains?(sample["source"], sample["excerpt"])
      end
    end

    def validate_focus(audit, sources, failures)
      rows = audit.fetch("focus_sources")
      paths = rows.map { _1["path"] }
      missing = REQUIRED_FOCUS - paths
      failures << "completion focus omits new, moved, or llms sources: #{missing.join(', ')}" unless missing.empty?
      rows.each do |row|
        failures << "#{row['path']}: focus reason is missing" if row["reason"].to_s.strip.empty?
        failures << "#{row['path']}: focus source is not in the public/history corpus" unless sources.key?(row["path"])
      end
    end

    def validate_aggregate_provenance(audit, corpus, failures)
      record = audit.fetch("aggregate_provenance")
      failures << "llms aggregate provenance must remain planned" unless record["status"] == "planned"
      failures << "llms aggregate templates must include both ERB sources" unless Array(record["templates"]).sort == %w[docs/src/llms-full.txt.erb docs/src/llms.txt.erb]
      failures << "llms aggregate conclusion is missing" if record["conclusion"].to_s.strip.empty?
      rules = corpus.fetch("rules").select { %w[docs/src/llms.txt.erb docs/src/llms-full.txt.erb].include?(_1["path"]) }
      failures << "both llms corpus rules must declare planned derivation" unless rules.length == 2 && rules.all? { _1["derivation_status"] == "planned" }
    end

    def validate_blind_review(audit, sources, failures)
      review = audit.fetch("blind_review")
      denominator = sources.length
      minimum = (denominator * 0.15).ceil
      sample = Array(review["sample"])
      high_traffic = Array(review["high_traffic"])
      failures << "blind editor must be Mina Shaw" unless review["editor"] == "Mina Shaw"
      failures << "blind editor role must be blind_corpus_editor" unless review["role"] == "blind_corpus_editor"
      failures << "blind review must record SHA-256 normalized-path ranking" unless review["sample_method"].to_s.include?("SHA-256 normalized-path ranking")
      failures << "blind review denominator must be #{denominator}" unless review["denominator"] == denominator
      failures << "blind review minimum percent must be 15" unless review["minimum_percent"] == 15
      failures << "blind review minimum sample must be #{minimum}" unless review["minimum_sample"] == minimum
      failures << "blind sample paths must be distinct" unless sample.uniq.length == sample.length
      failures << "blind sample must match Mina Shaw's recorded deterministic sample" unless sample == RECORDED_BLIND_SAMPLE
      failures << "blind sample is below 15 percent" if sample.length < minimum
      failures << "blind sample contains a non-corpus source" unless sample.all? { sources.key?(_1) }
      failures << "high-traffic review must include all required entry points" unless (REQUIRED_HIGH_TRAFFIC - high_traffic).empty?
      failures << "high-traffic paths must be distinct corpus sources" unless high_traffic.uniq.length == high_traffic.length && high_traffic.all? { sources.key?(_1) }
      overlap = (sample & high_traffic).length
      total = (sample | high_traffic).length
      failures << "blind review overlap count must be #{overlap}" unless review["overlap_count"] == overlap
      failures << "blind review distinct total must be #{total}" unless review["total_distinct_reviewed"] == total
    end

    def contains?(path, locator)
      file = @root.join(path.to_s)
      file.file? && file.read(encoding: "UTF-8").include?(locator.to_s)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = Pathname(__dir__).join("../..").expand_path
  audit = nil
  OptionParser.new do |options|
    options.on("--root PATH") { root = Pathname(_1).expand_path }
    options.on("--audit PATH") { audit = Pathname(_1).expand_path }
  end.parse!
  errors = DocumentationQuality::CompletionAudit.new(root: root, audit: audit).errors
  abort(errors.map { "ERROR: #{_1}" }.join("\n")) unless errors.empty?
  puts "Completion audit valid: 99 public/history sources, 17 anchors, 16 duplicate decisions, 2 rhetorical exceptions, and a 15-source blind sample plus high-traffic entry points."
end
