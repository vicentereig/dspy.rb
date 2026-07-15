# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "yaml"
require_relative "../../docs/scripts/audit_economical_writing"

RSpec.describe EconomicalWritingAudit do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:fixtures_path) { root.join("docs/editorial/economical-writing-fixtures.yml") }
  let(:fixture_document) { YAML.safe_load_file(fixtures_path, aliases: false) }
  let(:fixtures) { fixture_document.fetch("samples") }
  let(:review_gate_dry_runs) { fixture_document.fetch("review_gate_dry_runs") }
  let(:runner) { described_class::Runner.new(root: root) }

  def scan(text, path: "sample.md", outcome: nil)
    runner.scan_text(path, text, outcome: outcome)
  end

  def write_manifest(root, rules)
    FileUtils.mkdir_p(root.join("docs/editorial"))
    File.write(root.join("docs/editorial/public-doc-corpus.yml"), {"version" => 1, "rules" => rules}.to_yaml)
  end

  def write_file(root, relative, content)
    path = root.join(relative)
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, content)
  end

  it "calibrates every category against shared independently adjudicated fixtures" do
    expected_categories = described_class::Rules::CATEGORIES.sort
    positive_categories = fixtures.select { _1.fetch("case") == "positive" }
                                  .flat_map { _1.fetch("expected_categories") }.uniq.sort

    expect(positive_categories).to eq(expected_categories)
    fixtures.each do |sample|
      outcome = sample.fetch("outcome", fixture_document.fetch("default_outcome"))
      result = scan(sample.fetch("excerpt"), path: "#{sample.fetch('id')}.md", outcome: outcome)
      categories = result.fetch(:findings).map(&:category).uniq.sort
      expect(result.fetch(:diagnostics)).to be_empty, sample.fetch("id")
      expect(categories).to eq(sample.fetch("expected_categories").sort), sample.fetch("id")
      expect(%w[reviewer_a reviewer_b final].map { sample.fetch(_1) })
        .to all(satisfy { |verdict| ["KEEP technical", "KEEP voice", "EDIT", "DELETE"].include?(verdict) })
      if sample["expected_lines"]
        expect(result.fetch(:findings).map(&:line).uniq).to eq(sample.fetch("expected_lines")), sample.fetch("id")
      end
    end
  end

  it "keeps automatic, simple, and robust from acting as blacklist words" do
    %w[automatic simple robust].each do |word|
      expect(scan("#{word.capitalize}.\n").fetch(:findings)).to be_empty
    end
  end

  it "dry-runs representative review-gate files without turning candidates into failures" do
    Dir.mktmpdir("economy-review-gate") do |directory|
      temp_root = Pathname(directory)
      rules = review_gate_dry_runs.map do |sample|
        {"id" => sample.fetch("id"), "kind" => "public", "path" => sample.fetch("path")}
      end
      write_manifest(temp_root, rules)
      review_gate_dry_runs.each do |sample|
        write_file(temp_root, sample.fetch("path"), "#{sample.fetch('excerpt')}\n")
      end

      stdout = StringIO.new
      stderr = StringIO.new
      status = described_class::Runner.new(root: temp_root, stdout: stdout, stderr: stderr)
                              .run(["--jsonl", *review_gate_dry_runs.map { _1.fetch("path") }])
      findings = stdout.string.lines.map { JSON.parse(_1, symbolize_names: true) }

      expect(status).to eq(0)
      expect(stderr.string).to be_empty
      review_gate_dry_runs.each do |sample|
        categories = findings.select { _1.fetch(:path) == sample.fetch("path") }.map { _1.fetch(:category) }
        expect(categories).to eq(sample.fetch("expected_categories")), sample.fetch("id")
      end
    end
  end

  it "distinguishes technical contrasts from abstract reversal" do
    technical = "Native structured output validates a schema, while prompt-based JSON requires application parsing."
    abstract = "The goal is not avoiding mistakes; it is embracing excellence."

    expect(scan(technical).fetch(:findings).map(&:category)).not_to include("empty contrast")
    expect(scan(abstract).fetch(:findings).map(&:category)).to include("empty contrast")
  end

  it "protects scoped automatic behavior and the ReAct-versus-CodeAct mechanism contrast" do
    scoped = fixtures.fetch(fixtures.index { _1.fetch("id") == "protected-scoped-automatic" })
    react_codeact = fixtures.fetch(fixtures.index { _1.fetch("id") == "protected-react-codeact-contrast" })
    unscoped = fixtures.fetch(fixtures.index { _1.fetch("id") == "qualifier-does-not-whitelist-empty-contrast" })

    expect(scan(scoped.fetch("excerpt")).fetch(:findings)).to be_empty
    expect(scan(react_codeact.fetch("excerpt")).fetch(:findings)).to be_empty
    expect(scan(unscoped.fetch("excerpt")).fetch(:findings).map(&:category)).to include("empty contrast")
  end

  it "judges the same short heading against the source outcome" do
    aligned = fixtures.find { _1.fetch("id") == "generic-heading-outcome-aligned" }
    taskless = fixtures.find { _1.fetch("id") == "generic-heading-taskless-outcome" }

    expect(scan(aligned.fetch("excerpt"), outcome: aligned.fetch("outcome")).fetch(:findings)).to be_empty
    findings = scan(taskless.fetch("excerpt"), outcome: taskless.fetch("outcome")).fetch(:findings)
    expect(findings.map(&:category)).to eq(["generic heading"])
  end

  it "passes effective manifest outcomes through default and explicit path modes" do
    Dir.mktmpdir("economy-outcomes") do |directory|
      temp_root = Pathname(directory)
      rules = [
        {"id" => "aligned", "kind" => "public", "path" => "aligned.md",
         "outcome" => "Review provider configuration requirements."},
        {"id" => "taskless", "kind" => "public", "path" => "taskless.md",
         "outcome" => "Read the documentation page."}
      ]
      write_manifest(temp_root, rules)
      rules.each { write_file(temp_root, _1.fetch("path"), "## Configuration\n") }

      [[], %w[taskless.md aligned.md]].each do |arguments|
        stdout = StringIO.new
        status = described_class::Runner.new(root: temp_root, stdout: stdout, stderr: StringIO.new).run(arguments)
        expect(status).to eq(0)
        expect(stdout.string.lines.map { _1.split(":", 2).first }).to eq(["taskless.md"])
      end
    end
  end

  it "requires a subject and stacked unsupported modifiers for vague praise" do
    bare = fixtures.find { _1.fetch("id") == "false-positive-qualifiers-alone" }
    stacked = fixtures.find { _1.fetch("id") == "stacked-qualifiers-form-a-claim" }
    scoped = fixtures.find { _1.fetch("id") == "scoped-stacked-qualifiers" }

    expect(scan(bare.fetch("excerpt")).fetch(:findings)).to be_empty
    expect(scan(stacked.fetch("excerpt")).fetch(:findings).map(&:category)).to eq(["vague praise"])
    expect(scan(scoped.fetch("excerpt")).fetch(:findings)).to be_empty
  end

  it "selects the repository corpus without derived references or editorial internals" do
    paths = described_class::Corpus.new(root: root).default_paths

    expect(paths).to include("README.md", "CHANGELOG.md", "docs/src/_articles/codeact-research-agent.md")
    expect(paths).not_to include("docs/src/llms.txt.erb", "docs/src/llms-full.txt.erb")
    expect(paths.grep(%r{\Adocs/editorial/})).to be_empty
    expect(paths.grep(%r{(?:docs/plans|todos)/})).to be_empty
  end

  it "preserves UTF-8, emoji, CJK, CRLF, and physical line numbers" do
    text = "境界 🧪\r\nPrompt engineering is simply modern programming.\r\n次の行\r\n"
    result = scan(text)

    expect(result.fetch(:diagnostics)).to be_empty
    expect(result.fetch(:findings).map { [_1.line, _1.category] }).to eq([[2, "AI aphorism"]])
  end

  it "masks code, quotes, frontmatter, destinations, autolinks, and raw URLs while retaining labels" do
    text = <<~MARKDOWN
      ---
      description: "where the magic happens"
      ---
      [## Diagnose Timeout Failures](https://example.test/where-the-magic-happens)
      <https://example.test/the-journey-begins>
      https://example.test/ready-to-dive
      > Ready to begin? Let's dive in.
          Prompt engineering is simply modern programming.
      ````ruby
      puts "where the magic happens"
      ````
      ~~~~~text
      Ready to begin? Let's dive in.
      ~~~~~
      Literal ``Prompt engineering is simply
      modern programming.`` remains code.
    MARKDOWN

    expect(scan(text).fetch(:findings)).to be_empty
  end

  it "masks only explicitly marked blockquote lines and scans ordinary prose immediately after them" do
    text = "> Prompt engineering is simply modern programming.\nPrompt engineering is simply modern programming.\n"
    result = scan(text)

    expect(result.fetch(:findings).map { [_1.line, _1.category] }).to eq([[2, "AI aphorism"]])
  end

  it "diagnoses unterminated masked regions and suppresses their remainder" do
    cases = {
      "---\ndescription: where the magic happens\n" => "frontmatter-unterminated",
      "Text\n~~~~\nwhere the magic happens\n" => "fence-unterminated",
      "Text `where the magic happens\nPrompt engineering is simply modern programming.\n" => "inline-code-unterminated"
    }

    cases.each do |text, rule_id|
      result = scan(text)
      expect(result.fetch(:findings)).to be_empty
      expect(result.fetch(:diagnostics).map(&:rule_id)).to eq([rule_id])
    end

    before_error = scan("where the magic happens\n~~~~\nPrompt engineering is simply modern programming.\n")
    expect(before_error.fetch(:findings).map(&:line)).to eq([1])
    expect(before_error.fetch(:diagnostics).map(&:rule_id)).to eq(["fence-unterminated"])
  end

  it "derives default public and history files from the manifest and omits excluded and derived sources" do
    Dir.mktmpdir("economy-corpus") do |directory|
      temp_root = Pathname(directory)
      rules = [
        {"id" => "public", "kind" => "public", "path" => "public.md"},
        {"id" => "history", "kind" => "history", "path" => "history.md"},
        {"id" => "derived", "kind" => "public", "path" => "derived.md", "owner_type" => "derived"},
        {"id" => "excluded", "kind" => "excluded", "path" => "excluded.md"}
      ]
      write_manifest(temp_root, rules)
      rules.each { |rule| write_file(temp_root, rule.fetch("path"), "where the magic happens\n") }
      stdout = StringIO.new
      status = described_class::Runner.new(root: temp_root, stdout: stdout, stderr: StringIO.new).run([])

      expect(status).to eq(0)
      expect(stdout.string.lines.map { _1.split(":", 2).first }).to eq(%w[history.md public.md])
    end
  end

  it "does not let explicit path mode bypass excluded or derived classification" do
    Dir.mktmpdir("economy-refusal") do |directory|
      temp_root = Pathname(directory)
      rules = [
        {"id" => "derived", "kind" => "public", "path" => "derived.md", "owner_type" => "derived"},
        {"id" => "excluded", "kind" => "excluded", "path" => "excluded.md"}
      ]
      write_manifest(temp_root, rules)
      rules.each { |rule| write_file(temp_root, rule.fetch("path"), "where the magic happens\n") }

      rules.each do |rule|
        stderr = StringIO.new
        status = described_class::Runner.new(root: temp_root, stdout: StringIO.new, stderr: stderr)
                                .run([rule.fetch("path")])
        expect(status).to eq(2)
        expect(stderr.string).to match(/excluded|derived\/generated/)
      end
    end
  end

  it "sorts text and JSONL output by path, numeric line, category, and rule" do
    Dir.mktmpdir("economy-order") do |directory|
      temp_root = Pathname(directory)
      write_manifest(temp_root, [
        {"id" => "docs", "kind" => "history", "glob" => "*.md"}
      ])
      write_file(temp_root, "b.md", "line\n\n\n\n\n\n\n\n\nwhere the magic happens\n")
      write_file(temp_root, "a.md", "Prompt engineering is simply modern programming.\nReady to inspect? Let's dive in where the magic happens.\n")

      text_out = StringIO.new
      text_status = described_class::Runner.new(root: temp_root, stdout: text_out, stderr: StringIO.new)
                                   .run(%w[b.md a.md])
      expect(text_status).to eq(0)
      expect(text_out.string.lines.map { _1.split(":", 3).first(2) }).to eq([
        ["a.md", "1"], ["a.md", "2"], ["a.md", "2"], ["b.md", "10"]
      ])
      expect(text_out.string.lines[1, 2].map { _1.split(": ", 3)[1] }).to eq(["chatbot cadence", "synthetic flourish"])

      json_out = StringIO.new
      json_status = described_class::Runner.new(root: temp_root, stdout: json_out, stderr: StringIO.new)
                                   .run(%w[--jsonl b.md a.md])
      records = json_out.string.lines.map { JSON.parse(_1) }
      expect(json_status).to eq(0)
      expect(records.map { [_1.fetch("path"), _1.fetch("line")] }).to eq([
        ["a.md", 1], ["a.md", 2], ["a.md", 2], ["b.md", 10]
      ])
      expect(records.first.keys).to eq(%w[path line category rule_id message])
    end
  end

  it "returns zero for candidates and leaves every input byte unchanged" do
    Dir.mktmpdir("economy-read-only") do |directory|
      temp_root = Pathname(directory)
      write_manifest(temp_root, [{"id" => "public", "kind" => "public", "path" => "public.md"}])
      source = temp_root.join("public.md")
      write_file(temp_root, "public.md", "Prompt engineering is simply modern programming.\r\n")
      before = Digest::SHA256.file(source).hexdigest

      status = described_class::Runner.new(root: temp_root, stdout: StringIO.new, stderr: StringIO.new)
                              .run(["public.md"])

      expect(status).to eq(0)
      expect(Digest::SHA256.file(source).hexdigest).to eq(before)
    end
  end

  it "returns nonzero only for invocation, configuration, read, or parse failures" do
    Dir.mktmpdir("economy-failures") do |directory|
      temp_root = Pathname(directory)
      write_file(temp_root, "bad.yml", "rules: [\n")
      stderr = StringIO.new
      status = described_class::Runner.new(root: temp_root, stdout: StringIO.new, stderr: stderr)
                              .run(%w[--manifest bad.yml])
      expect(status).to eq(2)
      expect(stderr.string).to include("cannot load corpus manifest")
    end

    Dir.mktmpdir("economy-invalid-utf8") do |directory|
      temp_root = Pathname(directory)
      write_manifest(temp_root, [{"id" => "public", "kind" => "public", "path" => "public.md"}])
      write_file(temp_root, "public.md", "\xFF".b)
      stderr = StringIO.new
      status = described_class::Runner.new(root: temp_root, stdout: StringIO.new, stderr: stderr).run(["public.md"])
      expect(status).to eq(2)
      expect(stderr.string).to include("not valid UTF-8")
    end

    %w[--rewrite --fail-on-match].each do |unsupported|
      expect(described_class::Runner.new(root: root, stdout: StringIO.new, stderr: StringIO.new).run([unsupported])).to eq(2)
    end
  end

  it "uses structural mutations rather than embedding fixture excerpts as exact triggers" do
    script = root.join("docs/scripts/audit_economical_writing.rb").read(encoding: "UTF-8")
    positive_excerpts = fixtures.select { _1.fetch("case") == "positive" }.map { _1.fetch("excerpt") }
    expect(positive_excerpts).to all(satisfy { |excerpt| !script.include?(excerpt) })

    mutations = {
      "AI needs a database moment." => "AI aphorism",
      "Attach the adapter; this is when the magic happens." => "synthetic flourish",
      "Ready to inspect traces? We'll explore them." => "chatbot cadence",
      "This is not about status; it is about momentum." => "empty contrast",
      "Finally, we'll inspect the result." => "tutorial patter",
      "## Overview" => "generic heading",
      "A robust, intuitive, elegant experience." => "vague praise",
      "It's worth remembering that scores are scoped." => "throat-clearing",
      "<!-- The following section explains tracing. -->" => "narrating comments",
      "The predictor runs once. The inference engine returns the value." => "elegant variation"
    }
    mutations.each do |text, category|
      expect(scan(text).fetch(:findings).map(&:category)).to include(category), text
    end
  end
end
