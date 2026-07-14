#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
LEDGER_PATH = File.join(ROOT, "docs/editorial/semantic-anchors.yml")
CORPUS_PATH = File.join(ROOT, "docs/editorial/public-doc-corpus.yml")
VOICE_PATH = File.join(ROOT, "docs/editorial/house-voice-samples.yml")

REQUIRED_ANCHORS = %w[
  readme-product-promise readme-three-beat-contrast readme-mental-model
  predictor-taxonomy validation-not-correctness ruby-versus-agent-ownership
  feature-parity-non-goal evaluation-limits anti-overfitting
  agent-side-effect-boundary troubleshooting-decision-rule
].freeze
REQUIRED_COPY_OCCURRENCES = %w[
  llms-index-build-like-software llms-full-build-like-software
  llms-index-production-ready llms-full-production-ready
  llms-index-automatic-optimization llms-full-automatic-optimization
].freeze
PRESERVATIONS = %w[literal-preferred semantic-required retire-with-reason].freeze
SOURCE_STATUSES = %w[present moved deleted stale].freeze
DUPLICATE_DISPOSITIONS = %w[
  align-to-owner derive-or-link link-and-specialize expand-owner-model
  summarize-and-link preserve-through-merge retain-historical
  specialize-for-optimization retain-optimizer-specific
  retain-historical-detail retain-stronger-codeact-boundary align-positioning
  redirect-and-retire-copy
].freeze

def tracked_prose
  output, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", chdir: ROOT)
  abort "Could not list tracked prose" unless status.success?
  output.lines(chomp: true).select do |path|
    path.end_with?(".md") || path.match?(%r{(^|/)llms(?:-full)?\.txt\.erb\z})
  end
end

def matches?(record, path)
  patterns = [record["path"], record["glob"]].compact
  patterns.any? { |pattern| File.fnmatch?(pattern, path, File::FNM_EXTGLOB | File::FNM_PATHNAME) } &&
    !Array(record["except"]).include?(path)
end

def file_contains?(record)
  path = File.join(ROOT, record.fetch("path"))
  return false unless File.file?(path)

  text = File.read(path, encoding: "UTF-8")
  locator = record.fetch("locator").to_s.encode("UTF-8")
  count = text.scan(Regexp.new(Regexp.escape(locator))).length
  record["allow_multiple"] ? count.positive? : count == 1
end

def effective_rule(rule, source)
  rule.merge(rule.fetch("overrides", {}).fetch(source, {})).except("overrides")
end

def expanded_owner(rule, source)
  rule["canonical_owner"].to_s.gsub("{source}", source)
end

ledger = YAML.load_file(LEDGER_PATH)
corpus = YAML.load_file(CORPUS_PATH)
voice = YAML.load_file(VOICE_PATH)
anchors = ledger.fetch("anchors")
errors = []
local_sources = tracked_prose
manifest_rules = corpus.fetch("rules")
classified = local_sources.to_h do |path|
  matched = manifest_rules.select { |rule| matches?(rule, path) }
  errors << "#{path}: corpus classification matched #{matched.length} rules" unless matched.length == 1
  [path, matched.length == 1 ? effective_rule(matched.first, path) : nil]
end

ids = anchors.map { |anchor| anchor["id"] }
errors << "duplicate anchor ids" unless ids.uniq.length == ids.length
(REQUIRED_ANCHORS - ids).each { |id| errors << "missing acceptance anchor: #{id}" }

anchors.each do |anchor|
  id = anchor.fetch("id")
  %w[acceptance_anchor lifecycle semantic_job preservation successor_contract].each do |field|
    errors << "#{id}: missing #{field}" if anchor[field].to_s.empty?
  end
  errors << "#{id}: invalid preservation" unless PRESERVATIONS.include?(anchor["preservation"])
  errors << "#{id}: invalid lifecycle" unless %w[active retired].include?(anchor["lifecycle"])

  source = anchor.fetch("source")
  status = source["status"]
  errors << "#{id}: invalid source status" unless SOURCE_STATUSES.include?(status)
  source_path = File.join(ROOT, source.fetch("path"))
  source_text = File.file?(source_path) ? File.read(source_path, encoding: "UTF-8") : ""
  if status == "present"
    errors << "#{id}: present source locator is not unique" unless file_contains?(source)
    if anchor["preservation"] == "literal-preferred"
      excerpt = source["observed_excerpt"]
      errors << "#{id}: literal-preferred source lacks observed_excerpt" if excerpt.to_s.empty?
      errors << "#{id}: preferred literal drifted; update status or ledger after correctness review" unless excerpt.to_s.empty? || source_text.include?(excerpt)
    end
  elsif status == "moved"
    errors << "#{id}: #{status} source lacks migration_reference" if source["migration_reference"].to_s.empty?
    errors << "#{id}: moved old locator still exists" if source_text.include?(source.fetch("locator"))
  elsif status == "deleted"
    errors << "#{id}: deleted source lacks migration_reference" if source["migration_reference"].to_s.empty?
    errors << "#{id}: deleted old locator still exists" if source_text.include?(source.fetch("locator"))
  elsif status == "stale"
    errors << "#{id}: stale source lacks migration_reference" if source["migration_reference"].to_s.empty?
    errors << "#{id}: stale source lacks observed_excerpt" if source["observed_excerpt"].to_s.empty?
    errors << "#{id}: stale source lacks stale_reason" if source["stale_reason"].to_s.empty?
    errors << "#{id}: stale excerpt still exists" if source_text.include?(source["observed_excerpt"].to_s)
  end
  retired = anchor["lifecycle"] == "retired"
  retiring = anchor["preservation"] == "retire-with-reason"
  errors << "#{id}: retired lifecycle and retire-with-reason must agree" unless retired == retiring
  errors << "#{id}: retirement reason missing" if retiring && anchor["retirement_reason"].to_s.empty?

  %w[factual_owner canonical_destination].each do |field|
    record = anchor.fetch(field)
    errors << "#{id}: #{field} cannot be a generated llms reference" if record.fetch("path").match?(/llms.*\.erb\z/)
    errors << "#{id}: #{field} locator is not findable" unless file_contains?(record)
    next if record["future_target"]

    rule = classified[record.fetch("path")]
    if rule.nil? || rule["kind"] != "public"
      errors << "#{id}: #{field} is not an effective public corpus source"
    elsif !%w[keep move].include?(rule["lifecycle"])
      errors << "#{id}: #{field} resolves to #{rule["lifecycle"]} lifecycle"
    elsif rule["owner_type"] == "derived" || expanded_owner(rule, record.fetch("path")) != record.fetch("path")
      errors << "#{id}: #{field} is not a canonical factual owner"
    end
  end

  Array(anchor["evidence"]).each do |record|
    errors << "#{id}: evidence locator is not findable" unless file_contains?(record)
  end
  Array(anchor["duplicates"]).each do |duplicate|
    errors << "#{id}: duplicate locator is not findable" unless file_contains?(duplicate)
    unless DUPLICATE_DISPOSITIONS.include?(duplicate["disposition"])
      errors << "#{id}: invalid duplicate disposition #{duplicate["disposition"].inspect}"
    end
  end
end

aphorisms = ledger.fetch("aphorism_candidates")
aphorism_ids = aphorisms.map { |candidate| candidate["id"] }
errors << "aphorism candidate ids are duplicated" unless aphorism_ids.uniq.length == aphorism_ids.length
aphorisms.each do |candidate|
  id = candidate.fetch("id")
  errors << "#{id}: invalid disposition" unless %w[retain rewrite delete].include?(candidate["disposition"])
  errors << "#{id}: missing reason" if candidate["reason"].to_s.empty?
  source = {"path" => candidate.fetch("source"), "locator" => candidate.fetch("locator")}
  if candidate["status"] == "present"
    errors << "#{id}: present aphorism locator is not unique" unless file_contains?(source)
    errors << "#{id}: present aphorism must be active" unless candidate["lifecycle"] == "active"
  elsif candidate["status"] == "resolved"
    errors << "#{id}: resolved aphorism lacks resolution_reference" if candidate["resolution_reference"].to_s.empty?
    path = File.join(ROOT, candidate.fetch("source"))
    errors << "#{id}: resolved aphorism remains" if File.file?(path) && File.read(path).include?(candidate.fetch("locator"))
    expected = candidate["disposition"] == "delete" ? "retired" : "active"
    errors << "#{id}: resolved aphorism lifecycle should be #{expected}" unless candidate["lifecycle"] == expected
  else
    errors << "#{id}: invalid aphorism status"
  end
end

voice_samples = voice.fetch("samples").to_h { |sample| [sample.fetch("id"), sample] }
voice_records = ledger.fetch("voice_dispositions")
voice_ids = voice_records.map { |record| record["sample_id"] }
errors << "voice disposition ids are duplicated" unless voice_ids.uniq.length == voice_ids.length
(voice_samples.keys - voice_ids).each { |id| errors << "missing voice disposition: #{id}" }
(voice_ids - voice_samples.keys).each { |id| errors << "unknown voice disposition: #{id}" }

voice_records.each do |record|
  id = record.fetch("sample_id")
  sample = voice_samples[id]
  next unless sample
  expected = {"KEEP technical" => "retain", "KEEP voice" => "retain", "EDIT" => "rewrite", "DELETE" => "delete"}.fetch(sample.fetch("final"))
  errors << "#{id}: disposition should be #{expected}" unless record["disposition"] == expected
  expected_lifecycle = if sample["status"] == "retired" || (sample["status"] == "resolved" && expected == "delete")
                         "retired"
                       else
                         "active"
                       end
  errors << "#{id}: lifecycle should be #{expected_lifecycle}" unless record["lifecycle"] == expected_lifecycle
  errors << "#{id}: voice disposition lacks reason" if record["reason"].to_s.empty?
end

copy_occurrences = ledger.fetch("copy_occurrences")
copy_ids = copy_occurrences.map { |record| record["id"] }
errors << "copy occurrence ids are duplicated" unless copy_ids.uniq.length == copy_ids.length
(REQUIRED_COPY_OCCURRENCES - copy_ids).each { |id| errors << "missing copy occurrence: #{id}" }
copy_occurrences.each do |record|
  id = record.fetch("id")
  errors << "#{id}: invalid disposition" unless %w[retain rewrite delete].include?(record["disposition"])
  errors << "#{id}: missing reason" if record["reason"].to_s.empty?
  source = {"path" => record.fetch("source"), "locator" => record.fetch("locator")}
  if record["status"] == "present"
    errors << "#{id}: present copy locator is not unique" unless file_contains?(source)
    errors << "#{id}: present copy must be active" unless record["lifecycle"] == "active"
  elsif record["status"] == "resolved"
    errors << "#{id}: resolved copy lacks resolution_reference" if record["resolution_reference"].to_s.empty?
    path = File.join(ROOT, record.fetch("source"))
    errors << "#{id}: resolved stale copy remains" if File.file?(path) && File.read(path, encoding: "UTF-8").include?(record.fetch("locator"))
    expected_lifecycle = record["disposition"] == "delete" ? "retired" : "active"
    errors << "#{id}: lifecycle should be #{expected_lifecycle}" unless record["lifecycle"] == expected_lifecycle
  else
    errors << "#{id}: invalid copy status"
  end
  next unless record["voice_sample"]

  sample = voice_samples[record["voice_sample"]]
  if sample.nil?
    errors << "#{id}: unknown voice sample #{record["voice_sample"]}"
  else
    expected = {"KEEP technical" => "retain", "KEEP voice" => "retain", "EDIT" => "rewrite", "DELETE" => "delete"}.fetch(sample.fetch("final"))
    errors << "#{id}: disposition should follow voice sample as #{expected}" unless record["disposition"] == expected
  end
end

public_copy_sources = ledger.fetch("public_copy_sources")
site_metadata = "docs/src/_data/site_metadata.yml"
errors << "public copy sources must include #{site_metadata}" unless public_copy_sources.any? { |record| record["path"] == site_metadata }
public_copy_sources.each do |record|
  path = record.fetch("path")
  errors << "#{path}: public-copy format must be explicit" if record["format"].to_s.empty?
  errors << "#{path}: public-copy scope must be explicit" if record["scope"].to_s.empty?
  errors << "#{path}: public-copy source missing" unless File.file?(File.join(ROOT, path))
  claims = record.fetch("claims")
  errors << "#{path}: public-copy source needs claims" if claims.empty?
  claims.each do |claim|
    locator_record = {"path" => path, "locator" => claim.fetch("locator")}
    if claim["status"] == "present"
      errors << "#{path}: public-copy claim locator is not unique" unless file_contains?(locator_record)
      errors << "#{path}: present public-copy claim must be active" unless claim["lifecycle"] == "active"
    elsif claim["status"] == "resolved"
      errors << "#{path}: resolved public-copy claim lacks resolution_reference" if claim["resolution_reference"].to_s.empty?
      source_text = File.file?(File.join(ROOT, path)) ? File.read(File.join(ROOT, path), encoding: "UTF-8") : ""
      errors << "#{path}: resolved stale public-copy claim remains" if source_text.include?(claim.fetch("locator"))
      expected_lifecycle = claim["disposition"] == "delete" ? "retired" : "active"
      errors << "#{path}: resolved public-copy lifecycle should be #{expected_lifecycle}" unless claim["lifecycle"] == expected_lifecycle
    else
      errors << "#{path}: invalid public-copy claim status"
    end
    sample = voice_samples[claim["voice_sample"]]
    if sample.nil?
      errors << "#{path}: unknown voice sample #{claim["voice_sample"]}"
      next
    end
    errors << "#{path}: voice sample points to #{sample["source"]}" unless sample["source"] == path
    expected_status = sample["status"] == "present" ? "present" : "resolved"
    errors << "#{path}: claim status should follow voice sample as #{expected_status}" unless claim["status"] == expected_status
    expected = {"KEEP technical" => "retain", "KEEP voice" => "retain", "EDIT" => "rewrite", "DELETE" => "delete"}.fetch(sample.fetch("final"))
    errors << "#{path}: claim disposition should be #{expected}" unless claim["disposition"] == expected
    errors << "#{path}: claim reason missing" if claim["reason"].to_s.empty?
  end
end

public_sources = classified.select do |_path, rule|
  rule && %w[public history].include?(rule["kind"])
end.keys
considerations = ledger.fetch("corpus_consideration")
public_sources.each do |path|
  matched = considerations.select { |record| matches?(record, path) }
  errors << "corpus consideration for #{path}: matched #{matched.length}" unless matched.length == 1
end
considerations.each do |record|
  errors << "#{record.fetch("id")}: consideration lacks result" if record["result"].to_s.empty?
  Array(record["anchors"]).each do |id|
    errors << "#{record.fetch("id")}: unknown anchor #{id}" unless ids.include?(id)
  end
end

if errors.empty?
  puts "Semantic anchor ledger valid: #{anchors.length} anchors, #{voice_records.length} voice dispositions, #{public_sources.length} corpus sources considered."
else
  warn "Semantic anchor ledger validation failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
