#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
REPO = ROOT.join("..").cleanpath
FRAGMENT = /\A[a-z0-9][a-z0-9_-]*\z/
ROUTE = %r{\A/(?:[a-z0-9_-]+/)*\z}

def read_utf8(path)
  File.binread(path).force_encoding(Encoding::UTF_8)
end

def frontmatter(path)
  match = read_utf8(path).match(/\A---\s*\n(.*?)\n---\s*\n/m)
  match ? YAML.safe_load(match[1], permitted_classes: [Date, Time]) : {}
end

def source_route(path)
  data = frontmatter(path)
  return data["permalink"] if data["permalink"]

  relative = path.relative_path_from(ROOT.join("src")).to_s
  return "/" if relative == "index.md"
  return "/blog/articles/#{File.basename(relative, ".md")}/" if relative.start_with?("_articles/")

  "/#{relative.sub(/\.(?:md|erb|html)\z/, "").sub(%r{/index\z}, "")}/".gsub(%r{/+}, "/")
end

def heading_ids(path)
  body = read_utf8(path).sub(/\A---\s*\n.*?\n---\s*\n/m, "")
  fenced = false
  counts = Hash.new(0)
  body.each_line.filter_map do |line|
    if line.match?(/^\s*(```|~~~)/)
      fenced = !fenced
      next
    end
    next if fenced

    match = line.match(/^\s{0,3}\#{1,6}\s+(.+?)\s*\#*\s*$/)
    next unless match

    text = match[1]
    explicit = text[/\{#([^}]+)\}\s*\z/, 1]
    id = explicit || text.sub(/\{#[^}]+\}\s*\z/, "")
                         .gsub(/<[^>]+>/, "")
                         .gsub(/[`*~]/, "")
                         .downcase
                         .gsub(/[^a-z0-9 _-]/, "")
                         .strip
                         .gsub(/\s+/, "-")
                         .gsub(/-+/, "-")
    suffix = counts[id]
    counts[id] += 1
    suffix.zero? ? id : "#{id}-#{suffix}"
  end
end

def split_internal(value)
  return unless value.start_with?("/")
  return if value.count("#") > 1 || value.include?("?")

  route, fragment = value.split("#", 2)
  [route, fragment]
end

def valid_route?(route, base_path)
  route.match?(ROUTE) && !route.start_with?("#{base_path}/") && !route.include?("//")
end

def artifact(output, route)
  output.join(route.delete_prefix("/"), "index.html")
end

output = nil
OptionParser.new { _1.on("--output PATH") { |path| output = Pathname.new(path).expand_path } }.parse!
manifest = YAML.safe_load_file(ROOT.join("editorial/url-redirects.yml"))
corpus = YAML.safe_load_file(ROOT.join("editorial/public-doc-corpus.yml"))
errors = []
redirects = manifest.fetch("redirects", [])
active = redirects.select { _1["state"] == "active" }
base_path = manifest.fetch("base_path")

errors << "base_path must be /dspy.rb" unless base_path == "/dspy.rb"
errors << "unknown fragments require a non-empty fallback reason" if manifest.dig("policy", "unknown_fragment_reason").to_s.strip.empty?
froms = redirects.map { _1["from"] }
errors << "redirect sources must be normalized and unique" unless froms.uniq.length == froms.length

redirects.each do |redirect|
  id = redirect.fetch("id")
  state = redirect["state"]
  from = redirect.fetch("from")
  to = redirect.fetch("to")
  source = REPO.join(redirect.fetch("source"))
  fragments = redirect.fetch("fragments")
  mappings = fragments.fetch("mappings", {})
  retired = fragments.fetch("retired", {})

  errors << "#{id}: state must be planned or active" unless %w[planned active].include?(state)
  errors << "#{id}: planned redirects require activation_requires" if state == "planned" && redirect["activation_requires"].to_s.strip.empty?
  errors << "#{id}: source is not a normalized root-relative route" unless valid_route?(from, base_path)
  errors << "#{id}: source cannot contain query or fragment" if from.include?("?") || from.include?("#")
  errors << "#{id}: source file is missing: #{redirect["source"]}" unless source.file?

  internal = split_internal(to)
  if internal
    route, target_fragment = internal
    errors << "#{id}: internal target is not a normalized route" unless valid_route?(route, base_path)
    errors << "#{id}: invalid target fragment" if target_fragment && !target_fragment.match?(FRAGMENT)
    errors << "#{id}: target #{route} creates a chain or double move" if froms.include?(route)
  elsif !to.match?(%r{\Ahttps://[^\s?#]+(?:#[a-z0-9][a-z0-9_-]*)?\z})
    errors << "#{id}: target must be a normalized route or https URL"
  end

  overlap = mappings.keys & retired.keys
  errors << "#{id}: fragments both mapped and retired: #{overlap.join(", ")}" unless overlap.empty?
  (mappings.keys + retired.keys).each do |fragment|
    errors << "#{id}: invalid old fragment #{fragment.inspect}" unless fragment.match?(FRAGMENT)
  end
  retired.each do |fragment, reason|
    errors << "#{id}: retired ##{fragment} needs a reason" if reason.to_s.strip.empty?
  end
  mappings.each do |old_fragment, destination|
    if destination.start_with?("/")
      mapped = split_internal(destination)
      if mapped.nil? || !valid_route?(mapped[0], base_path) || (mapped[1] && !mapped[1].match?(FRAGMENT))
        errors << "#{id}: ##{old_fragment} has invalid mapped route #{destination.inspect}"
      elsif froms.include?(mapped[0])
        errors << "#{id}: ##{old_fragment} maps through another redirect source"
      end
    elsif !destination.match?(FRAGMENT)
      errors << "#{id}: ##{old_fragment} has invalid replacement fragment #{destination.inspect}"
    end
  end

  if source.file?
    missing = heading_ids(source) - mappings.keys - retired.keys
    errors << "#{id}: undispositioned source headings: #{missing.join(", ")}" unless missing.empty?
    data = frontmatter(source)
    if state == "active"
      owns_old_route = source_route(source) == from && data.fetch("published", true) != false
      errors << "#{id}: active source still owns #{from}" if owns_old_route
    elsif source_route(source) != from || data.fetch("published", true) == false
      errors << "#{id}: planned source must remain published at #{from}"
    end
  end

  target_source = redirect["target_source"] && REPO.join(redirect["target_source"])
  if target_source && !target_source.file?
    errors << "#{id}: target source is missing: #{redirect["target_source"]}"
  elsif target_source && !internal
    target_ids = heading_ids(target_source)
    mappings.values.reject { _1.start_with?("/") }.each do |target_id|
      errors << "#{id}: external target source lacks ##{target_id}" unless target_ids.include?(target_id)
    end
  elsif target_source && state == "active" && source_route(target_source) != internal[0]
    errors << "#{id}: target_source permalink #{source_route(target_source)} does not match #{internal[0]}"
  end
end

# Every corpus redirect disposition must exist in either lifecycle state.
expected = []
corpus.fetch("rules").each do |rule|
  candidates = rule["path"] ? [[rule["path"], rule]] : rule.fetch("overrides", {}).map { |path, data| [path, data.merge("id" => rule["id"])] }
  candidates.each do |path, data|
    disposition = data["url_disposition"].to_s
    expected << [data["id"] || rule["id"], path, data.fetch("route"), disposition.delete_prefix("redirect-to:")] if disposition.start_with?("redirect-to:")
  end
end
expected.each do |corpus_id, source, from, disposition|
  match = redirects.find { _1["from"] == from && _1["source"] == source }
  unless match
    errors << "#{source}: corpus redirect #{from} is missing"
    next
  end
  errors << "#{source}: corpus id mismatch" unless match["corpus_id"] == corpus_id
  expected_target = if disposition.start_with?("repository:")
                      "https://github.com/vicentereig/dspy.rb/blob/main/#{disposition.delete_prefix("repository:")}"
                    else
                      disposition
                    end
  errors << "#{source}: target differs from corpus (#{expected_target})" unless match["to"] == expected_target
end
errors << "manifest has #{redirects.length} redirects; corpus requires #{expected.length}" unless redirects.length == expected.length

# Public inbound fragments must have an explicit disposition.
scan_paths = [REPO.join("README.md")] + Dir.glob(REPO.join("{docs/src,examples,lib}/**/*.{md,erb,liquid,html}")) .map { Pathname.new(_1) }
redirects.each do |redirect|
  from = redirect.fetch("from")
  known = redirect.dig("fragments", "mappings").keys + redirect.dig("fragments", "retired").to_h.keys
  pattern = %r{(?:https?://[^/\s)]+)?(?:#{Regexp.escape(base_path)})?#{Regexp.escape(from)}#([a-zA-Z0-9_-]+)}
  scan_paths.each do |path|
    read_utf8(path).scan(pattern).flatten.each do |fragment|
      errors << "#{path.relative_path_from(REPO)}: inbound #{from}##{fragment} lacks a disposition" unless known.include?(fragment)
    end
  end
end

if output
  public_path = output.join("redirects.json")
  if public_path.file?
    public_redirects = JSON.parse(read_utf8(public_path)).fetch("redirects")
    expected_pairs = active.map { |r| ["#{base_path}#{r.fetch("from")}", r.fetch("to").start_with?("/") ? "#{base_path}#{r.fetch("to")}" : r.fetch("to")] }
    errors << "generated redirects.json must contain active redirects only" unless public_redirects.map { [_1["from"], _1["to"]] } == expected_pairs
  else
    errors << "generated redirects.json is missing"
  end

  redirects.each do |redirect|
    old_artifact = artifact(output, redirect.fetch("from"))
    if !old_artifact.file?
      errors << "#{redirect.fetch("id")}: old-route artifact is missing"
      next
    end
    html = read_utf8(old_artifact)
    marker = %{data-redirect-id="#{redirect.fetch("id")}"}
    if redirect["state"] == "planned"
      errors << "#{redirect.fetch("id")}: planned route was replaced by a redirect" if html.include?(marker) || html.include?("data-redirect-id=")
      next
    end
    errors << "#{redirect.fetch("id")}: active artifact identity mismatch or collision" unless html.include?(marker)
    target = redirect.fetch("to")
    public_target = target.start_with?("/") ? "#{base_path}#{target}" : target
    canonical = public_target.sub(/#.*/, "")
    canonical = "https://oss.vicente.services#{canonical}" unless canonical.start_with?("https://")
    errors << "#{redirect.fetch("id")}: generated target is wrong" unless html.include?(public_target)
    errors << "#{redirect.fetch("id")}: canonical is not final" unless html.include?(%{rel="canonical" href="#{canonical}"})
  end

  redirects.each do |redirect|
    destinations = [redirect.fetch("to")] + redirect.dig("fragments", "mappings").values.select { _1.start_with?("/") }
    destinations.each do |destination|
      internal = split_internal(destination)
      next unless internal
      page = artifact(output, internal[0])
      if !page.file?
        errors << "#{redirect.fetch("id")}: destination artifact missing for #{destination}"
      elsif internal[1] && !read_utf8(page).match?(/\bid=["']#{Regexp.escape(internal[1])}["']/)
        errors << "#{redirect.fetch("id")}: destination artifact lacks ##{internal[1]}"
      end
    end
  end
end

abort(errors.map { "ERROR: #{_1}" }.join("\n")) unless errors.empty?
puts "URL redirects valid: #{redirects.length} inventoried, #{active.length} active#{output ? ", build artifacts verified" : ""}."
