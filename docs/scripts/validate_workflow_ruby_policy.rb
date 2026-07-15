#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "json"
require "pathname"
require "yaml"

module DocumentationQuality
  class WorkflowRubyPolicy
    SOLE_COMMAND = "ruby docs/scripts/check_documentation_quality.rb"
    BUN_VERSION = "1.3.14"
    BUN_INSTALL_COMMAND = "bun install --frozen-lockfile"

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
      workflows = {ruby_path => ruby_workflow, deploy_path => deploy_workflow}
      workflows.each_key do |path|
        text = path.read(encoding: "UTF-8")
        failures << "#{relative(path)}: must read Ruby from .ruby-version" unless text.include?("cat .ruby-version")
        failures << "#{relative(path)}: contains an unsupported hard-coded Ruby literal" if text.match?(/ruby-version:\s*['\"]?\d+\.\d+/)
      end
      workflows.each_value do |workflow|
        workflow.fetch("jobs").each_value do |job|
          Array(job["steps"]).select { _1["uses"] == "ruby/setup-ruby@v1" }.each do |step|
            version = step.dig("with", "ruby-version").to_s
            failures << "ruby/setup-ruby must use the .ruby-version step output" unless version.include?("steps.ruby-version.outputs.version")
          end
        end
      end

      test_job = ruby_workflow.fetch("jobs").fetch("test")
      matrix = test_job.dig("strategy", "matrix", "include")
      integration = matrix.find { _1["name"] == "DSPy Integration" }
      integration_command = integration.fetch("command").to_s
      unless integration_command.include?("spec/**/*_spec.rb") && !integration_command.match?(/exclude-pattern\s+['\"]spec\/documentation/)
        failures << "#{relative(ruby_path)}: DSPy Integration must keep full documentation specs in its command"
      end
      unless integration["documentation"] == "1"
        failures << "#{relative(ruby_path)}: DSPy Integration must opt into documentation bundle installation"
      end
      test_steps = test_job.fetch("steps")
      docs_bundle_steps = test_steps.select { _1["name"] == "Install documentation Ruby dependencies" }
      docs_bundle_step = docs_bundle_steps.first
      docs_bundle_valid = docs_bundle_steps.length == 1 &&
        docs_bundle_step["if"].to_s.include?("matrix.documentation == '1'") &&
        docs_bundle_step["working-directory"] == "docs" &&
        docs_bundle_step["run"].to_s.include?("bundle config set --local path ../vendor/bundle") &&
        docs_bundle_step["run"].to_s.include?("bundle install --jobs 4") &&
        test_steps.index(docs_bundle_step) < test_steps.index { _1["name"] == "Run tests" }
      unless docs_bundle_valid
        failures << "#{relative(ruby_path)}: test job must install cached docs/Gemfile dependencies before documentation-enabled matrix tests"
      end

      workflows.each do |path, workflow|
        steps = workflow.fetch("jobs").values.flat_map { Array(_1["steps"]) }
        bun_setup = steps.select { _1["uses"] == "oven-sh/setup-bun@v2" }
        unless bun_setup.length == 1 && bun_setup.first.dig("with", "bun-version").to_s == BUN_VERSION
          failures << "#{relative(path)}: setup-bun must pin Bun #{BUN_VERSION} exactly"
        end
        bun_installs = steps.filter_map { _1["run"] }.flat_map(&:lines).map(&:strip).grep(/\Abun install(?:\s|\z)/)
        unless bun_installs == [BUN_INSTALL_COMMAND]
          failures << "#{relative(path)}: must install Bun dependencies once with #{BUN_INSTALL_COMMAND.inspect}"
        end
      end

      package_path = @root.join("docs/package.json")
      package = JSON.parse(package_path.read(encoding: "UTF-8"))
      unless package["packageManager"] == "bun@#{BUN_VERSION}"
        failures << "#{relative(package_path)}: packageManager must be bun@#{BUN_VERSION}"
      end

      lock_path = @root.join("docs/bun.lock")
      failures << "#{relative(lock_path)}: text lockfile is required" unless lock_path.file?
      legacy_lock_path = @root.join("docs/bun.lockb")
      failures << "#{relative(legacy_lock_path)}: legacy binary lockfile must not be used" if legacy_lock_path.exist?

      bridgetown_path = @root.join("docs/bridgetown.config.yml")
      bridgetown = bridgetown_path.read(encoding: "UTF-8")
      unless bridgetown.lines.map(&:strip).include?("- bun.lock") && !bridgetown.include?("bun.lockb")
        failures << "#{relative(bridgetown_path)}: must exclude the text bun.lock and not the legacy binary lock"
      end

      docker_path = @root.join("docs/Dockerfile")
      docker = docker_path.read(encoding: "UTF-8")
      ruby_version = @root.join(".ruby-version").read(encoding: "UTF-8").strip
      unless docker.lines.map(&:strip).include?("FROM ruby:#{ruby_version}-slim")
        failures << "#{relative(docker_path)}: Ruby base image must match .ruby-version (#{ruby_version})"
      end
      failures << "#{relative(docker_path)}: Bun installer must pin bun-v#{BUN_VERSION}" unless docker.include?(%{bash -s "bun-v#{BUN_VERSION}"})
      failures << "#{relative(docker_path)}: must copy the text bun.lock" unless docker.include?("COPY package.json bun.lock ./")
      docker_installs = docker.lines.map(&:strip).grep(/\ARUN bun install(?:\s|\z)/)
      unless docker_installs == ["RUN #{BUN_INSTALL_COMMAND}"]
        failures << "#{relative(docker_path)}: must install Bun dependencies once with #{BUN_INSTALL_COMMAND.inspect}"
      end

      long_page_spec_path = @root.join("spec/documentation/long_page_dispositions_spec.rb")
      long_page_spec = long_page_spec_path.read(encoding: "UTF-8")
      if long_page_spec.match?(/["']rbenv["']/)
        failures << "#{relative(long_page_spec_path)}: documentation subprocesses must not invoke rbenv"
      end
      unless long_page_spec.include?('RbConfig.ruby, "-S", "bundle", "exec", "bridgetown", "build"')
        failures << "#{relative(long_page_spec_path)}: Bridgetown build must use the active Ruby and Bundler"
      end
      validator_invocations = long_page_spec.scan(/RbConfig\.ruby,\s*"scripts\/validate_long_page_dispositions\.rb"/).length
      unless validator_invocations == 4
        failures << "#{relative(long_page_spec_path)}: all four validator subprocesses must use RbConfig.ruby"
      end
      failures
    rescue JSON::ParserError, Psych::Exception, KeyError, TypeError, Errno::ENOENT => error
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
  puts "Workflow runtime policy valid: Ruby is authoritative, Bun is reproducible, documentation subprocesses are portable, and CI invokes the sole documentation command."
end
