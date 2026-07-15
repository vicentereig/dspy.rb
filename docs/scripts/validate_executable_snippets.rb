#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"

module DocumentationQuality
  class ExecutableSnippets
    EXPECTED_SPECS = %w[
      spec/documentation/quick_start_spec.rb
      spec/documentation/toolsets_spec.rb
      spec/documentation/long_page_examples_spec.rb
    ].freeze
    MARKER = /<!-- ([a-z0-9][a-z0-9-]*) -->/.freeze
    LIVE_TOKEN = /(?:sk-(?!your-key-here)[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|(?:api|secret)[_-]?key\s*[:=]\s*["'][^"']{12,})/i.freeze

    def initialize(root:, registry: nil)
      @root = Pathname(root).expand_path
      @registry = registry ? Pathname(registry).expand_path : @root.join("docs/editorial/executable-snippets.yml")
    end

    def errors
      document = YAML.safe_load_file(@registry, aliases: false)
      snippets = document.fetch("snippets")
      specs = document.fetch("specs")
      failures = []
      failures << "#{relative(@registry)}: version must be 1" unless document["version"] == 1
      failures << "#{relative(@registry)}: specs must be exactly #{EXPECTED_SPECS.join(', ')}" unless specs == EXPECTED_SPECS
      EXPECTED_SPECS.each do |spec|
        failures << "#{spec}: designated snippet spec is missing" unless @root.join(spec).file?
        next unless @root.join(spec).file?

        spec_text = @root.join(spec).read(encoding: "UTF-8")
        network_guard = spec_text.include?("a_request(:any, /.*/)") || spec_text.include?("network access attempted")
        failures << "#{spec}: must prove selected examples cannot make a network request" unless network_guard
      end

      identities = snippets.map { |entry| [entry["source"], entry["marker"]] }
      failures << "#{relative(@registry)}: source/marker entries must be unique" unless identities.uniq.length == identities.length

      snippets.each_with_index do |entry, index|
        context = "#{relative(@registry)}: snippets[#{index}]"
        %w[source marker language spec].each do |field|
          failures << "#{context}: missing #{field}" if entry[field].to_s.empty?
        end
        failures << "#{context}: spec is not designated: #{entry['spec']}" unless specs.include?(entry["spec"])
        source = @root.join(entry.fetch("source"))
        unless source.file?
          failures << "#{context}: source is missing: #{entry['source']}"
          next
        end
        text = source.read(encoding: "UTF-8")
        pattern = /<!--\s*#{Regexp.escape(entry.fetch('marker'))}\s*-->\s*\r?\n[ \t]{0,3}```#{Regexp.escape(entry.fetch('language'))}[ \t]*\r?\n(.*?)\r?\n[ \t]{0,3}```[ \t]*(?:\r?\n|\z)/m
        selected = text.scan(pattern).flatten
        count = selected.length
        failures << "#{entry['source']}: marker #{entry['marker']} must select exactly one #{entry['language']} fence, got #{count}" unless count == 1
        selected.each do |body|
          failures << "#{entry['source']}:#{entry['marker']}: selected fence contains a live-looking credential" if body.match?(LIVE_TOKEN)
          failures << "#{entry['source']}:#{entry['marker']}: selected fence must not depend on Rails" if body.match?(/\bRails(?:\.|::)/)
          failures << "#{entry['source']}:#{entry['marker']}: selected fence must not invoke VCR" if body.match?(/\bVCR\./)
        end
        spec_text = @root.join(entry.fetch("spec")).read(encoding: "UTF-8")
        failures << "#{entry['spec']}: does not reference marker #{entry['marker']}" unless spec_text.include?(entry["marker"])
      end

      actual_markers = Dir[@root.join("docs/src/**/*.{md,erb}")].flat_map do |path|
        relative_path = Pathname(path).relative_path_from(@root).to_s
        File.read(path, encoding: "UTF-8").scan(MARKER).flatten.map { |marker| [relative_path, marker] }
      end
      missing = actual_markers - identities
      stale = identities - actual_markers
      missing.each { |source, marker| failures << "#{source}: unregistered executable marker #{marker}" }
      stale.each { |source, marker| failures << "#{source}: registered marker is missing: #{marker}" }
      failures
    rescue Psych::Exception, KeyError, TypeError => error
      ["#{relative(@registry)}: cannot parse executable snippet registry: #{error.message}"]
    end

    private

    def relative(path)
      path.relative_path_from(@root).to_s
    rescue ArgumentError
      path.to_s
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = Pathname(__dir__).join("../..").expand_path
  registry = nil
  OptionParser.new do |options|
    options.on("--root PATH") { |path| root = Pathname(path).expand_path }
    options.on("--registry PATH") { |path| registry = Pathname(path).expand_path }
  end.parse!
  validator = DocumentationQuality::ExecutableSnippets.new(root: root, registry: registry)
  errors = validator.errors
  abort(errors.map { "ERROR: #{_1}" }.join("\n")) unless errors.empty?
  puts "Executable snippet registry valid: #{DocumentationQuality::ExecutableSnippets::EXPECTED_SPECS.length} designated spec files; unmarked fences are not executed."
end
