#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "optparse"
require "pathname"
require "yaml"

ROOT = Pathname.new(__dir__).join("..").expand_path
REPO = ROOT.join("..").cleanpath
MANIFEST = ROOT.join("src/_data/documentation_navigation.yml")
REDIRECTS = ROOT.join("editorial/url-redirects.yml")
ROUTE = %r{\A/(?:[a-z0-9][a-z0-9_-]*/)*\z}
STATUSES = %w[published unpublished draft planned].freeze
FORBIDDEN = %w[breadcrumb nav prev next nav_order order parent].freeze
GUIDE_ROOTS = %w[getting-started core-concepts optimization advanced production build].freeze
GUIDE_EXCLUSIONS = [].freeze
EXPECTED_SECTIONS = {
  "start" => ["Start", "/getting-started/"],
  "understand" => ["Understand", "/core-concepts/"],
  "build" => ["Build", "/build/"],
  "evaluate-optimize" => ["Evaluate / Optimize", "/optimization/"],
  "operate" => ["Operate", "/production/"],
  "extend" => ["Extend", "/advanced/"],
}.freeze
EXPECTED_OWNERS = {
  "/core-concepts/events/" => "operate",
  "/advanced/module-runtime-context/" => "operate",
  "/advanced/observability-interception/" => "operate",
  "/advanced/rails-integration/" => "operate",
  "/production/storage/" => "operate",
  "/production/registry/" => "operate",
  "/production/observability/" => "operate",
  "/production/troubleshooting/" => "operate",
  "/advanced/complex-types/" => "extend",
  "/advanced/custom-toolsets/" => "extend",
}.freeze

def frontmatter(path)
  match = File.binread(path).force_encoding(Encoding::UTF_8).match(/\A---\s*\n(.*?)\n---\s*\n/m)
  match ? YAML.safe_load(match[1], permitted_classes: [Date, Time]) || {} : {}
end

def source_route(path, data)
  return data["permalink"] if data["permalink"]

  relative = Pathname.new(path).relative_path_from(ROOT.join("src")).to_s
  "/#{relative.delete_suffix(".md").sub(%r{/index\z}, "")}/".gsub(%r{/+}, "/")
end

def artifact(output, route)
  output.join(route.delete_prefix("/"), "index.html")
end

def attrs(raw)
  raw.scan(/([:\w-]+)="([^"]*)"/).to_h
end

def text_content(raw)
  CGI.unescapeHTML(raw.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip)
end

def element(html, tag, attribute)
  html[/<#{tag}\b[^>]*\b#{Regexp.escape(attribute)}(?:="[^"]*")?[^>]*>(.*?)<\/#{tag}>/m, 1]
end

def balanced_element(html, tag, attribute)
  opening = html.match(/<#{tag}\b[^>]*\b#{Regexp.escape(attribute)}(?:="[^"]*")?[^>]*>/m)
  return unless opening

  tail = html[opening.begin(0)..]
  depth = 0
  tail.to_enum(:scan, %r{<\/?#{tag}\b[^>]*>}).each do
    token = Regexp.last_match
    depth += token[0].start_with?("</") ? -1 : 1
    return tail[0...token.end(0)] if depth.zero?
  end
  nil
end

def interactive_nesting_errors(markup)
  stack = []
  errors = []
  markup.to_s.scan(%r{<(/?)(a|button)\b[^>]*>}i) do |closing, tag|
    tag = tag.downcase
    if closing.empty?
      errors << "#{tag} nested inside #{stack.last}" unless stack.empty?
      stack << tag
    else
      match = stack.rindex(tag)
      stack.delete_at(match) if match
    end
  end
  errors
end

def links(fragment)
  fragment.to_s.scan(/<a\b([^>]*)>(.*?)<\/a>/m).map { |raw_attrs, body| [attrs(raw_attrs), text_content(body)] }
end

def expected_link_errors(path, surface, actual, expected)
  return ["#{path}: #{surface} expected #{expected.length} links, got #{actual.length}"] unless actual.length == expected.length

  actual.zip(expected).filter_map.with_index do |((actual_attrs, actual_label), expected_item), index|
    expected_href = "/dspy.rb#{expected_item.fetch("url")}"
    next if actual_attrs["href"] == expected_href && actual_label == expected_item.fetch("label")

    "#{path}: #{surface}[#{index}] expected #{expected_href.inspect} / #{expected_item.fetch("label").inspect}, got #{actual_attrs["href"].inspect} / #{actual_label.inspect}"
  end
end

def current_link_valid?(link, item)
  return false unless link

  attributes, label = link
  attributes["href"] == "/dspy.rb#{item.fetch("url")}" &&
    attributes["data-doc-path"] == item.fetch("url") &&
    attributes["aria-current"] == "page" &&
    label == item.fetch("label")
end

def pager_link_valid?(link, rel, item)
  return false unless link

  attributes, label = link
  expected_label = rel == "prev" ? "← #{item.fetch("label")}" : "#{item.fetch("label")} →"
  attributes["href"] == "/dspy.rb#{item.fetch("url")}" &&
    attributes["data-doc-#{rel}"] == item.fetch("url") &&
    attributes["rel"] == rel &&
    label == expected_label
end

def internal_exit?(url)
  url.start_with?("/")
end

def graph_for(manifest)
  graph = Hash.new { |hash, key| hash[key] = [] }
  published = manifest.fetch("items").select { _1["status"] == "published" }
  published.group_by { _1["traversal"] }.each do |traversal, members|
    next if traversal == "none"

    members.each_cons(2) { |left, right| graph[left.fetch("url")] << right.fetch("url") }
  end
  (published + manifest.fetch("resources", [])).each do |record|
    Array(record["exits"]).each { |exit| graph[record.fetch("url")] << exit.fetch("url") }
  end
  graph
end

def semantic_errors(manifest)
  errors = []
  sections = manifest.fetch("sections", [])
  items = manifest.fetch("items", [])
  published = items.select { _1["status"] == "published" }
  graph = graph_for(manifest)

  actual_sections = sections.to_h { [_1["id"], [_1["label"], _1["url"]]] }
  errors << "task buckets must be Start, Understand, Build, Evaluate / Optimize, Operate, Extend with stable landing routes" unless actual_sections == EXPECTED_SECTIONS
  EXPECTED_OWNERS.each do |url, section|
    owner = published.find { _1["url"] == url }&.dig("section")
    errors << "#{url}: expected task bucket #{section}, got #{owner.inspect}" unless owner == section
  end
  sections.each do |section|
    overview = published.find { _1["url"] == section["url"] && _1["section"] == section["id"] }
    errors << "#{section["id"]}: section landing is not a reachable published overview" unless overview
  end

  novice = %w[
    /getting-started/quick-start/
    /core-concepts/
    /core-concepts/signatures/
    /core-concepts/predictors/
    /core-concepts/modules/
    /core-concepts/examples/
    /core-concepts/toolsets/
    /advanced/stateful-agents/
  ]
  novice.each_cons(2) { |left, right| errors << "novice graph lacks #{left} -> #{right}" unless graph[left].include?(right) }
  quality_prefix = %w[/optimization/evaluation/ /optimization/benchmarking-raw-prompts/ /optimization/prompt-optimization/]
  quality_prefix.each_cons(2) { |left, right| errors << "quality graph lacks #{left} -> #{right}" unless graph[left].include?(right) }
  errors << "quality graph lacks Quick Start -> Evaluation" unless graph["/getting-started/quick-start/"].include?("/optimization/evaluation/")
  %w[/optimization/gepa/ /optimization/miprov2/].each do |optimizer|
    errors << "optimizer choice lacks /optimization/prompt-optimization/ -> #{optimizer}" unless graph["/optimization/prompt-optimization/"].include?(optimizer)
  end
  [
    ["/core-concepts/toolsets/", "https://github.com/vicentereig/dspy.rb/tree/main/examples/coffee-shop-agent"],
    ["https://github.com/vicentereig/dspy.rb/tree/main/examples/coffee-shop-agent", "/advanced/custom-toolsets/"],
    ["/advanced/custom-toolsets/", "/production/observability/"],
    ["https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/openai/README.md", "/getting-started/installation/"],
    ["/getting-started/installation/", "/advanced/"],
    ["/advanced/", "/advanced/module-runtime-context/"],
    ["/advanced/module-runtime-context/", "/llms-full.txt"],
  ].each { |left, right| errors << "context graph lacks #{left} -> #{right}" unless graph[left].include?(right) }

  known = published.map { _1["url"] } + manifest.fetch("resources", []).map { _1["url"] } + ["/llms-full.txt"]
  graph.each do |source, destinations|
    errors << "context graph source is orphaned: #{source}" unless known.include?(source)
    destinations.select { internal_exit?(_1) }.each do |destination|
      errors << "context graph has broken internal destination: #{destination}" unless known.include?(destination)
    end
  end
  errors
end

output = nil
OptionParser.new { _1.on("--output PATH") { |path| output = Pathname.new(path).expand_path } }.parse!
manifest = YAML.safe_load_file(MANIFEST)
redirect_manifest = YAML.safe_load_file(REDIRECTS)
active_redirects = redirect_manifest.fetch("redirects").select { _1["state"] == "active" }
errors = []

# Fault checks keep the element-local assertions from regressing into marker-only tests.
fault_item = { "url" => "/expected/", "label" => "Expected" }
valid_current = [{ "href" => "/dspy.rb/expected/", "data-doc-path" => "/expected/", "aria-current" => "page" }, "Expected"]
errors << "validator fault test: valid current link rejected" unless current_link_valid?(valid_current, fault_item)
%w[href data-doc-path aria-current].each do |field|
  mutation = [valid_current[0].merge(field => "wrong"), valid_current[1]]
  errors << "validator fault test: current link #{field} mutation escaped" if current_link_valid?(mutation, fault_item)
end
errors << "validator fault test: current link label mutation escaped" if current_link_valid?([valid_current[0], "Wrong"], fault_item)
valid_next = [{ "href" => "/dspy.rb/expected/", "data-doc-next" => "/expected/", "rel" => "next" }, "Expected →"]
errors << "validator fault test: valid pager link rejected" unless pager_link_valid?(valid_next, "next", fault_item)
errors << "validator fault test: pager partial label escaped" if pager_link_valid?([valid_next[0], "Expected"], "next", fault_item)
valid_dialog_markup = '<div id="mobile-menu" role="dialog" aria-label="Site navigation"><a href="/">Home</a><a href="/github">GitHub</a><button type="button">Close</button></div>'
nested_dialog_markup = '<div id="mobile-menu" role="dialog" aria-label="Site navigation"><a href="/">Home <a href="/github">GitHub</a></a><button type="button">Close</button></div>'
errors << "validator fault test: valid global mobile dialog rejected" unless interactive_nesting_errors(valid_dialog_markup).empty?
errors << "validator fault test: nested anchor mutation escaped" if interactive_nesting_errors(nested_dialog_markup).empty?

errors << "src/_data/documentation_navigation.yml: version must be 2" unless manifest["version"] == 2
errors << "src/_data/documentation_navigation.yml: base_path must be /dspy.rb" unless manifest["base_path"] == "/dspy.rb"
errors << "src/_data/documentation_navigation.yml: label_policy is required" if manifest["label_policy"].to_s.strip.empty?

sections = manifest.fetch("sections", [])
items = manifest.fetch("items", [])
resources = manifest.fetch("resources", [])
traversal_ids = manifest.fetch("traversals", []).map { _1["id"] }
errors << "src/_data/documentation_navigation.yml: traversal ids must be unique" unless traversal_ids.uniq.length == traversal_ids.length
errors << "src/_data/documentation_navigation.yml: traversal ids cannot include none" if traversal_ids.include?("none")
%w[id url source].each do |field|
  values = resources.map { _1[field] }
  errors << "src/_data/documentation_navigation.yml: resource #{field}s must be present and unique" unless values.all? { !_1.to_s.empty? } && values.uniq.length == values.length
end
section_ids = sections.map { _1["id"] }
errors << "src/_data/documentation_navigation.yml: duplicate section id" unless section_ids.uniq.length == section_ids.length
sections.each_with_index do |section, index|
  location = "src/_data/documentation_navigation.yml: sections[#{index}]"
  errors << "#{location}.id is required" if section["id"].to_s.empty?
  errors << "#{location}.label is required" if section["label"].to_s.strip.empty?
  errors << "#{location}.url must be a normalized root-relative route" unless section["url"].to_s.match?(ROUTE)
end

items.each_with_index do |item, index|
  location = "src/_data/documentation_navigation.yml: items[#{index}]"
  status = item["status"]
  source_value = item["source"].to_s
  errors << "#{location}.section references #{item["section"].inspect}" unless section_ids.include?(item["section"])
  errors << "#{location}.label is required" if item["label"].to_s.strip.empty?
  errors << "#{location}.url must be a normalized root-relative route without /dspy.rb" unless item["url"].to_s.match?(ROUTE) && !item["url"].start_with?("/dspy.rb/")
  errors << "#{location}.status must be one of #{STATUSES.join(", ")}" unless STATUSES.include?(status)
  errors << "#{location}.traversal must name a traversal or be none" unless (traversal_ids + ["none"]).include?(item["traversal"])
  errors << "#{location}.source is required for #{status}" if status != "planned" && source_value.empty?
  errors << "#{location}.source must be absent while status is planned" if status == "planned" && !source_value.empty?
  next if source_value.empty?

  source = REPO.join(source_value)
  errors << "#{location}.source does not exist: #{source_value}" unless source.file?
  next unless source.file?

  data = frontmatter(source)
  errors << "#{source_value}: layout must be docs" unless data["layout"] == "docs"
  FORBIDDEN.each { |key| errors << "#{source_value}: forbidden navigation field #{key}" if data.key?(key) }
  errors << "#{location}.url #{item["url"]} does not match source route #{source_route(source, data)}" unless source_route(source, data) == item["url"]
  if status == "published" && data["published"] == false
    errors << "#{location}.status is published but #{source_value} has published: false"
  elsif %w[unpublished draft].include?(status) && data["published"] != false
    errors << "#{location}.status #{status} requires published: false in #{source_value}"
  end
  if status == "unpublished"
    redirect = active_redirects.find { _1["from"] == item["url"] && _1["source"] == source_value }
    errors << "#{location}: unpublished route must be owned by an active redirect with the same source" unless redirect
  end
end

known_exit_urls = items.select { _1["status"] == "published" }.map { _1["url"] } + resources.map { _1["url"] } + ["/llms-full.txt"]
(items + resources).each_with_index do |record, index|
  Array(record["exits"]).each_with_index do |exit, exit_index|
    location = "navigation record #{index} exits[#{exit_index}]"
    errors << "#{location}.label is required" if exit["label"].to_s.strip.empty?
    url = exit["url"].to_s
    errors << "#{location}.url must be an internal path or https URL" unless url.start_with?("/") || url.match?(%r{\Ahttps://[^\s]+\z})
    errors << "#{location}.url points outside the documentation graph: #{url}" if internal_exit?(url) && !known_exit_urls.include?(url)
  end
end
resources.each do |resource|
  source = REPO.join(resource.fetch("source"))
  errors << "#{resource["id"]}: resource source is missing" unless source.file?
  next unless source.file?

  body = source.read
  Array(resource["exits"]).each do |exit|
    public_url = exit.fetch("url").start_with?("/") ? "https://oss.vicente.services/dspy.rb#{exit.fetch("url")}" : exit.fetch("url")
    errors << "#{resource["id"]}: source does not expose contextual exit #{public_url}" unless body.include?(public_url)
  end
end

%w[url source].each do |field|
  values = items.filter_map { _1[field] }
  duplicates = values.group_by(&:itself).select { _2.length > 1 }.keys
  errors << "src/_data/documentation_navigation.yml: duplicate item #{field}: #{duplicates.join(", ")}" unless duplicates.empty?
end

guide_sources = GUIDE_ROOTS.flat_map { |root| Dir[ROOT.join("src", root, "**/*.md")] }
  .map { Pathname.new(_1).relative_path_from(REPO).to_s }
  .reject { GUIDE_EXCLUSIONS.include?(_1) }
  .select { frontmatter(REPO.join(_1))["layout"] == "docs" }
  .sort
listed_sources = items.filter_map { _1["source"] }.sort
(guide_sources - listed_sources).each { |source| errors << "#{source}: docs page is missing from navigation manifest" }
(listed_sources - guide_sources).each { |source| errors << "#{source}: navigation source is outside the recursive guide inventory" }

published = items.select { _1["status"] == "published" }
sections.each { |section| errors << "sections.#{section["id"]}: no published items (unintended orphan section)" unless published.any? { _1["section"] == section["id"] } }
errors.concat semantic_errors(manifest)

# These mutations prove the graph checks fail on a broken prerequisite edge,
# task-bucket reassignment, and unreachable section overview.
faults = {
  "prerequisite edge" => lambda { |copy| copy["items"].find { _1["url"] == "/core-concepts/examples/" }["traversal"] = "none" },
  "bucket ownership" => lambda { |copy| copy["items"].find { _1["url"] == "/core-concepts/events/" }["section"] = "extend" },
  "overview reachability" => lambda { |copy| copy["items"].find { _1["url"] == "/build/" }["status"] = "draft" },
}
faults.each do |name, mutation|
  copy = Marshal.load(Marshal.dump(manifest))
  mutation.call(copy)
  errors << "validator fault test: #{name} mutation escaped" if semantic_errors(copy).empty?
end

legacy_components = %w[src/_components/navigation.liquid src/_components/mobile_menu.liquid src/_components/site_header.liquid]
legacy_components.each do |relative|
  body = ROOT.join(relative).read
  errors << "#{relative}: substring current-page matching is forbidden" if body.include?("page.url contains")
  sections.each { |section| errors << "#{relative}: hard-coded section route #{section["url"]}" if body.include?("'#{section["url"]}'") }
end
%w[src/_layouts/docs.liquid src/_layouts/default.liquid].each do |relative|
  errors << "#{relative}: index.js must be owned only by src/_components/head.liquid" if ROOT.join(relative).read.include?("/_bridgetown/static/js/index.js")
end

js = ROOT.join("frontend/javascript/mobile-navigation.js").read
{
  "capture triggering focus" => "returnFocus = document.activeElement",
  "focus menu on open" => "firstFocusable?.focus()",
  "restore triggering focus" => "returnFocus?.focus()",
  "trap Tab" => "e.key === 'Tab'",
  "trap Shift+Tab" => "e.shiftKey",
  "exclude hidden focus controls" => "!element.closest('[hidden], .hidden')",
  "close on Escape" => "e.key === 'Escape'",
}.each { |contract, token| errors << "frontend/javascript/mobile-navigation.js: missing #{contract}" unless js.include?(token) }
errors << "frontend/javascript/mobile-navigation.js: disclosure click handler must bind exactly once" unless js.scan("button.addEventListener('click'").length == 1

if output
  expected_paths = published.map { _1["url"] }
  published.each_with_index do |item, index|
    path = artifact(output, item["url"])
    unless path.file?
      errors << "#{path}: missing production artifact for items[#{items.index(item)}].url"
      next
    end

    html = File.binread(path).force_encoding(Encoding::UTF_8)
    script_tags = html.scan(/<script\b[^>]*\bsrc="[^"]*\/_bridgetown\/static\/js\/index\.js"[^>]*><\/script>/)
    errors << "#{path}: expected exactly one index.js script tag, got #{script_tags.length}" unless script_tags.length == 1
    ids = html.scan(/\bid="([^"]+)"/).flatten
    duplicate_ids = ids.group_by(&:itself).select { _2.length > 1 }.keys
    errors << "#{path}: duplicate element IDs #{duplicate_ids.join(", ")}" unless duplicate_ids.empty?

    %w[desktop mobile].each do |mode|
      sidebar = html[/<nav\b[^>]*data-doc-sidebar="#{mode}"[^>]*>(.*?)<\/nav>/m, 1].to_s
      sidebar_links = links(sidebar).select { _1[0].key?("data-doc-path") }
      errors.concat expected_link_errors(path, "#{mode} sidebar", sidebar_links, published)
      current = sidebar_links.select { _1[0]["aria-current"] == "page" }
      errors << "#{path}: #{mode} sidebar current anchor must exactly bind href, label, data-doc-path, and aria-current for #{item["url"]}" unless current.length == 1 && current_link_valid?(current.first, item)
      buttons = sidebar.scan(/<button\b([^>]*)>/).map { attrs(_1[0]) }.select { _1.key?("data-dropdown-toggle") }
      errors << "#{path}: #{mode} expected #{sections.length} disclosure buttons" unless buttons.length == sections.length
      buttons.each do |button|
        target = button["data-dropdown-toggle"]
        errors << "#{path}: #{mode} disclosure #{target.inspect} aria-controls mismatch" unless button["aria-controls"] == target
        errors << "#{path}: #{mode} disclosure target ##{target} must exist exactly once" unless ids.count(target) == 1
      end
      current_sections = buttons.select { _1["aria-current"] == "location" }
      errors << "#{path}: #{mode} sidebar must mark exactly one current task bucket" unless current_sections.length == 1 && current_sections.first["data-dropdown-toggle"].include?(item["section"])
    end

    top_links = links(element(html, "div", "data-doc-top-nav")).select { _1[0].key?("data-doc-section") }
    errors.concat expected_link_errors(path, "docs top navigation", top_links, sections)
    active_top = top_links.select { _1[0]["aria-current"] == "location" }
    errors << "#{path}: docs top navigation must mark #{item["section"]} as current" unless active_top.length == 1 && active_top.first[0]["data-doc-section"] == item["section"]

    breadcrumb = element(html, "nav", "data-doc-breadcrumb").to_s
    breadcrumb_links = links(breadcrumb)
    expected_section = sections.find { _1["id"] == item["section"] }
    home_crumb = breadcrumb_links.first
    errors << "#{path}: breadcrumb home link must be /dspy.rb/ with aria-label Home" unless home_crumb && home_crumb[0]["href"] == "/dspy.rb/" && home_crumb[0]["aria-label"] == "Home"
    section_crumbs = breadcrumb_links.drop(1)
    expected_section_crumbs = item["url"] == expected_section["url"] ? [] : [["/dspy.rb#{expected_section["url"]}", expected_section["label"]]]
    actual_section_crumbs = section_crumbs.map { |attributes, label| [attributes["href"], label] }
    errors << "#{path}: breadcrumb section expected #{expected_section_crumbs.inspect}, got #{actual_section_crumbs.inspect}" unless actual_section_crumbs == expected_section_crumbs
    current_crumb = breadcrumb.scan(/<span\b([^>]*)>(.*?)<\/span>/m).map { |a, body| [attrs(a), text_content(body)] }.find { _1[0].key?("data-doc-path") }
    errors << "#{path}: breadcrumb current item must be #{item["url"]} / #{item["label"]}" unless current_crumb && current_crumb[0]["data-doc-path"] == item["url"] && current_crumb[1] == item["label"]

    pager_links = links(element(html, "nav", "data-doc-prev-next"))
    traversal = item["traversal"]
    traversal_items = published.select { _1["traversal"] == traversal }
    traversal_index = traversal_items.index(item)
    expected_pager = if traversal == "none"
                       { "prev" => nil, "next" => nil }
                     else
                       { "prev" => (traversal_index.zero? ? nil : traversal_items[traversal_index - 1]), "next" => (traversal_index == traversal_items.length - 1 ? nil : traversal_items[traversal_index + 1]) }
                     end
    expected_pager.each do |rel, expected|
      actual = pager_links.find { _1[0]["rel"] == rel }
      if expected
        errors << "#{path}: #{rel} anchor must exactly bind href, label, rel, and data-doc-#{rel} for #{expected["url"]}" unless pager_link_valid?(actual, rel, expected)
      else
        errors << "#{path}: boundary must not render a #{rel} link" if actual
      end
    end

    context_links = links(element(html, "nav", "data-doc-context-exits"))
    expected_exits = Array(item["exits"])
    if context_links.length != expected_exits.length
      errors << "#{path}: contextual exits expected #{expected_exits.length}, got #{context_links.length}"
    else
      context_links.zip(expected_exits).each do |(attributes, label), exit|
        expected_href = if exit.fetch("url").start_with?("https://")
                          exit.fetch("url")
                        else
                          "/dspy.rb#{exit.fetch("url")}"
                        end
        errors << "#{path}: contextual exit mismatch for #{exit.fetch("url")}" unless attributes["href"] == expected_href && attributes["data-doc-exit"] == exit.fetch("url") && label == exit.fetch("label")
      end
    end
    dialog = html[/<div\b[^>]*\bid="mobile-menu"[^>]*>/]
    errors << "#{path}: mobile dialog requires an accessible name" unless dialog && attrs(dialog)["aria-label"].to_s.length.positive?
  end

  items.reject { _1["status"] == "published" }.each do |item|
    next if item["status"] == "planned"

    path = artifact(output, item["url"])
    redirect = active_redirects.find { _1["from"] == item["url"] && _1["source"] == item["source"] }
    if redirect
      errors << "#{path}: active redirect artifact missing for #{item["url"]}" unless path.file? && File.binread(path).include?("data-redirect-id=\"#{redirect["id"]}\"")
    elsif path.file?
      errors << "#{path}: #{item["status"]} page rendered without an active redirect owner"
    end
  end

  root_html = File.binread(output.join("index.html")).force_encoding(Encoding::UTF_8)
  root_scripts = root_html.scan(/<script\b[^>]*\bsrc="[^"]*\/_bridgetown\/static\/js\/index\.js"[^>]*><\/script>/)
  errors << "#{output.join("index.html")}: expected exactly one index.js script tag, got #{root_scripts.length}" unless root_scripts.length == 1
  %w[data-global-top-nav data-global-mobile-nav].each do |surface|
    global_links = links(element(root_html, "div", surface)).select { _1[0].key?("data-doc-section") }
    errors.concat expected_link_errors(output.join("index.html"), surface, global_links, sections)
  end

  global_surfaces = {
    "home" => output.join("index.html"),
    "blog" => output.join("blog/index.html"),
    "default" => output.join("404.html"),
  }
  global_surfaces.each do |name, path|
    unless path.file?
      errors << "#{path}: missing #{name} global-navigation artifact"
      next
    end

    html = File.binread(path).force_encoding(Encoding::UTF_8)
    ids = html.scan(/\bid="([^"]+)"/).flatten
    duplicates = ids.group_by(&:itself).select { _2.length > 1 }.keys
    errors << "#{path}: duplicate element IDs #{duplicates.join(", ")}" unless duplicates.empty?

    dialog = balanced_element(html, "div", 'id="mobile-menu"')
    if dialog.nil?
      errors << "#{path}: global mobile dialog is missing or unbalanced"
      next
    end
    dialog_open = dialog[/\A<div\b[^>]*>/]
    dialog_attrs = attrs(dialog_open.to_s)
    errors << "#{path}: global mobile dialog requires role=dialog and aria-modal=true" unless dialog_attrs["role"] == "dialog" && dialog_attrs["aria-modal"] == "true"
    errors << "#{path}: global mobile dialog requires an accessible name" if dialog_attrs["aria-label"].to_s.strip.empty? && dialog_attrs["aria-labelledby"].to_s.strip.empty?
    nesting = interactive_nesting_errors(dialog)
    errors << "#{path}: global mobile dialog has invalid interactive nesting: #{nesting.join(", ")}" unless nesting.empty?

    dialog_links = links(dialog)
    dialog_links.each_with_index do |(attributes, label), link_index|
      errors << "#{path}: global mobile dialog link[#{link_index}] lacks href" if attributes["href"].to_s.strip.empty?
      errors << "#{path}: global mobile dialog link[#{link_index}] lacks an accessible name" if label.to_s.strip.empty? && attributes["aria-label"].to_s.strip.empty?
    end
    dialog.scan(/<button\b([^>]*)>(.*?)<\/button>/m).each_with_index do |(raw_attrs, body), button_index|
      attributes = attrs(raw_attrs)
      errors << "#{path}: global mobile dialog button[#{button_index}] must use type=button" unless attributes["type"] == "button"
      errors << "#{path}: global mobile dialog button[#{button_index}] lacks an accessible name" if text_content(body).empty? && attributes["aria-label"].to_s.strip.empty?
    end
    mobile_links = links(element(dialog, "div", "data-global-mobile-nav")).select { _1[0].key?("data-doc-section") }
    errors.concat expected_link_errors(path, "#{name} global mobile navigation", mobile_links, sections)
    current_sections = mobile_links.select { _1[0].key?("aria-current") }
    errors << "#{path}: non-document global mobile navigation must not claim a current task bucket" unless current_sections.empty?

    opener = html[/<button\b[^>]*\bid="mobile-menu-button"[^>]*>/]
    opener_attrs = attrs(opener.to_s)
    errors << "#{path}: global mobile menu opener must control mobile-menu" unless opener_attrs["aria-controls"] == "mobile-menu" && opener_attrs["aria-expanded"] == "false"
    errors << "#{path}: global mobile menu opener requires an accessible name" if opener_attrs["aria-label"].to_s.strip.empty?
  end
end

abort errors.join("\n") unless errors.empty?
puts "Documentation navigation valid: #{published.length} published, #{items.length - published.length} excluded; #{traversal_ids.length} task traversals and #{sections.length} reader buckets."
