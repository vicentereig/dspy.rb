# frozen_string_literal: true

require "pathname"

module DocumentationQuality
  class LegacyPackageEvidence
    FIELDS = %w[
      name replacement disposition evidence_commit evidence_subject
      former_gemspec former_locator replacement_gemspec replacement_locator
    ].freeze
    EXPECTED_ATTESTATIONS = [
      {
        "name" => "dspy-deepsearch",
        "replacement" => "dspy-deep_search",
        "disposition" => "retired-name",
        "evidence_commit" => "8702acb800a6ddf75bbcddbec3dc6af318b30edf",
        "evidence_subject" => "Rename gemspecs to deep_search and deep_research",
        "former_gemspec" => "dspy-deepsearch.gemspec",
        "former_locator" => 'spec.name          = "dspy-deepsearch"',
        "replacement_gemspec" => "dspy-deep_search.gemspec",
        "replacement_locator" => 'spec.name          = "dspy-deep_search"'
      },
      {
        "name" => "dspy-deepresearch",
        "replacement" => "dspy-deep_research",
        "disposition" => "retired-name",
        "evidence_commit" => "8702acb800a6ddf75bbcddbec3dc6af318b30edf",
        "evidence_subject" => "Rename gemspecs to deep_search and deep_research",
        "former_gemspec" => "dspy-deepresearch.gemspec",
        "former_locator" => 'spec.name          = "dspy-deepresearch"',
        "replacement_gemspec" => "dspy-deep_research.gemspec",
        "replacement_locator" => 'spec.name          = "dspy-deep_research"'
      }
    ].map(&:freeze).freeze

    def initialize(root:, entries:)
      @root = Pathname(root).expand_path
      @entries = entries
    end

    def errors
      validate_attestations + EXPECTED_ATTESTATIONS.flat_map { validate_current_tree(_1) }
    end

    private

    def validate_attestations
      failures = []
      names = @entries.map { _1["name"] }
      names.tally.each do |name, count|
        failures << "legacy evidence record is duplicated: #{name}" if count > 1
      end

      expected_names = EXPECTED_ATTESTATIONS.map { _1.fetch("name") }
      (expected_names - names).each { failures << "legacy evidence record is missing: #{_1}" }
      (names - expected_names).uniq.each { failures << "legacy evidence record is unexpected: #{_1.inspect}" }

      EXPECTED_ATTESTATIONS.each do |expected|
        actual = @entries.find { _1["name"] == expected.fetch("name") }
        next unless actual

        unknown_fields = actual.keys - FIELDS
        unless unknown_fields.empty?
          failures << "#{expected.fetch('name')}: legacy evidence record has unknown fields #{unknown_fields.sort.inspect}"
        end
        FIELDS.each do |field|
          next if actual[field] == expected.fetch(field)

          failures << "#{expected.fetch('name')}: legacy evidence #{field} differs: #{actual[field].inspect}"
        end
      end
      failures
    end

    def validate_current_tree(attestation)
      label = attestation.fetch("name")
      failures = []
      former = @root.join(attestation.fetch("former_gemspec"))
      replacement = @root.join(attestation.fetch("replacement_gemspec"))
      failures << "#{label}: retired gemspec still exists: #{relative(former)}" if former.exist?
      unless replacement.file?
        failures << "#{label}: replacement gemspec is missing: #{relative(replacement)}"
        return failures
      end

      count = read_utf8(replacement).scan(attestation.fetch("replacement_locator")).length
      unless count == 1
        failures << "#{label}: replacement locator must occur exactly once in #{relative(replacement)}, got #{count}"
      end
      failures
    end

    def read_utf8(path)
      File.binread(path).force_encoding(Encoding::UTF_8).scrub
    end

    def relative(path)
      path.relative_path_from(@root).to_s
    end
  end
end
