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
GUIDE_ROOTS = %w[getting-started core-concepts optimization advanced production].freeze
GUIDE_EXCLUSIONS = [].freeze

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

errors << "src/_data/documentation_navigation.yml: version must be 1" unless manifest["version"] == 1
errors << "src/_data/documentation_navigation.yml: base_path must be /dspy.rb" unless manifest["base_path"] == "/dspy.rb"
errors << "src/_data/documentation_navigation.yml: label_policy is required" if manifest["label_policy"].to_s.strip.empty?

sections = manifest.fetch("sections", [])
items = manifest.fetch("items", [])
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
errors << "src/_data/documentation_navigation.yml: first must equal #{published.first&.dig("url")}" unless manifest["first"] == published.first&.dig("url")
errors << "src/_data/documentation_navigation.yml: last must equal #{published.last&.dig("url")}" unless manifest["last"] == published.last&.dig("url")
sections.each { |section| errors << "sections.#{section["id"]}: no published items (unintended orphan section)" unless published.any? { _1["section"] == section["id"] } }

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
    end

    top_links = links(element(html, "div", "data-doc-top-nav")).select { _1[0].key?("data-doc-section") }
    errors.concat expected_link_errors(path, "docs top navigation", top_links, sections)

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
    { "prev" => (index.zero? ? nil : published[index - 1]), "next" => (index == published.length - 1 ? nil : published[index + 1]) }.each do |rel, expected|
      actual = pager_links.find { _1[0]["rel"] == rel }
      if expected
        errors << "#{path}: #{rel} anchor must exactly bind href, label, rel, and data-doc-#{rel} for #{expected["url"]}" unless pager_link_valid?(actual, rel, expected)
      else
        errors << "#{path}: boundary must not render a #{rel} link" if actual
      end
    end
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
end

abort errors.join("\n") unless errors.empty?
puts "Documentation navigation valid: #{published.length} published, #{items.length - published.length} excluded; boundaries #{manifest["first"]} -> #{manifest["last"]}."
