#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "pathname"
require "yaml"

module DocumentationQuality
  class WorkflowRubyPolicy
    SOLE_COMMAND = "ruby docs/scripts/check_documentation_quality.rb"

    def initialize(root:)
      @root = Pathname(root).expand_path
    end

    def errors
      failures = []
      ruby_path = @root.join(".github/workflows/ruby.yml")
      deploy_path = @root.join(".github/workflows/deploy.yml")
      ruby_workflow = YAML.safe_load_file(ruby_path, aliases: true)
      deploy_workflow = YAML.safe_load_file(deploy_path, aliases: true)
      docs_job = ruby_workflow.fetch("jobs").fetch("docs-quality")
      commands = docs_job.fetch("steps").filter_map { _1["run"] }.join("\n")
      failures << "#{relative(ruby_path)}: docs-quality must invoke the sole command exactly once" unless commands.scan(SOLE_COMMAND).length == 1
      [ruby_path, deploy_path].each do |path|
        text = path.read(encoding: "UTF-8")
        failures << "#{relative(path)}: must read Ruby from .ruby-version" unless text.include?("cat .ruby-version")
        failures << "#{relative(path)}: contains an unsupported hard-coded Ruby literal" if text.match?(/ruby-version:\s*['\"]?\d+\.\d+/)
      end
      [ruby_workflow, deploy_workflow].each do |workflow|
        workflow.fetch("jobs").each_value do |job|
          Array(job["steps"]).select { _1["uses"] == "ruby/setup-ruby@v1" }.each do |step|
            version = step.dig("with", "ruby-version").to_s
            failures << "ruby/setup-ruby must use the .ruby-version step output" unless version.include?("steps.ruby-version.outputs.version")
          end
        end
      end
      failures
    rescue Psych::Exception, KeyError, TypeError => error
      ["workflow Ruby policy could not be parsed: #{error.message}"]
    end

    private

    def relative(path)
      path.relative_path_from(@root).to_s
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = Pathname(__dir__).join("../..").expand_path
  OptionParser.new { _1.on("--root PATH") { |path| root = Pathname(path).expand_path } }.parse!
  validator = DocumentationQuality::WorkflowRubyPolicy.new(root: root)
  errors = validator.errors
  abort(errors.map { "ERROR: #{_1}" }.join("\n")) unless errors.empty?
  puts "Workflow Ruby policy valid: .ruby-version is authoritative and CI invokes the sole documentation command."
end
