# frozen_string_literal: true

require "open3"
require "pathname"
require "psych"

ROOT = Pathname.new(__dir__).join("../..").expand_path
MANIFEST = ROOT.join("docs/editorial/public-doc-corpus.yml")
FIELDS = %w[audience outcome lifecycle target_section route url_disposition].freeze
LIFECYCLES = %w[keep merge move redirect archive].freeze
KINDS = %w[public history excluded].freeze
TARGET_SECTIONS = ["Start", "Build", "Understand", "Evaluate / Optimize", "Operate", "Extend", "Cross-cutting reference", "Blog / History"].freeze
FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB
REQUIRED_SURFACES = %w[
  README.md docs/src/getting-started/index.md docs/src/getting-started/installation.md
  docs/src/getting-started/quick-start.md docs/src/getting-started/first-program.md
  docs/src/getting-started/core-concepts.md docs/src/core-concepts/toolsets.md
  docs/src/core-concepts/toolsets-guide.md docs/src/advanced/custom-toolsets.md
  docs/src/llms.txt.erb docs/src/llms-full.txt.erb examples/README.md
  examples/ade_optimizer_gepa/README.md examples/ade_optimizer_miprov2/README.md
  examples/coffee-shop-agent/README.md examples/deep_research_cli/README.md
  examples/github-assistant/README.md examples/html_to_markdown/README.md
  examples/sentiment-evaluation/README.md lib/dspy/anthropic/README.md
  lib/dspy/code_act/README.md lib/dspy/deep_research/README.md
  lib/dspy/deep_search/README.md lib/dspy/gemini/README.md
  lib/dspy/openai/README.md lib/dspy/ruby_llm/README.md lib/sorbet/toon/README.md
].freeze

def tracked_sources
  output, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", chdir: ROOT.to_s)
  abort "git ls-files failed" unless status.success?

  output.lines(chomp: true).select do |path|
    path.end_with?(".md") || path.match?(%r{(^|/)llms(?:-full)?\.txt\.erb\z})
  end
end

def matches?(rule, source)
  return source == rule["path"] if rule["path"]

  File.fnmatch?(rule.fetch("glob"), source, FLAGS) &&
    !Array(rule["except"]).include?(source)
end

def expand(value, source)
  value.to_s.gsub("{source}", source).gsub("{slug}", File.basename(source, ".md"))
end

def effective_rule(rule, source)
  override = rule.fetch("overrides", {}).fetch(source, {})
  effective = rule.merge(override).except("overrides")
  effective["route"] = expand(effective["route"], source)
  effective
end

def normalized_route(route)
  value = route.to_s.strip
  return value.sub(%r{/+\z}, "") if value.start_with?("repository:")

  value = "/#{value}" unless value.start_with?("/")
  value = value.gsub(%r{/+}, "/")
  return value if File.extname(value) != ""

  value == "/" ? value : "#{value.sub(%r{/+\z}, '')}/"
end

manifest = Psych.safe_load_file(MANIFEST, aliases: false)
rules = manifest.fetch("rules")
errors = []

rules.each do |rule|
  errors << "#{rule['id']}: unknown kind #{rule['kind'].inspect}" unless KINDS.include?(rule["kind"])
  errors << "#{rule['id']}: specify exactly one of path or glob" unless [rule.key?("path"), rule.key?("glob")].count(true) == 1
  if rule["glob"] && !rule["allow_empty"] && tracked_sources.none? { |source| matches?(rule, source) }
    errors << "#{rule['id']}: glob matches no eligible local source"
  end
  Array(rule["overrides"]&.keys).each do |source|
    errors << "#{rule['id']}: override #{source} is not matched by its rule" unless matches?(rule, source)
    errors << "#{rule['id']}: override #{source} is not an eligible local source" unless tracked_sources.include?(source)
  end
  if rule["kind"] == "public" && rule["glob"]
    tracked_sources.select { |source| matches?(rule, source) }.each do |source|
      errors << "#{rule['id']}: public glob source #{source} needs an explicit override" unless rule.fetch("overrides", {}).key?(source)
    end
  end
end

classified = tracked_sources.to_h do |source|
  matching = rules.select { |rule| matches?(rule, source) }
  errors << "#{source}: not classified" if matching.empty?
  errors << "#{source}: classified by #{matching.map { |r| r['id'] }.join(', ')}" if matching.length > 1
  [source, matching.first && effective_rule(matching.first, source)]
end

rules.each do |rule|
  next unless rule["path"]
  errors << "#{rule['id']}: path is not a tracked documentation source" unless classified.key?(rule["path"])
end

outcomes = Hash.new { |hash, key| hash[key] = [] }
routes = Hash.new { |hash, key| hash[key] = [] }
classified.each do |source, rule|
  next unless rule

  if rule["kind"] == "excluded"
    errors << "#{source}: excluded rule needs a reason" if rule["reason"].to_s.strip.empty?
    next
  end

  FIELDS.each do |field|
    errors << "#{source}: missing #{field}" if rule[field].to_s.strip.empty?
  end
  errors << "#{source}: invalid lifecycle #{rule['lifecycle'].inspect}" unless LIFECYCLES.include?(rule["lifecycle"])
  errors << "#{source}: invalid target section #{rule['target_section'].inspect}" unless TARGET_SECTIONS.include?(rule["target_section"])
  errors << "#{source}: route must be explicit" if rule["route"].to_s.match?(/[{}]|derived|repository README|repository examples/i)
  errors << "#{source}: logical route must exclude /dspy.rb base path" if rule["route"].to_s.start_with?("/dspy.rb/")
  if source.start_with?("docs/src/_articles/")
    expected = "/blog/articles/#{File.basename(source, '.md')}/"
    errors << "#{source}: article route must be #{expected}" unless rule["route"] == expected
  end
  if %w[merge move redirect].include?(rule["lifecycle"]) && !rule["url_disposition"].to_s.start_with?("redirect-to:")
    errors << "#{source}: #{rule['lifecycle']} lifecycle needs redirect-to disposition"
  end
  if rule["lifecycle"] == "keep" && rule["url_disposition"].to_s.start_with?("redirect-to:")
    errors << "#{source}: keep lifecycle cannot redirect"
  end
  errors << "#{source}: public outcome contains a template" if rule["kind"] == "public" && rule["outcome"].to_s.include?("{")

  if rule["owner_type"] == "derived"
    errors << "#{source}: derived aggregate cannot declare canonical_owner" if rule.key?("canonical_owner")
    errors << "#{source}: missing derived_owner" if rule["derived_owner"].to_s.strip.empty?
    errors << "#{source}: derivation_status must be planned" unless rule["derivation_status"] == "planned"
    errors << "#{source}: planned_inputs must be a nonempty string list" unless rule["planned_inputs"].is_a?(Array) && rule["planned_inputs"].all? { |input| input.is_a?(String) && !input.strip.empty? } && !rule["planned_inputs"].empty?
    errors << "#{source}: missing current provenance" if rule["current_provenance"].to_s.strip.empty?
    errors << "#{source}: missing target provenance" if rule["target_provenance"].to_s.strip.empty?
    errors << "#{source}: missing aggregate sync contract" if rule["sync_contract"].to_s.strip.empty?
  else
    errors << "#{source}: unknown owner_type #{rule['owner_type'].inspect}" if rule.key?("owner_type")
    owner = expand(rule["canonical_owner"], source)
    errors << "#{source}: missing canonical_owner" if owner.strip.empty?
    errors << "#{source}: canonical owner #{owner.inspect} is not tracked" unless classified.key?(owner)
    if rule["kind"] == "public" && classified[owner]&.fetch("kind", nil) != "public"
      errors << "#{source}: canonical owner #{owner.inspect} is not public"
    end
  end
  outcomes[expand(rule["outcome"], source)] << source if rule["kind"] == "public"
  routes[normalized_route(rule["route"])] << [source, rule]
end

outcomes.each_value do |sources|
  errors << "duplicate public outcome: #{sources.join(', ')}" if sources.length > 1
end

routes.each do |route, entries|
  next if entries.length == 1
  aliases = entries.map { |_source, rule| rule["intentional_alias"] }.uniq
  next if aliases.length == 1 && !aliases.first.to_s.strip.empty?

  errors << "duplicate logical route #{route}: #{entries.map(&:first).join(', ')} (set one shared intentional_alias to approve)"
end

# Canonical ownership is a directed graph. Every non-derived public source must
# terminate at a retained, self-owned public source; cycles other than that
# terminal self-edge are invalid.
classified.each do |source, rule|
  next unless rule&.fetch("kind", nil) == "public" && rule["owner_type"] != "derived"

  cursor = source
  visited = []
  loop do
    cursor_rule = classified[cursor]
    break unless cursor_rule
    owner = expand(cursor_rule["canonical_owner"], cursor)
    if owner == cursor
      errors << "#{source}: owner terminates at non-retained #{cursor}" unless %w[keep move].include?(cursor_rule["lifecycle"])
      break
    end
    if visited.include?(cursor)
      errors << "#{source}: canonical-owner cycle: #{(visited + [cursor]).join(' -> ')}"
      break
    end
    visited << cursor
    if classified[owner]&.fetch("owner_type", nil) == "derived"
      errors << "#{source}: canonical owner graph cannot terminate at derived aggregate #{owner}"
      break
    end
    cursor = owner
  end
end

REQUIRED_SURFACES.each do |required|
  errors << "required surface missing: #{required}" unless classified[required]&.fetch("kind", nil) == "public"
end

unless errors.empty?
  warn errors.map { |error| "ERROR: #{error}" }.join("\n")
  exit 1
end

counts = classified.values.compact.map { |rule| rule.fetch("kind") }.tally
article_count = classified.count { |source, _rule| source.start_with?("docs/src/_articles/") }
aggregate_count = classified.count { |_source, rule| rule&.fetch("owner_type", nil) == "derived" }
puts "Public documentation corpus is valid: #{classified.length} tracked sources " \
     "(#{counts.fetch('public', 0)} public, #{counts.fetch('history', 0)} history, " \
     "#{counts.fetch('excluded', 0)} excluded)."
puts "Validated: exact local source coverage (tracked plus untracked/nonignored), metadata, unique outcomes, canonical-owner graph, sections, normalized route uniqueness, and lifecycle dispositions."
puts "Audited: #{article_count} deterministic /blog/articles/:slug/ history routes and #{aggregate_count} planned derived aggregates with current/target provenance."
puts "Not validated: rendered URLs, anchors/fragments, redirects at runtime, or llms aggregate drift; those checks are deferred to dspy.rb-2ey.10."
