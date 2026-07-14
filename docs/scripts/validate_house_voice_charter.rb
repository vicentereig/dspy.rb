#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "date"

ROOT = File.expand_path("../..", __dir__)
SAMPLES_PATH = File.join(ROOT, "docs/editorial/house-voice-samples.yml")
REQUIRED_EDGES = %w[true-automatic playful-headline caveat-overload stale-brand-claim].freeze
REQUIRED_VERDICTS = ["KEEP technical", "KEEP voice", "EDIT", "DELETE"].freeze
VALID_STATUSES = %w[present resolved retired].freeze
EXCEPTION_FIELDS = %w[audience evidence evidence_locator scope editor reviewed_on re_review approval].freeze

document = YAML.load_file(SAMPLES_PATH)
samples = document.fetch("samples")
declared_verdicts = document.fetch("verdicts")
errors = []

active_samples = samples.reject { |sample| sample["status"] == "retired" }
errors << "expected at least ten active calibration samples" if active_samples.length < 10
errors << "verdict vocabulary changed" unless declared_verdicts == REQUIRED_VERDICTS

samples.each do |sample|
  id = sample.fetch("id")
  source = File.join(ROOT, sample.fetch("source"))
  status = sample["status"]

  errors << "#{id}: invalid status" unless VALID_STATUSES.include?(status)
  unless [true, false].include?(sample["requires_exception"])
    errors << "#{id}: requires_exception must be true or false"
  end

  source_exists = File.file?(source)
  source_text = source_exists ? File.read(source) : ""
  excerpt_present = if sample["match"] == "exact-line"
                      source_text.lines.any? { |line| line.chomp == sample.fetch("excerpt") }
                    else
                      source_text.include?(sample.fetch("excerpt"))
                    end
  if status == "present"
    errors << "#{id}: missing source #{sample.fetch("source")}" unless source_exists
    errors << "#{id}: present excerpt drifted from #{sample.fetch("source")}" if source_exists && !excerpt_present
  elsif status == "resolved"
    errors << "#{id}: missing source #{sample.fetch("source")}" unless source_exists
    unless %w[EDIT DELETE].include?(sample["final"])
      errors << "#{id}: only EDIT/DELETE samples can be resolved"
    end
    if sample["resolution_reference"].to_s.empty?
      errors << "#{id}: resolved sample lacks resolution_reference"
    end
    errors << "#{id}: resolved stale excerpt remains in source" if excerpt_present
  elsif status == "retired"
    errors << "#{id}: retired sample lacks retirement_reason" if sample["retirement_reason"].to_s.empty?
  end

  %w[reviewer_a reviewer_b final].each do |field|
    errors << "#{id}: invalid #{field}" unless REQUIRED_VERDICTS.include?(sample[field])
  end
  errors << "#{id}: missing rationale" if sample["why"].to_s.empty?

  exception = sample["exception"]
  if sample["requires_exception"]
    errors << "#{id}: exceptions only apply to KEEP voice" unless sample["final"] == "KEEP voice"
    if exception.nil?
      errors << "#{id}: required exception is missing"
    else
      EXCEPTION_FIELDS.each do |field|
        errors << "#{id}: exception lacks #{field}" if exception[field].to_s.empty?
      end
      errors << "#{id}: exception must approve rhetorical form only" unless exception["approval"] == "rhetorical-form-only"
      begin
        Date.iso8601(exception["reviewed_on"].to_s)
      rescue Date::Error
        errors << "#{id}: exception reviewed_on must be an ISO date"
      end
    end
  elsif exception
    errors << "#{id}: exception present when requires_exception is false"
  end

  if sample["final"] == "KEEP voice"
    exception_required = sample["edge"] != "earned-compression"
    unless sample["requires_exception"] == exception_required
      errors << "#{id}: KEEP voice requires an exception unless edge is exactly earned-compression"
    end
  end
end

missing_edges = REQUIRED_EDGES - active_samples.map { |sample| sample["edge"] }.uniq
errors << "missing adversarial edges: #{missing_edges.join(", ")}" unless missing_edges.empty?

missing_finals = REQUIRED_VERDICTS - active_samples.map { |sample| sample["final"] }.uniq
errors << "missing final verdicts: #{missing_finals.join(", ")}" unless missing_finals.empty?

if errors.empty?
  disagreements = samples.count { |sample| sample["reviewer_a"] != sample["reviewer_b"] }
  puts "House voice calibration valid: #{samples.length} samples, #{disagreements} adjudicated disagreements."
else
  warn "House voice calibration failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
