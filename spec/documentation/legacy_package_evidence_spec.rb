# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../../docs/scripts/validate_legacy_package_evidence"

RSpec.describe DocumentationQuality::LegacyPackageEvidence do
  def git!(*arguments, chdir:)
    output, error, status = Open3.capture3("git", *arguments, chdir: chdir.to_s)
    raise "git #{arguments.join(' ')} failed: #{error}" unless status.success?

    output.chomp
  end

  def write(path, content)
    FileUtils.mkdir_p(path.dirname)
    path.write(content, encoding: "UTF-8")
  end

  def ledger
    YAML.safe_load_file(evidence_root.join("docs/src/_data/package_capabilities.yml")).fetch("legacy_names")
  end

  def evidence_root
    Pathname(__dir__).join("../..").expand_path
  end

  def commit_all(root, message)
    git!("add", "-A", chdir: root)
    git!("commit", "--quiet", "-m", message, chdir: root)
  end

  def current_tree_fixture
    Dir.mktmpdir("legacy-evidence-tree") do |directory|
      root = Pathname(directory)
      described_class::EXPECTED_ATTESTATIONS.each do |attestation|
        write(root.join(attestation.fetch("replacement_gemspec")), "#{attestation.fetch('replacement_locator')}\n")
      end
      yield root
    end
  end

  def copied_repository_fixture
    Dir.mktmpdir("legacy-evidence-repository") do |directory|
      copy = Pathname(directory).join("source")
      paths = git!("ls-files", "-z", chdir: evidence_root).split("\0")
      paths << "docs/scripts/validate_legacy_package_evidence.rb"
      paths.reject { _1.empty? || _1.start_with?("docs/node_modules/") }.uniq.each do |relative|
        source = evidence_root.join(relative)
        next unless source.file? || source.symlink?

        destination = copy.join(relative)
        FileUtils.mkdir_p(destination.dirname)
        source.symlink? ? FileUtils.ln_s(File.readlink(source), destination) : FileUtils.cp(source, destination)
      end
      yield copy
    end
  end

  def run_real_validator(root)
    Open3.capture2e(
      RbConfig.ruby,
      root.join("docs/scripts/validate_package_capabilities.rb").to_s,
      "--source-only",
      chdir: root.to_s
    )
  end

  it "verifies the exact attestations and current replacement tree" do
    expect(described_class.new(root: evidence_root, entries: ledger).errors).to be_empty
  end

  it "runs the real validator without Git history and in a genuine depth-one checkout" do
    copied_repository_fixture do |source|
      expect(source.join(".git")).not_to exist
      output, status = run_real_validator(source)
      expect(status).to be_success, output

      git!("init", "--quiet", chdir: source)
      git!("config", "user.name", "Documentation Test", chdir: source)
      git!("config", "user.email", "docs@example.test", chdir: source)
      commit_all(source, "Import current source")
      write(source.join("shallow-marker.txt"), "Later work\n")
      commit_all(source, "Add later work")

      Dir.mktmpdir("legacy-evidence-clone") do |clone_directory|
        clone = Pathname(clone_directory).join("checkout")
        git!("clone", "--quiet", "--depth=1", "file://#{source}", clone.to_s, chdir: clone.dirname)
        expect(git!("rev-parse", "--is-shallow-repository", chdir: clone)).to eq("true")
        commit = "8702acb800a6ddf75bbcddbec3dc6af318b30edf^{commit}"
        expect { git!("cat-file", "-e", commit, chdir: clone) }.to raise_error(RuntimeError)
        output, status = run_real_validator(clone)
        expect(status).to be_success, output
      end
    end
  end

  it "does not branch on Git history or shallow-checkout state" do
    paths = %w[
      docs/scripts/validate_legacy_package_evidence.rb
      docs/scripts/validate_package_capabilities.rb
    ]
    source = paths.map { evidence_root.join(_1).read(encoding: "UTF-8") }.join("\n")
    expect(source).not_to include("cat-file", "is-shallow-repository", "Open3", ".git")
  end

  it "rejects mutations to every attested identity and rename field" do
    mutations = {
      "evidence_commit" => "0" * 40,
      "evidence_subject" => "Invented rename",
      "replacement" => "invented-replacement",
      "disposition" => "unknown",
      "former_gemspec" => "invented-old.gemspec",
      "former_locator" => "invented old locator",
      "replacement_gemspec" => "invented-new.gemspec",
      "replacement_locator" => "invented new locator"
    }
    mutations.each do |field, value|
      changed = ledger.map(&:dup)
      changed.first[field] = value
      errors = described_class.new(root: evidence_root, entries: changed).errors.join("\n")
      expect(errors).to include("legacy evidence #{field} differs")
    end

    changed = ledger.map(&:dup)
    changed.first["name"] = "invented-legacy"
    errors = described_class.new(root: evidence_root, entries: changed).errors.join("\n")
    expect(errors).to include("legacy evidence record is missing: dspy-deepsearch")
    expect(errors).to include('legacy evidence record is unexpected: "invented-legacy"')
  end

  it "rejects missing, duplicate, and extended evidence records" do
    errors = described_class.new(root: evidence_root, entries: ledger.take(1)).errors.join("\n")
    expect(errors).to include("legacy evidence record is missing: dspy-deepresearch")

    errors = described_class.new(root: evidence_root, entries: ledger + [ledger.first]).errors.join("\n")
    expect(errors).to include("legacy evidence record is duplicated: dspy-deepsearch")

    errors = described_class.new(root: evidence_root, entries: ledger + [{}]).errors.join("\n")
    expect(errors).to include("legacy evidence record is unexpected: nil")

    changed = ledger.map(&:dup)
    changed.first["unreviewed_claim"] = "invented"
    errors = described_class.new(root: evidence_root, entries: changed).errors.join("\n")
    expect(errors).to include("legacy evidence record has unknown fields")
  end

  it "rejects current-tree drift independently of the ledger" do
    current_tree_fixture do |root|
      replacement = root.join("dspy-deep_search.gemspec")
      replacement.write("wrong package\n", encoding: "UTF-8")
      errors = described_class.new(root: root, entries: ledger).errors.join("\n")
      expect(errors).to include("replacement locator must occur exactly once")

      write(root.join("dspy-deepresearch.gemspec"), "retired package returned\n")
      errors = described_class.new(root: root, entries: ledger).errors.join("\n")
      expect(errors).to include("retired gemspec still exists")
    end
  end
end
