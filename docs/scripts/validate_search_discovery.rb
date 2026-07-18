#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

output = Pathname(ARGV.fetch(0) do
  warn "Usage: validate_search_discovery.rb OUTPUT_DIRECTORY"
  exit 2
end).expand_path

errors = []

unless output.directory?
  warn "Search discovery output directory does not exist: #{output}"
  exit 2
end

def json_ld_documents(path, errors)
  html = path.read(encoding: "UTF-8")
  payloads = html.scan(%r{<script\s+type=["']application/ld\+json["'][^>]*>(.*?)</script>}mi).flatten

  payloads.filter_map do |payload|
    JSON.parse(payload)
  rescue JSON::ParserError => error
    errors << "#{path}: invalid JSON-LD: #{error.message}"
    nil
  end
end

def schema_types(documents)
  documents.flat_map do |document|
    Array(document["@graph"] || document).flat_map { |node| Array(node["@type"]) }
  end
end

html_paths = output.glob("**/*.html")
html_paths.each { |path| json_ld_documents(path, errors) }

home = output.join("index.html")
article = output.join("blog/articles/dspy-rb-1-0-0-release/index.html")
sitemap = output.join("sitemap.xml")

{home => %w[WebSite SoftwareSourceCode], article => %w[TechArticle]}.each do |path, required_types|
  unless path.file?
    errors << "missing rendered page: #{path}"
    next
  end

  types = schema_types(json_ld_documents(path, errors))
  required_types.each do |type|
    errors << "#{path}: missing #{type} JSON-LD" unless types.include?(type)
  end
end

if article.file?
  article_types = schema_types(json_ld_documents(article, errors))
  errors << "#{article}: unexpected FAQPage JSON-LD" if article_types.include?("FAQPage")
  errors << "#{article}: unexpected HowTo JSON-LD" if article_types.include?("HowTo")
end

if sitemap.file?
  sitemap_text = sitemap.read(encoding: "UTF-8")
  errors << "#{sitemap}: advertises the 404 page" if sitemap_text.match?(%r{<loc>[^<]+/404(?:\.html)?</loc>})
else
  errors << "missing rendered sitemap: #{sitemap}"
end

rendered_text = html_paths.map { |path| path.read(encoding: "UTF-8") }.join("\n")
errors << "rendered HTML references the removed schema logo" if rendered_text.include?("/images/logo.png")
errors << "rendered HTML claims an imprecise latest software version" if rendered_text.include?('"softwareVersion": "latest"')

if errors.empty?
  puts "Search discovery valid: #{html_paths.length} HTML files contain parseable, truthful schema and a clean sitemap."
else
  warn errors.join("\n")
  exit 1
end
