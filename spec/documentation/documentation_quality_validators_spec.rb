# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../../docs/scripts/validate_completion_audit"
require_relative "../../docs/scripts/validate_executable_snippets"
require_relative "../../docs/scripts/validate_internal_links"
require_relative "../../docs/scripts/validate_llms_references"
require_relative "../../docs/scripts/validate_workflow_ruby_policy"
require_relative "../../docs/scripts/check_documentation_quality"

RSpec.describe "documentation quality validators" do
  QUALITY_ROOT = Pathname(__dir__).join("../..").expand_path
  QUALITY_ROUTES = DocumentationQuality::LlmsReferences::REQUIRED_ROUTES.freeze

  def write(path, content)
    FileUtils.mkdir_p(path.dirname)
    path.write(content, encoding: "UTF-8")
  end

  def link_fixture
    Dir.mktmpdir("docs-links") do |directory|
      output = Pathname(directory).join("output")
      write(output.join("index.html"), <<~HTML)
        <html><body id="home">
        <a href="/dspy.rb/guide/#encoded%20fragment">Guide</a>
        <a href="https://offline.invalid/never-fetch">External</a>
        <img src="/dspy.rb/assets/logo.svg">
        </body></html>
      HTML
      write(output.join("guide/index.html"), '<h1 id="encoded fragment">Guide</h1>')
      write(output.join("assets/logo.svg"), "<svg/>")
      write(output.join("llms.txt"), "[Guide](https://oss.vicente.services/dspy.rb/guide/#encoded%20fragment)\n")
      write(output.join("llms-full.txt"), "[Guide](/dspy.rb/guide/)\n")
      yield output
    end
  end

  def replace_in(path, before, after)
    path.write(path.read(encoding: "UTF-8").sub(before, after), encoding: "UTF-8")
  end

  def completion_audit_errors
    document = YAML.safe_load_file(QUALITY_ROOT.join("docs/editorial/completion-audit.yml"))
    yield document if block_given?
    Dir.mktmpdir("completion-audit") do |directory|
      audit = Pathname(directory).join("completion-audit.yml")
      write(audit, document.to_yaml)
      return DocumentationQuality::CompletionAudit.new(root: QUALITY_ROOT, audit: audit).errors
    end
  end

  it "accepts the complete corpus audit" do
    expect(completion_audit_errors).to be_empty
  end

  it "rejects omitted corpus, anchor, duplicate, exception, taxonomy, blind-review, and llms evidence" do
    mutations = [
      [->(doc) { doc.fetch("source_audits").reject! { _1["path"] == "docs/src/advanced/module-lifecycle-callbacks.md" } }, "source audits missing"],
      [->(doc) { row = doc.fetch("anchor_audits").first; row["verdict"] = "blocked"; row.delete("owner") }, "blocked anchor needs owner"],
      [->(doc) { doc.fetch("duplicate_decisions").first["distinction"] = "" }, "duplicate distinction is missing"],
      [->(doc) { doc.fetch("rhetorical_exceptions").first["editor"] = "" }, "exception editor is missing or drifted"],
      [->(doc) { doc.fetch("category_results").reject! { _1["category"] == "voice" } }, "four finding categories exactly"],
      [->(doc) { doc.fetch("blind_review").fetch("sample").pop }, "recorded deterministic sample"],
      [->(doc) { doc.fetch("blind_review").fetch("high_traffic").delete("docs/src/core-concepts/toolsets.md") }, "all required entry points"],
      [->(doc) { doc.fetch("focus_sources").reject! { %w[docs/src/llms.txt.erb docs/src/llms-full.txt.erb].include?(_1["path"]) } }, "omits new, moved, or llms sources"]
    ]

    mutations.each do |mutation, diagnostic|
      errors = completion_audit_errors { mutation.call(_1) }
      expect(errors.join("\n")).to include(diagnostic)
    end
  end

  it "resolves encoded fragments and assets without fetching external URLs" do
    link_fixture do |output|
      expect(DocumentationQuality::InternalLinks.new(output: output).errors).to be_empty
    end
  end

  it "reports file, line, href, missing base path, route, and fragment context" do
    mutations = [
      ["/dspy.rb/guide/#encoded%20fragment", "/guide/", "missing /dspy.rb"],
      ["/dspy.rb/guide/#encoded%20fragment", "/dspy.rb/missing/", "does not exist"],
      ["/dspy.rb/guide/#encoded%20fragment", "/dspy.rb/guide/#missing", "fragment does not exist"]
    ]
    mutations.each do |before, after, diagnostic|
      link_fixture do |output|
        replace_in(output.join("index.html"), before, after)
        errors = DocumentationQuality::InternalLinks.new(output: output).errors
        expect(errors.join("\n")).to include("index.html:2:", "href=#{after.inspect}", diagnostic)
      end
    end
  end

  it "validates same-site protocol-relative URLs instead of treating them as external" do
    link_fixture do |output|
      replace_in(output.join("index.html"), "https://offline.invalid/never-fetch", "//oss.vicente.services/guide/")
      errors = DocumentationQuality::InternalLinks.new(output: output).errors.join("\n")
      expect(errors).to include('href="//oss.vicente.services/guide/"', "missing /dspy.rb")
    end
  end

  it "does not let an unquoted href bypass base-path validation" do
    link_fixture do |output|
      replace_in(output.join("index.html"), 'href="/dspy.rb/guide/#encoded%20fragment"', "href=/guide/")
      errors = DocumentationQuality::InternalLinks.new(output: output).errors.join("\n")
      expect(errors).to include('href="/guide/"', "missing /dspy.rb")
    end
  end

  def llms_fixture
    Dir.mktmpdir("llms-consistency") do |directory|
      root = Pathname(directory)
      quick_source = QUALITY_ROOT.join("docs/src/getting-started/quick-start.md")
      matrix_source = QUALITY_ROOT.join("docs/src/_data/package_capabilities.yml")
      FileUtils.mkdir_p(root.join("docs/src/getting-started"))
      FileUtils.mkdir_p(root.join("docs/src/_data"))
      FileUtils.cp(quick_source, root.join("docs/src/getting-started/quick-start.md"))
      FileUtils.cp(matrix_source, root.join("docs/src/_data/package_capabilities.yml"))
      quick = quick_source.read(encoding: "UTF-8")
      material = %w[
        quick-start-gemfile quick-start-install-command quick-start-api-key-command
        quick-start-program quick-start-run-command
      ].map do |marker|
        quick[/<!-- #{marker} -->\s*```\w+\n(.*?)\n```/m, 1]
      end.join("\n")
      route_text = QUALITY_ROUTES.map { "https://oss.vicente.services/dspy.rb#{_1}" }.join("\n")
      packages = YAML.safe_load_file(matrix_source).fetch("packages")
      public_names = packages.select { _1["visibility"] == "public" }.map { "`#{_1.fetch('gem')}`" }.join("\n")
      source_text = "package_capabilities\n#{route_text}\n#{material}\n"
      output_text = "#{route_text}\n#{material}\n#{public_names}\n"
      DocumentationQuality::LlmsReferences::SOURCE_FILES.each { |path| write(root.join(path), source_text) }
      DocumentationQuality::LlmsReferences::OUTPUT_FILES.each { |name| write(root.join("docs/output", name), output_text) }
      now = Time.now + 1
      DocumentationQuality::LlmsReferences::OUTPUT_FILES.each { |name| FileUtils.touch(root.join("docs/output", name), mtime: now) }
      yield root
    end
  end

  it "distinguishes stale ERB sources from correct rendered references" do
    llms_fixture do |root|
      source = root.join("docs/src/llms.txt.erb")
      replace_in(source, "bundle exec ruby classify.rb", "removed source command")
      errors = DocumentationQuality::LlmsReferences.new(root: root).errors
      expect(errors.join("\n")).to include("docs/src/llms.txt.erb: canonical Quick Start material is stale")
      expect(errors.join("\n")).not_to include("llms-full.txt: canonical Quick Start material is stale")
    end
  end

  it "distinguishes stale rendered references from correct ERB sources" do
    llms_fixture do |root|
      output = root.join("docs/output/llms-full.txt")
      replace_in(output, "bundle exec ruby classify.rb", "removed output command")
      errors = DocumentationQuality::LlmsReferences.new(root: root).errors
      expect(errors.join("\n")).to include("llms-full.txt: canonical Quick Start material is stale")
      expect(errors.join("\n")).not_to include("llms.txt.erb: canonical Quick Start material is stale")
    end
  end

  def snippet_fixture
    Dir.mktmpdir("snippet-registry") do |directory|
      root = Pathname(directory)
      registry = YAML.safe_load_file(QUALITY_ROOT.join("docs/editorial/executable-snippets.yml"))
      write(root.join("docs/editorial/executable-snippets.yml"), registry.to_yaml)
      registry.fetch("specs").each do |path|
        FileUtils.mkdir_p(root.join(path).dirname)
        FileUtils.cp(QUALITY_ROOT.join(path), root.join(path))
      end
      registry.fetch("snippets").map { _1.fetch("source") }.uniq.each do |path|
        FileUtils.mkdir_p(root.join(path).dirname)
        FileUtils.cp(QUALITY_ROOT.join(path), root.join(path))
      end
      yield root, registry
    end
  end

  it "ignores unmarked pseudocode, Rails, provider, live-token, and VCR fences" do
    snippet_fixture do |root, _registry|
      unsafe = <<~MARKDOWN

        ```ruby
        Rails.application.config.x.token = "sk-live-looking-token-1234567890"
        VCR.use_cassette("provider") { Provider.call }
        ```
      MARKDOWN
      path = root.join("docs/src/core-concepts/toolsets.md")
      path.write(path.read(encoding: "UTF-8") + unsafe, encoding: "UTF-8")
      expect(DocumentationQuality::ExecutableSnippets.new(root: root).errors).to be_empty
    end
  end

  it "fails a designated marker mutation through the real registry validator" do
    snippet_fixture do |root, registry|
      entry = registry.fetch("snippets").first
      path = root.join(entry.fetch("source"))
      replace_in(path, entry.fetch("marker"), "mutated-marker")
      errors = DocumentationQuality::ExecutableSnippets.new(root: root).errors
      expect(errors.join("\n")).to include("registered marker is missing", "unregistered executable marker mutated-marker")
    end
  end

  it "rejects Rails, live credentials, and VCR when a marker selects the fence" do
    snippet_fixture do |root, _registry|
      path = root.join("docs/src/core-concepts/toolsets.md")
      unsafe = <<~RUBY
        Rails.application.config.x.token = "sk-live-looking-token-1234567890"
        VCR.use_cassette("provider") { Provider.call }
      RUBY
      text = path.read(encoding: "UTF-8")
      text.sub!(/(<!-- toolsets-text-processing-example -->\s*```ruby\n)(.*?)(\n```)/m, "\\1#{unsafe.rstrip}\\3")
      path.write(text, encoding: "UTF-8")
      errors = DocumentationQuality::ExecutableSnippets.new(root: root).errors.join("\n")
      expect(errors).to include("live-looking credential", "must not depend on Rails", "must not invoke VCR")
    end
  end

  it "rejects an existing redirect target mutated into a redirect chain" do
    document = YAML.safe_load_file(QUALITY_ROOT.join("docs/editorial/url-redirects.yml"))
    document.fetch("redirects").first["to"] = document.fetch("redirects")[1].fetch("from")
    Dir.mktmpdir("redirect-chain") do |directory|
      manifest = Pathname(directory).join("redirects.yml")
      write(manifest, document.to_yaml)
      output, status = Open3.capture2e(
        RbConfig.ruby, QUALITY_ROOT.join("docs/scripts/validate_url_redirects.rb").to_s,
        "--manifest", manifest.to_s, chdir: QUALITY_ROOT.to_s
      )
      expect(status).not_to be_success
      expect(output).to include("creates a chain or double move")
    end
  end

  it "runs redirect script escaping exactly once from the documentation bundle" do
    pipeline = DocumentationQuality::Pipeline.new(root: QUALITY_ROOT)
    steps = pipeline.send(:steps)
    safety = steps.select { _1.command.include?("scripts/test_url_redirect_safety.rb") }

    expect(steps.length).to eq(22)
    expect(safety.length).to eq(1)
    expect(safety.first.chdir).to eq(QUALITY_ROOT.join("docs").to_s)
    expect(safety.first.command).to include("bundle", "exec", "ruby")
  end

  it "keeps workflows on .ruby-version and the sole documentation command" do
    ruby_workflow = YAML.safe_load_file(QUALITY_ROOT.join(".github/workflows/ruby.yml"), aliases: true)
    deploy = QUALITY_ROOT.join(".github/workflows/deploy.yml").read(encoding: "UTF-8")
    docs_job = ruby_workflow.fetch("jobs").fetch("docs-quality")
    commands = docs_job.fetch("steps").filter_map { _1["run"] }.join("\n")
    expect(commands).to include("ruby docs/scripts/check_documentation_quality.rb")
    expect(commands).not_to include("rbenv exec")
    expect(commands.scan("check_documentation_quality.rb").length).to eq(1)
    expect(commands).not_to match(/ruby-version:\s*['\"]?3\./)
    expect(deploy).to include("cat .ruby-version")
    expect(deploy).not_to match(/ruby-version:\s*['\"]?3\./)
  end

  it "rejects a workflow fixture with an unsupported hard-coded Ruby" do
    Dir.mktmpdir("workflow-ruby") do |directory|
      root = Pathname(directory)
      FileUtils.mkdir_p(root.join(".github/workflows"))
      %w[ruby.yml deploy.yml].each do |name|
        FileUtils.cp(QUALITY_ROOT.join(".github/workflows", name), root.join(".github/workflows", name))
      end
      path = root.join(".github/workflows/deploy.yml")
      text = path.read(encoding: "UTF-8").sub(
        '${{ steps.ruby-version.outputs.version }}',
        "'3.2'"
      )
      path.write(text, encoding: "UTF-8")
      errors = DocumentationQuality::WorkflowRubyPolicy.new(root: root).errors.join("\n")
      expect(errors).to include("unsupported hard-coded Ruby literal", "must use the .ruby-version step output")
    end
  end
end
