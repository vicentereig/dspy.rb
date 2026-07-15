#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"
require_relative "validate_legacy_package_evidence"

ROOT = Pathname.new(__dir__).join("../..").expand_path
MATRIX_PATH = ROOT.join("docs/src/_data/package_capabilities.yml")
NAV_PATH = ROOT.join("docs/src/_data/documentation_navigation.yml")
DEFAULT_OUTPUT = ROOT.join("docs/output")
STATUSES = %w[preview supported supporting].freeze
ROLES = %w[core optional-feature provider-adapter supporting-library].freeze
VISIBILITIES = %w[internal public].freeze
INTERNAL_STATUSES = %w[supporting].freeze
EVIDENCE_SUPPORT = %w[distribution loading status verification].freeze
NUMERIC_CAPABILITY_INVENTORY = /\b\d+\+?\s+(?:LLM\s+)?(?:providers?|models?)\b/i
REQUIRED_SELECTION_SURFACES = %w[
  docs/src/getting-started/quick-start.md
  docs/src/production/observability.md
  docs/src/optimization/evaluation.md
  docs/src/optimization/miprov2.md
  docs/src/optimization/gepa.md
  docs/src/core-concepts/codeact.md
  lib/dspy/code_act/README.md
].freeze

def read_utf8(path)
  File.binread(path).force_encoding(Encoding::UTF_8).scrub
end

output = DEFAULT_OUTPUT
source_only = false
OptionParser.new do |options|
  options.on("--output PATH") { |path| output = Pathname.new(path).expand_path }
  options.on("--source-only") { source_only = true }
end.parse!

matrix = YAML.safe_load_file(MATRIX_PATH)
packages = matrix.fetch("packages")
errors = []

errors << "matrix version must be 1" unless matrix["version"] == 1
errors << "canonical URL must be /getting-started/packages/" unless matrix["canonical_url"] == "/getting-started/packages/"

statuses = matrix.fetch("support_statuses", {})
roles = matrix.fetch("package_roles", {})
errors << "support status vocabulary must be exactly #{STATUSES.inspect}" unless statuses.keys.sort == STATUSES
errors << "package role vocabulary must be exactly #{ROLES.inspect}" unless roles.keys.sort == ROLES
statuses.each { |status, definition| errors << "status #{status}: definition is not substantive" if definition.to_s.length < 40 }
roles.each { |role, definition| errors << "role #{role}: definition is not substantive" if definition.to_s.length < 30 }

decisions = matrix.fetch("maintainer_decisions", {})
decisions.each do |id, decision|
  errors << "decision #{id}: decided_by must name a maintainer" if decision["decided_by"].to_s.split.length < 2
  errors << "decision #{id}: role must be DSPy.rb maintainer" unless decision["role"] == "DSPy.rb maintainer"
  errors << "decision #{id}: recorded_on is required" unless decision["recorded_on"]
  errors << "decision #{id}: undefined status #{decision['status']}" unless STATUSES.include?(decision["status"])
  errors << "decision #{id}: decision text is not durable" if decision["decision"].to_s.length < 70
end

gemspecs = Dir[ROOT.join("*.gemspec")].map { File.basename(_1) }.sort
matrix_gemspecs = packages.map { _1["gemspec"] }.sort
errors << "gemspec inventory differs: repo=#{gemspecs.inspect} matrix=#{matrix_gemspecs.inspect}" unless gemspecs == matrix_gemspecs

%w[gem gemspec visibility role support_status install require_path load_behavior capabilities limitations evidence status_basis].each do |field|
  packages.each_with_index do |package, index|
    value = package[field]
    errors << "packages[#{index}] missing #{field}" if value.nil? || value.respond_to?(:empty?) && value.empty?
  end
end

%w[gem gemspec require_path].each do |field|
  values = packages.map { _1[field] }
  errors << "duplicate package #{field}" unless values.uniq.length == values.length
end

nav_routes = YAML.safe_load_file(NAV_PATH).fetch("items").to_h { [_1.fetch("url"), _1.fetch("source", nil)] }
all_evidence_ids = []
specifications = {}

packages.each do |package|
  label = package.fetch("gem")
  spec = Dir.chdir(ROOT) { Gem::Specification.load(package.fetch("gemspec")) }
  specifications[label] = spec
  errors << "#{label}: gemspec did not load" unless spec
  next unless spec

  errors << "#{label}: gemspec name is #{spec.name}" unless spec.name == label
  errors << "#{label}: install text must contain exact gem name" unless package.fetch("install").include?("gem '#{label}'")
  errors << "#{label}: invalid visibility #{package['visibility']}" unless VISIBILITIES.include?(package["visibility"])
  errors << "#{label}: undefined role #{package['role']}" unless ROLES.include?(package["role"])
  errors << "#{label}: undefined support status #{package['support_status']}" unless STATUSES.include?(package["support_status"])
  errors << "#{label}: load behavior must state require semantics" unless package.fetch("load_behavior").downcase.include?("require")
  errors << "#{label}: limitations must be substantive" if package.fetch("limitations").length < 70
  if package["visibility"] == "internal" && !INTERNAL_STATUSES.include?(package["support_status"])
    errors << "#{label}: internal package cannot use public status #{package['support_status']}"
  end

  guide = package["guide"]
  if package["visibility"] == "public"
    errors << "#{label}: public package requires a guide" if guide.to_s.empty?
  else
    errors << "#{label}: internal package must not publish a guide" unless guide.nil?
  end
  if guide&.start_with?("repository:")
    path = guide.delete_prefix("repository:")
    errors << "#{label}: repository guide missing: #{path}" unless ROOT.join(path).file?
  elsif guide
    errors << "#{label}: site guide is not in navigation: #{guide}" unless nav_routes.key?(guide.sub(/#.*\z/, ""))
  end

  entrypoint = "lib/#{package.fetch('require_path')}.rb"
  errors << "#{label}: require entry point missing: #{entrypoint}" unless ROOT.join(entrypoint).file?
  errors << "#{label}: gemspec does not ship #{entrypoint}" unless spec.files.include?(entrypoint)

  evidence = package.fetch("evidence")
  evidence_ids = evidence.map { _1["id"] }
  errors << "#{label}: duplicate evidence id" unless evidence_ids.uniq.length == evidence_ids.length
  all_evidence_ids.concat(evidence_ids)
  supports = evidence.flat_map { Array(_1["supports"]) }.uniq.sort
  EVIDENCE_SUPPORT.each { |type| errors << "#{label}: evidence does not support #{type}" unless supports.include?(type) }
  evidence.each do |item|
    id = item["id"].to_s
    path = item["path"].to_s
    locator = item["locator"].to_s
    item_supports = Array(item["supports"])
    errors << "#{label}: evidence id #{id.inspect} is outside package namespace" unless id.start_with?("#{label}:")
    errors << "#{label}: evidence #{id} has unknown support type" unless (item_supports - EVIDENCE_SUPPORT).empty?
    source = ROOT.join(path)
    unless source.file?
      errors << "#{label}: evidence does not exist: #{path}"
      next
    end
    count = read_utf8(source).scan(Regexp.new(Regexp.escape(locator))).length
    errors << "#{label}: evidence #{id} locator must occur exactly once in #{path}, got #{count}" unless count == 1
    if item_supports.include?("distribution")
      errors << "#{label}: distribution evidence must be its gemspec" unless path == package["gemspec"]
    end
    if item_supports.include?("loading")
      errors << "#{label}: loading evidence must be its require entry point" unless path == entrypoint
    end
    if item_supports.include?("verification")
      errors << "#{label}: verification evidence must be under spec/" unless path.start_with?("spec/")
    end
  end

  basis = package.fetch("status_basis")
  decision = decisions[basis["decision"]]
  errors << "#{label}: status basis references missing decision #{basis['decision']}" unless decision
  errors << "#{label}: decision status does not match #{package['support_status']}" if decision && decision["status"] != package["support_status"]
  basis_evidence = Array(basis["evidence"])
  errors << "#{label}: status basis references evidence outside package" unless (basis_evidence - evidence_ids).empty?
  status_evidence = evidence.select { basis_evidence.include?(_1["id"]) }.flat_map { Array(_1["supports"]) }.uniq
  %w[distribution verification status].each do |support|
    errors << "#{label}: status basis evidence does not support #{support}" unless status_evidence.include?(support)
  end
end
errors << "evidence ids must be globally unique" unless all_evidence_ids.uniq.length == all_evidence_ids.length

# Compare development-only flags with the actual Gemfile blocks.
actual_flags = Hash.new { |hash, key| hash[key] = [] }
active_flag = nil
ROOT.join("Gemfile").each_line do |line|
  active_flag = Regexp.last_match(1) if line =~ /if ENV\.fetch\('(DSPY_WITH_[A-Z0-9_]+)'/
  actual_flags[active_flag] << Regexp.last_match(1) if active_flag && line =~ /gemspec name: "([^"]+)"/
  active_flag = nil if active_flag && line.strip == "end"
end
actual_flags.transform_values!(&:sort)
declared_flags = matrix.dig("monorepo_flags", "flags").transform_values(&:sort)
errors << "monorepo flag map differs: Gemfile=#{actual_flags.inspect} matrix=#{declared_flags.inspect}" unless actual_flags == declared_flags
policy = matrix.dig("monorepo_flags", "policy").to_s
errors << "monorepo flag policy must say flags are development-only and applications install gems" unless policy.include?("develop") && policy.include?("Application users")
flag_for_package = declared_flags.each_with_object({}) { |(flag, gems), map| gems.each { |gem| map[gem] = flag } }
packages.each do |package|
  expected = flag_for_package[package.fetch("gem")]
  errors << "#{package['gem']}: monorepo_flag #{package['monorepo_flag'].inspect} should be #{expected.inspect}" unless package["monorepo_flag"] == expected
end

# Provider prefixes are executable claims.
require ROOT.join("lib/dspy/lm/adapter_factory")
actual_adapters = DSPy::LM::AdapterFactory::ADAPTER_MAP.to_h { |prefix, data| [prefix, data.fetch(:gem_name)] }
declared_adapters = packages.each_with_object({}) do |package, map|
  Array(package["provider_prefixes"]).each { |prefix| map[prefix] = package.fetch("gem") }
end
errors << "provider adapter claims differ: code=#{actual_adapters.inspect} matrix=#{declared_adapters.inspect}" unless actual_adapters == declared_adapters

# Every pairwise gemspec file collision must be declared with exact paths.
actual_overlaps = {}
specifications.keys.sort.combination(2) do |left, right|
  paths = (specifications.fetch(left).files & specifications.fetch(right).files).grep(%r{\Alib/}).sort
  actual_overlaps[[left, right]] = paths unless paths.empty?
end
declared_overlaps = {}
matrix.fetch("declared_file_overlaps").each do |overlap|
  pair = overlap.fetch("packages").sort
  errors << "overlap #{pair.join(' + ')}: package pair must be unique" if declared_overlaps.key?(pair)
  errors << "overlap #{pair.join(' + ')}: disclosure is not substantive" if overlap["disclosure"].to_s.length < 80
  declared_overlaps[pair] = overlap.fetch("paths").sort
end
errors << "gemspec file overlaps differ: actual=#{actual_overlaps.inspect} declared=#{declared_overlaps.inspect}" unless actual_overlaps == declared_overlaps

# Package-selection surfaces either link the canonical matrix or must gain an explicit validated disposition.
surfaces = matrix.fetch("selection_surfaces")
surface_paths = surfaces.map { _1["path"] }
errors << "selection surface paths must be unique" unless surface_paths.uniq.length == surface_paths.length
REQUIRED_SELECTION_SURFACES.each { |path| errors << "required package-selection surface missing: #{path}" unless surface_paths.include?(path) }
surfaces.each do |surface|
  path = surface.fetch("path")
  source = ROOT.join(path)
  errors << "selection surface missing: #{path}" unless source.file?
  errors << "#{path}: unknown selection disposition" unless surface["disposition"] == "link-canonical-matrix"
  errors << "#{path}: does not link canonical package matrix" if source.file? && !read_utf8(source).include?("getting-started/packages/")
  unknown = surface.fetch("packages") - packages.map { _1["gem"] }
  errors << "#{path}: unknown packages #{unknown.inspect}" unless unknown.empty?
  internal = surface.fetch("packages").select { |gem| packages.find { _1["gem"] == gem }&.dig("visibility") == "internal" }
  errors << "#{path}: public selection surface exposes internal packages #{internal.inspect}" unless internal.empty?
end

legacy_names = matrix.fetch("legacy_names")
legacy_names.each do |legacy|
  errors << "legacy package still appears current: #{legacy['name']}" if packages.any? { _1["gem"] == legacy["name"] }
  errors << "legacy replacement missing: #{legacy['replacement']}" unless packages.any? { _1["gem"] == legacy["replacement"] }
end
errors.concat(DocumentationQuality::LegacyPackageEvidence.new(root: ROOT, entries: legacy_names).errors)

ruby_llm = packages.find { _1["gem"] == "dspy-ruby_llm" }
errors << "RubyLLM boundary must name provider/model/registry/SDK variability" unless %w[provider model registry sdk].all? { ruby_llm.fetch("limitations").downcase.include?(_1) }
code_act = packages.find { _1["gem"] == "dspy-code_act" }
errors << "CodeAct boundary must deny sandbox and permission guarantees" unless %w[sandbox permission untrusted].all? { code_act.fetch("limitations").downcase.include?(_1) }

{
  "README.md" => "getting-started/packages/",
  "docs/src/getting-started/installation.md" => "/dspy.rb/getting-started/packages/",
  "docs/src/llms.txt.erb" => "package_capabilities",
  "docs/src/llms-full.txt.erb" => "package_capabilities",
  "docs/src/getting-started/packages.md" => "declared_file_overlaps"
}.each do |path, marker|
  errors << "#{path}: does not derive from or link to canonical package matrix" unless read_utf8(ROOT.join(path)).include?(marker)
end

llms_source = read_utf8(ROOT.join("docs/src/llms.txt.erb"))
legacy_provider_rows = llms_source.scan(/^gem 'dspy-(?:openai|anthropic|gemini)'/).uniq
if llms_source.include?("## Provider Adapter Gems") || legacy_provider_rows.length > 1
  errors << "llms.txt.erb: legacy hand-maintained provider inventory remains"
end
errors << "llms.txt.erb: hand-maintained observability install inventory remains" if llms_source.include?("Install `dspy-o11y` plus")
package_guide_source = read_utf8(ROOT.join("docs/src/getting-started/packages.md"))
%w[left_package.visibility right_package.visibility].each do |guard|
  errors << "packages.md: overlap rendering lacks #{guard} guard" unless package_guide_source.include?(guard)
end

# Dated articles are historical records rather than current capability claims;
# every other task-oriented public source fails on numeric provider/model totals.
claim_sources = [ROOT.join("README.md")] + Dir[ROOT.join("*.gemspec")] +
  Dir[ROOT.join("docs/src/**/*.{md,erb}")].reject { _1.include?("/docs/src/_articles/") } +
  Dir[ROOT.join("lib/**/README.md")]
claim_sources.each do |path|
  relative = Pathname.new(path).relative_path_from(ROOT).to_s
  read_utf8(path).each_line.with_index(1) do |line, number|
    line.scan(NUMERIC_CAPABILITY_INVENTORY) do
      errors << "#{relative}:#{number}: unsupported numeric provider/model inventory #{Regexp.last_match(0).inspect}"
    end
  end
end

# When a production build exists, validate visibility and plain-text generation.
if !source_only && output.directory?
  public_gems = packages.select { _1["visibility"] == "public" }.map { _1["gem"] }
  internal_gems = packages.select { _1["visibility"] == "internal" }.map { _1["gem"] }
  %w[llms.txt llms-full.txt].each do |name|
    path = output.join(name)
    unless path.file?
      errors << "#{path}: production output missing"
      next
    end
    text = read_utf8(path)
    errors << "#{path}: contains HTML entities" if text.match?(/&(?:amp|apos|gt|lt|quot|#\d+|#x[0-9a-f]+);/i)
    errors << "#{path}: contains template residue" if text.match?(/<%|%>|\{\{|\{%/)
    public_gems.each { |gem| errors << "#{path}: public package row missing #{gem}" unless text.include?("- `#{gem}`") }
    internal_gems.each { |gem| errors << "#{path}: internal package leaked #{gem}" if text.include?("- `#{gem}`") }
  end

  guide = output.join("getting-started/packages/index.html")
  if guide.file?
    html = read_utf8(guide)
    public_gems.each { |gem| errors << "#{guide}: public package heading missing #{gem}" unless html.include?(%(<h3 id="#{gem}">)) }
    internal_gems.each { |gem| errors << "#{guide}: internal package name leaked #{gem}" if html.include?(gem) }
    matrix.fetch("declared_file_overlaps").each do |overlap|
      next unless (overlap.fetch("packages") & internal_gems).any?

      overlap.fetch("packages").each { |gem| errors << "#{guide}: internal overlap package leaked #{gem}" if html.include?(gem) }
      overlap.fetch("paths").each { |path| errors << "#{guide}: internal overlap path leaked #{path}" if html.include?(path) }
      errors << "#{guide}: internal overlap disclosure leaked" if html.include?(overlap.fetch("disclosure"))
    end
  else
    errors << "#{guide}: production package guide missing"
  end
end

if errors.empty?
  puts "Package capability matrix valid: #{packages.length} packages, #{actual_adapters.length} provider prefixes, #{declared_flags.length} monorepo flags, #{actual_overlaps.length} declared overlap pairs."
else
  warn errors.map { "- #{_1}" }.join("\n")
  exit 1
end
