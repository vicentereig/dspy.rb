#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("../..").expand_path
DOCS = ROOT.join("docs")
LEDGER_PATH = DOCS.join("editorial/long-page-dispositions.yml")
CORPUS_PATH = DOCS.join("editorial/public-doc-corpus.yml")
NAV_PATH = DOCS.join("src/_data/documentation_navigation.yml")
REDIRECT_PATH = DOCS.join("editorial/url-redirects.yml")
TOKEN_PATTERN = /[[:alnum:]_]+(?:[-_][[:alnum:]_]+)*/u
FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
REQUIRED_INITIAL = %w[
  docs/src/production/observability.md docs/src/advanced/complex-types.md
  docs/src/core-concepts/signatures.md docs/src/core-concepts/predictors.md
  docs/src/core-concepts/multimodal.md docs/src/optimization/gepa.md
  docs/src/advanced/custom-metrics.md docs/src/advanced/stateful-agents.md
  docs/src/advanced/rails-integration.md docs/src/core-concepts/module-runtime-context.md
  docs/src/core-concepts/modules.md docs/src/index.md CHANGELOG.md
].freeze
REQUIRED_SPLITS = %w[concurrent-predictions module-lifecycle-callbacks score-reporting].freeze

def read_utf8(path)
  File.binread(path).force_encoding(Encoding::UTF_8)
end

def body(path)
  read_utf8(path).sub(/\A---\s*\n.*?\n---\s*\n/m, "")
end

def token_count(path)
  body(path).scan(TOKEN_PATTERN).length
end

def source_route(path)
  text = read_utf8(path)
  frontmatter = text[/\A---\s*\n(.*?)\n---\s*\n/m, 1]
  data = frontmatter ? YAML.safe_load(frontmatter, permitted_classes: [Date, Time]) : {}
  return data["permalink"] if data["permalink"]

  relative = path.relative_path_from(DOCS.join("src")).to_s
  return "/" if relative == "index.md"

  "/#{relative.sub(/\.md\z/, '').sub(%r{/index\z}, '')}/"
end

def matches?(rule, source)
  return source == rule["path"] if rule["path"]

  File.fnmatch?(rule.fetch("glob"), source, FLAGS) && !Array(rule["except"]).include?(source)
end

def effective_kind(rule, source)
  rule.dig("overrides", source, "kind") || rule.fetch("kind")
end

def corpus_markdown(corpus)
  tracked = `git -C #{ROOT} ls-files --cached --others --exclude-standard`.lines(chomp: true)
  tracked.grep(/\.md\z/).select do |source|
    rules = corpus.fetch("rules").select { |rule| matches?(rule, source) }
    rules.length == 1 && %w[public history].include?(effective_kind(rules.first, source))
  end
end

def heading_ids(text)
  fenced = false
  counts = Hash.new(0)
  text.each_line.filter_map do |line|
    if line.match?(/^\s*(```|~~~)/)
      fenced = !fenced
      next
    end
    next if fenced

    match = line.match(/^\s{0,3}\#{1,6}\s+(.+?)\s*\#*\s*$/)
    next unless match

    explicit = match[1][/\{#([^}]+)\}\s*\z/, 1]
    id = explicit || match[1].gsub(/<[^>]+>|[`*~]/, "").downcase.gsub(/[^a-z0-9 _-]/, "").strip.gsub(/\s+/, "-").gsub(/-+/, "-")
    suffix = counts[id]
    counts[id] += 1
    suffix.zero? ? id : "#{id}-#{suffix}"
  end
end

def source_anchor_ids(text)
  (heading_ids(text) + text.scan(/\bid=["']([^"']+)["']/).flatten).uniq
end

def rendered_anchor_ids(text)
  text.scan(/\bid=["']([^"']+)["']/).flatten.uniq
end

def anchors_exist?(anchors, source_ids, rendered_ids = nil)
  anchors.all? { |anchor| source_ids.include?(anchor) } &&
    (rendered_ids.nil? || anchors.all? { |anchor| rendered_ids.include?(anchor) })
end

def corpus_routes(corpus)
  corpus.fetch("rules").flat_map do |rule|
    if rule["path"]
      [[rule["path"], rule["route"]]]
    else
      rule.fetch("overrides", {}).map { |source, data| [source, data["route"] || rule["route"]] }
    end
  end.to_h
end

def artifact(output, route)
  output.join(route.delete_prefix("/"), "index.html")
end

def coverage_valid?(expected, actual)
  expected.sort == actual.sort && actual.uniq.length == actual.length
end

def navigation_discovery_valid?(items, source, route)
  items.any? { _1["source"] == source && _1["url"] == route }
end

def compatibility_valid?(text, marker, public_route, aliases = [])
  text.include?(marker) &&
    aliases.all? { |anchor| text.include?(%Q{id="#{anchor}"}) } &&
    text.include?("](/dspy.rb#{public_route})")
end

def stale_inbound?(text, pattern)
  text.match?(pattern)
end

def sitemap_routes(output)
  path = output.join("sitemap.xml")
  return [] unless path.file?

  read_utf8(path).scan(%r{<loc>https?://[^<]+?/dspy\.rb(/[^<]*)</loc>}).flatten
end

output = nil
ledger_path = LEDGER_PATH
OptionParser.new do |options|
  options.on("--output PATH") { |path| output = Pathname.new(path).expand_path }
  options.on("--ledger PATH") { |path| ledger_path = Pathname.new(path).expand_path }
end.parse!

ledger = YAML.safe_load_file(ledger_path, permitted_classes: [Date, Time])
corpus = YAML.safe_load_file(CORPUS_PATH, permitted_classes: [Date, Time])
nav = YAML.safe_load_file(NAV_PATH, permitted_classes: [Date, Time])
redirects = YAML.safe_load_file(REDIRECT_PATH, permitted_classes: [Date, Time])
errors = []

measurement = ledger.fetch("measurement")
threshold = measurement.fetch("review_trigger")
errors << "review trigger must be 1500" unless threshold == 1500
errors << "measurement must exclude frontmatter" unless measurement.fetch("frontmatter").match?(/Excluded/)
errors << "fenced-code treatment must explicitly include code" unless measurement.fetch("fenced_code").match?(/Included/)
errors << "token pattern drifted" unless measurement.fetch("token_pattern") == "[[:alnum:]_]+(?:[-_][[:alnum:]_]+)*"
errors << "review trigger is being described as a split quota" unless measurement.fetch("policy").match?(/never a quota.*never requires a split/i)

initial = ledger.fetch("initial_inventory")
initial_sources = initial.map { _1.fetch("source") }
errors << "initial research inventory is incomplete" unless initial_sources.sort == REQUIRED_INITIAL.sort
errors << "initial research inventory sources must be unique" unless initial_sources.uniq.length == initial_sources.length
errors << "initial research measurements must be positive integers" unless initial.all? { _1["tokens"].is_a?(Integer) && _1["tokens"].positive? }

eligible = corpus_markdown(corpus)
current_counts = eligible.to_h { |source| [source, token_count(ROOT.join(source))] }
triggered = current_counts.select { |_source, count| count >= threshold }.keys
dispositions = ledger.fetch("dispositions")
disposition_sources = dispositions.map { _1.fetch("source") }
expected_dispositions = (triggered + REQUIRED_INITIAL).uniq
errors << "threshold coverage differs: expected #{expected_dispositions.sort}, got #{disposition_sources.sort}" unless coverage_valid?(expected_dispositions, disposition_sources)

dispositions.each do |record|
  source = record.fetch("source")
  errors << "#{source}: source is not eligible public/history Markdown" unless eligible.include?(source)
  errors << "#{source}: measured token count drifted" unless record["measured_tokens"] == current_counts[source]
  errors << "#{source}: outcome must be keep or split" unless %w[keep split].include?(record["outcome"])
  %w[audience reason example_owner risk_review].each do |field|
    errors << "#{source}: missing #{field}" if record[field].to_s.strip.empty?
  end
  %w[canonical_definitions discovery_review].each do |field|
    errors << "#{source}: #{field} must be nonempty" unless record[field].is_a?(Array) && !record[field].empty?
  end
  policy = record["anchor_policy"]
  anchors = record["anchors"]
  errors << "#{source}: anchor_policy must be rendered, source-heading, or none" unless %w[rendered source-heading none].include?(policy)
  errors << "#{source}: anchors must be an array" unless anchors.is_a?(Array)
  if policy == "none"
    errors << "#{source}: no-anchor policy cannot declare anchors" unless anchors == []
    errors << "#{source}: no-anchor policy needs a rationale" if record["anchor_rationale"].to_s.strip.empty?
  else
    errors << "#{source}: retained anchors must be nonempty" unless anchors.is_a?(Array) && !anchors.empty?
    source_ids = source_anchor_ids(read_utf8(ROOT.join(source)))
    errors << "#{source}: declared source anchor missing" unless anchors.is_a?(Array) && anchors_exist?(anchors, source_ids)
    if policy == "rendered" && output
      rendered_page = artifact(output, source_route(ROOT.join(source)))
      if rendered_page.file?
        rendered_ids = rendered_anchor_ids(read_utf8(rendered_page))
        errors << "#{source}: declared rendered anchor missing" unless anchors_exist?(anchors, source_ids, rendered_ids)
      else
        errors << "#{source}: rendered page missing for anchor audit"
      end
    end
  end
end

fixtures = ledger.fetch("decision_fixtures")
over_keep = fixtures.any? { _1["measured_tokens"] > threshold && _1["outcome"] == "keep" && !_1["independently_sought_task"] }
under_split = fixtures.any? { _1["measured_tokens"] < threshold && _1["outcome"] == "split" && _1["independently_sought_task"] }
errors << "negative fixture missing: coherent over-trigger keep" unless over_keep
errors << "negative fixture missing: independently-sought under-trigger split" unless under_split

splits = ledger.fetch("splits")
errors << "split ids differ from the required task set" unless splits.map { _1["id"] }.sort == REQUIRED_SPLITS.sort
routes = corpus_routes(corpus)
published_nav = nav.fetch("items").select { _1["status"] == "published" }
llms_sources = %w[docs/src/llms.txt.erb docs/src/llms-full.txt.erb].to_h { |source| [source, read_utf8(ROOT.join(source))] }
definition_owners = Hash.new { |hash, key| hash[key] = [] }

splits.each do |split|
  id = split.fetch("id")
  source = split.fetch("source")
  route = split.fetch("route")
  source_text = read_utf8(ROOT.join(source))
  %w[owner outcome example_owner moved_from].each { |field| errors << "#{id}: missing #{field}" if split[field].to_s.strip.empty? }
  %w[prerequisites exits canonical_definitions].each do |field|
    errors << "#{id}: #{field} must be nonempty" unless split[field].is_a?(Array) && !split[field].empty?
  end
  split.fetch("canonical_definitions", []).each { |definition| definition_owners[definition] << source }
  errors << "#{id}: example owner must be the new source" unless split["example_owner"] == source
  errors << "#{id}: corpus route missing" unless routes[source] == route
  nav_item = published_nav.find { _1["source"] == source && _1["url"] == route }
  errors << "#{id}: published navigation item missing" unless navigation_discovery_valid?(published_nav, source, route)
  errors << "#{id}: navigation exits differ" unless nav_item && split["exits"].all? { |exit| Array(nav_item["exits"]).any? { _1["url"] == exit } }
  llms_sources.each { |name, text| errors << "#{id}: #{name} lacks canonical route" unless text.include?(route) }

  compatibility = split.fetch("compatibility")
  old_text = read_utf8(ROOT.join(compatibility.fetch("source")))
  marker = %Q{id="#{compatibility.fetch('anchor')}" data-canonical-route="#{route}"}
  aliases = compatibility.fetch("aliases", [])
  errors << "#{id}: compatibility anchor, aliases, or obvious canonical handoff missing" unless compatibility_valid?(old_text, marker, route, aliases)
  Array(split["protected_anchors"]).each do |protected|
    ids = heading_ids(read_utf8(ROOT.join(protected.fetch("source"))))
    errors << "#{id}: protected ##{protected.fetch('anchor')} moved or disappeared" unless ids.include?(protected.fetch("anchor"))
  end

  retained_route = source_route(ROOT.join(compatibility.fetch("source")))
  stale_routes = [routes.fetch(split.fetch("moved_from")), retained_route].uniq
  stale_pattern = %r{(?:https?://[^/\s)]+)?/dspy\.rb(?:#{stale_routes.map { Regexp.escape(_1) }.join('|')})\##{Regexp.escape(compatibility.fetch('anchor'))}}
  Dir.glob(ROOT.join("docs/src/**/*.{md,erb,liquid}")).each do |path|
    next if Pathname.new(path) == ROOT.join(compatibility.fetch("source"))
    errors << "#{id}: stale inbound remains in #{Pathname.new(path).relative_path_from(ROOT)}" if stale_inbound?(read_utf8(path), stale_pattern)
  end

  next unless output

  page = artifact(output, route)
  errors << "#{id}: rendered task route missing" unless page.file?
  if page.file?
    html = read_utf8(page)
    errors << "#{id}: rendered task heading missing" unless html.match?(/<h1[^>]*>.*#{Regexp.escape(source_text[/^# (.+)$/, 1])}.*<\/h1>/m)
  end
  old_route = retained_route
  old_page = artifact(output, old_route)
  if old_page.file?
    old_html = read_utf8(old_page)
    errors << "#{id}: rendered compatibility fragment missing" unless old_html.include?(%Q{id="#{compatibility.fetch('anchor')}"})
    aliases.each { |anchor| errors << "#{id}: rendered compatibility alias ##{anchor} missing" unless old_html.include?(%Q{id="#{anchor}"}) }
    errors << "#{id}: rendered compatibility lookup lacks canonical task link" unless old_html.include?("/dspy.rb#{route}")
  else
    errors << "#{id}: rendered retained route missing"
  end
end

definition_owners.each do |definition, owners|
  errors << "canonical split definition has multiple owners: #{definition}" unless owners.uniq.length == 1
end
task_outcomes = splits.map { _1["outcome"] }
errors << "canonical split outcomes must be unique" unless task_outcomes.uniq.length == task_outcomes.length

runtime_redirect = redirects.fetch("redirects").find { _1["id"] == "runtime-context-move" }
errors << "old runtime #lifecycle-callbacks does not map directly to the new owner" unless runtime_redirect&.dig("fragments", "mappings", "lifecycle-callbacks") == "/advanced/module-lifecycle-callbacks/"

if output
  sitemap = sitemap_routes(output)
  splits.each { |split| errors << "#{split.fetch('id')}: route absent from sitemap" unless sitemap.include?(split.fetch("route")) }
end

# Adversarial fault injections prove the checks are structural rather than ledger echoes.
errors << "fault injection: threshold omission escaped" if coverage_valid?(expected_dispositions, disposition_sources.drop(1))
anchor_sample = dispositions.find { _1["anchor_policy"] == "rendered" }
anchor_sample_ids = source_anchor_ids(read_utf8(ROOT.join(anchor_sample.fetch("source"))))
fake_anchors = anchor_sample.fetch("anchors") + ["fabricated-retained-anchor"]
errors << "fault injection: fabricated retained anchor escaped" if anchors_exist?(fake_anchors, anchor_sample_ids)
sample = splits.first
sample_old = read_utf8(ROOT.join(sample.dig("compatibility", "source")))
sample_marker = %Q{id="#{sample.dig('compatibility', 'anchor')}" data-canonical-route="#{sample.fetch('route')}"}
errors << "fault injection: compatibility-anchor removal escaped" if compatibility_valid?(sample_old.sub(sample_marker, ""), sample_marker, sample.fetch("route"), sample.dig("compatibility", "aliases"))
without_sample_nav = published_nav.reject { _1["source"] == sample["source"] && _1["url"] == sample["route"] }
errors << "fault injection: navigation omission escaped" if navigation_discovery_valid?(without_sample_nav, sample.fetch("source"), sample.fetch("route"))
injected = "[stale](/dspy.rb#{routes.fetch(sample.fetch('moved_from'))}##{sample.dig('compatibility', 'anchor')})"
injected_pattern = %r{/dspy\.rb#{Regexp.escape(routes.fetch(sample.fetch('moved_from')))}\##{Regexp.escape(sample.dig('compatibility', 'anchor'))}}
errors << "fault injection: stale inbound pattern was not detected" unless stale_inbound?(injected, injected_pattern)

abort(errors.map { "ERROR: #{_1}" }.join("\n")) unless errors.empty?
puts "Long-page dispositions valid: #{eligible.length} eligible Markdown sources measured, #{triggered.length} currently at or above #{threshold}, #{dispositions.length} reviewed, #{splits.length} task splits#{output ? ', rendered routes/fragments/sitemap verified' : ''}."
