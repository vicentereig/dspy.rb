#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "pathname"
require "rbconfig"

module DocumentationQuality
  class Pipeline
    Step = Data.define(:name, :command, :chdir, :environment)

    def initialize(root: Pathname(__dir__).join("../..").expand_path, stdout: $stdout, stderr: $stderr)
      @root = Pathname(root).expand_path
      @docs = @root.join("docs")
      @stdout = stdout
      @stderr = stderr
    end

    def run
      started = monotonic
      pipeline_steps = steps
      pipeline_steps.each_with_index do |step, index|
        header = "[docs-quality #{index + 1}/#{pipeline_steps.length}] #{step.name}"
        @stdout.puts("\n#{'=' * header.length}\n#{header}\n#{'=' * header.length}")
        status, output, duration = execute(step)
        @stdout.print(output)
        @stdout.puts("[completed in #{format('%.2f', duration)}s]") if status.success?
        next if status.success?

        @stderr.puts("\nDocumentation quality failed at step #{index + 1}: #{step.name}")
        @stderr.puts("cwd: #{step.chdir}")
        @stderr.puts("command: #{step.command.join(' ')}")
        @stderr.puts("exit: #{status.exitstatus}")
        return status.exitstatus || 1
      end
      @stdout.puts("\nDocumentation quality passed in #{format('%.2f', monotonic - started)}s (#{steps.length} steps).")
      0
    rescue Errno::ENOENT => error
      @stderr.puts("Documentation quality could not start a required command: #{error.message}")
      127
    end

    private

    def steps
      ruby = RbConfig.ruby
      scripts = @docs.join("scripts")
      source = [
        ["Source corpus and frontmatter", [ruby, scripts.join("validate_public_doc_corpus.rb").to_s]],
        ["Source navigation", [ruby, scripts.join("validate_documentation_navigation.rb").to_s]],
        ["Source redirects, chains, loops, and fragments", [ruby, scripts.join("validate_url_redirects.rb").to_s]],
        ["Semantic anchor ledger", [ruby, scripts.join("validate_semantic_anchors.rb").to_s]],
        ["Corpus completion audit", [ruby, scripts.join("validate_completion_audit.rb").to_s]],
        ["Long-page dispositions", [ruby, scripts.join("validate_long_page_dispositions.rb").to_s]],
        ["Source package capability matrix", [ruby, scripts.join("validate_package_capabilities.rb").to_s, "--source-only"]],
        ["House voice structural calibration", [ruby, scripts.join("validate_house_voice_charter.rb").to_s]],
        ["Economy audit (informational findings; parse/configuration failures are fatal)", [ruby, scripts.join("audit_economical_writing.rb").to_s]],
        ["Workflow Ruby and sole-command policy", [ruby, scripts.join("validate_workflow_ruby_policy.rb").to_s]],
        ["Executable snippet marker registry", [ruby, scripts.join("validate_executable_snippets.rb").to_s]]
      ].map { |name, command| Step.new(name:, command:, chdir: @root.to_s, environment: {}) }
      source.insert(
        3,
        Step.new(
          name: "Redirect script escaping safety",
          command: [ruby, "-S", "bundle", "exec", "ruby", "scripts/test_url_redirect_safety.rb"],
          chdir: @docs.to_s,
          environment: production_environment
        )
      )

      rspec = [ruby, "-S", "bundle", "exec", "rspec", "--format", "documentation"]
      behavioral = Step.new(
        name: "Documentation validator behavioral faults",
        command: rspec + ["spec/documentation/documentation_quality_validators_spec.rb"],
        chdir: @root.to_s,
        environment: test_environment
      )
      snippets = Step.new(
        name: "Designated deterministic snippet specs only",
        command: rspec + %w[
          spec/documentation/quick_start_spec.rb
          spec/documentation/toolsets_spec.rb
          spec/documentation/long_page_examples_spec.rb
        ],
        chdir: @root.to_s,
        environment: test_environment
      )
      build = [
        Step.new(name: "Clean documentation output once", command: %w[bun run clean], chdir: @docs.to_s, environment: production_environment),
        Step.new(name: "Build production site and assets once", command: %w[bun run build], chdir: @docs.to_s, environment: production_environment)
      ]
      rendered = [
        ["Rendered navigation", [ruby, scripts.join("validate_documentation_navigation.rb").to_s, "--output", @docs.join("output").to_s]],
        ["Rendered redirects and fragments", [ruby, scripts.join("validate_url_redirects.rb").to_s, "--output", @docs.join("output").to_s]],
        ["Rendered long pages, sitemap, and LLM references", [ruby, scripts.join("validate_long_page_dispositions.rb").to_s, "--output", @docs.join("output").to_s]],
        ["Rendered package capability matrix", [ruby, scripts.join("validate_package_capabilities.rb").to_s, "--output", @docs.join("output").to_s]],
        ["Rendered internal links and anchors", [ruby, scripts.join("validate_internal_links.rb").to_s, "--output", @docs.join("output").to_s]],
        ["LLM source-to-fresh-output consistency", [ruby, scripts.join("validate_llms_references.rb").to_s, "--output", @docs.join("output").to_s]]
      ].map { |name, command| Step.new(name:, command:, chdir: @root.to_s, environment: production_environment) }

      source + [behavioral, snippets] + build + rendered
    end

    def execute(step)
      output = +""
      started = monotonic
      status = nil
      Open3.popen2e(step.environment, *step.command, chdir: step.chdir) do |stdin, stream, wait|
        stdin.close
        stream.each do |chunk|
          output << chunk
          @stdout.print(chunk) if ENV["DOCS_QUALITY_STREAM"] == "1"
        end
        status = wait.value
      end
      [status, output, monotonic - started]
    end

    def test_environment
      production_environment.merge(
        "OPENAI_API_KEY" => "test-openai-key-no-network",
        "ANTHROPIC_API_KEY" => "test-anthropic-key-no-network",
        "GEMINI_API_KEY" => "test-gemini-key-no-network",
        "LANGFUSE_PUBLIC_KEY" => "test-public-key-no-network",
        "LANGFUSE_SECRET_KEY" => "test-secret-key-no-network",
        "RACK_ENV" => "test"
      )
    end

    def production_environment
      {"BRIDGETOWN_ENV" => "production", "DSPY_DISABLE_OBSERVABILITY" => "true"}
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

exit DocumentationQuality::Pipeline.new.run if $PROGRAM_NAME == __FILE__
