#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"

module DocumentationQuality
  class LlmsReferences
    SOURCE_FILES = %w[docs/src/llms.txt.erb docs/src/llms-full.txt.erb].freeze
    OUTPUT_FILES = %w[llms.txt llms-full.txt].freeze
    REQUIRED_ROUTES = %w[
      /getting-started/quick-start/
      /getting-started/packages/
      /core-concepts/toolsets/
      /advanced/concurrent-predictions/
      /advanced/module-lifecycle-callbacks/
      /production/score-reporting/
    ].freeze
    RESIDUE = /<%|\{\{|\{%|&(?:amp|apos|gt|lt|quot|#\d+|#x[0-9a-f]+);/i.freeze

    def initialize(root:, output: nil)
      @root = Pathname(root).expand_path
      @output = output ? Pathname(output).expand_path : @root.join("docs/output")
    end

    def errors
      failures = []
      canonical = canonical_material(failures)
      public_packages, internal_packages = package_names(failures)

      SOURCE_FILES.each do |relative|
        path = @root.join(relative)
        unless path.file?
          failures << "#{relative}: source reference is missing"
          next
        end
        text = path.read(encoding: "UTF-8")
        validate_common(failures, relative, text, canonical)
        failures << "#{relative}: package rows must derive from package_capabilities" unless text.include?("package_capabilities")
        failures << "#{relative}: contains Liquid residue" if text.match?(/\{\{|\{%/)
        failures << "#{relative}: contains HTML entity residue" if text.match?(/&(?:amp|apos|gt|lt|quot|#\d+|#x[0-9a-f]+);/i)
      end

      newest_source = SOURCE_FILES.map { @root.join(_1) }.select(&:file?).map(&:mtime).max
      OUTPUT_FILES.each do |name|
        path = @output.join(name)
        unless path.file?
          failures << "#{path}: rendered reference is missing"
          next
        end
        text = path.read(encoding: "UTF-8")
        validate_common(failures, path.to_s, text, canonical)
        failures << "#{path}: contains template or HTML entity residue" if text.match?(RESIDUE)
        failures << "#{path}: output predates an llms source; run the production build" if newest_source && path.mtime < newest_source
        public_packages.each { |gem| failures << "#{path}: public package is missing: #{gem}" unless text.include?("`#{gem}`") }
        internal_packages.each { |gem| failures << "#{path}: internal package leaked: #{gem}" if text.include?("`#{gem}`") }
      end
      failures
    rescue Psych::Exception, KeyError, TypeError => error
      ["llms reference configuration failed: #{error.message}"]
    end

    private

    def canonical_material(failures)
      path = @root.join("docs/src/getting-started/quick-start.md")
      unless path.file?
        failures << "docs/src/getting-started/quick-start.md: canonical source is missing"
        return []
      end
      source = path.read(encoding: "UTF-8")
      markers = {
        "quick-start-gemfile" => "ruby",
        "quick-start-install-command" => "bash",
        "quick-start-api-key-command" => "bash",
        "quick-start-program" => "ruby",
        "quick-start-run-command" => "bash"
      }
      markers.filter_map do |marker, language|
        match = source.match(/<!-- #{Regexp.escape(marker)} -->\s*```#{language}\n(.*?)\n```/m)
        if match
          [marker, match[1]]
        else
          failures << "docs/src/getting-started/quick-start.md: canonical marker/fence is missing: #{marker}"
          nil
        end
      end
    end

    def package_names(failures)
      path = @root.join("docs/src/_data/package_capabilities.yml")
      unless path.file?
        failures << "docs/src/_data/package_capabilities.yml: package matrix is missing"
        return [[], []]
      end
      packages = YAML.safe_load_file(path, aliases: false).fetch("packages")
      ["public", "internal"].map { |visibility| packages.select { _1["visibility"] == visibility }.map { _1.fetch("gem") } }
    end

    def validate_common(failures, label, text, canonical)
      REQUIRED_ROUTES.each do |route|
        absolute = "https://oss.vicente.services/dspy.rb#{route}"
        failures << "#{label}: canonical route is missing: #{absolute}" unless text.include?(absolute)
      end
      canonical.each do |marker, material|
        failures << "#{label}: canonical Quick Start material is stale: #{marker}" unless text.include?(material)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = Pathname(__dir__).join("../..").expand_path
  output = nil
  OptionParser.new do |options|
    options.on("--root PATH") { |path| root = Pathname(path).expand_path }
    options.on("--output PATH") { |path| output = Pathname(path).expand_path }
  end.parse!
  validator = DocumentationQuality::LlmsReferences.new(root: root, output: output)
  errors = validator.errors
  abort(errors.map { "ERROR: #{_1}" }.join("\n")) unless errors.empty?
  puts "LLM references valid: canonical Quick Start, designated routes, packages, sources, and fresh rendered output agree."
end
