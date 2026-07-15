# frozen_string_literal: true

require "open3"
require "pathname"
require "yaml"
require "bundler"
require "fileutils"
require "tempfile"
require "tmpdir"

RSpec.describe "Long-page dispositions" do
  TASKS = [
    {
      id: "concurrent-predictions",
      source: "docs/src/advanced/concurrent-predictions.md",
      route: "/advanced/concurrent-predictions/",
      heading: "concurrent-predictions",
      old_route: "/core-concepts/predictors/",
      old_anchor: "concurrent-predictions",
      exits: ["/production/observability/", "/production/troubleshooting/"]
    },
    {
      id: "module-lifecycle-callbacks",
      source: "docs/src/advanced/module-lifecycle-callbacks.md",
      route: "/advanced/module-lifecycle-callbacks/",
      heading: "module-lifecycle-callbacks",
      old_route: "/advanced/module-runtime-context/",
      old_anchor: "lifecycle-callbacks",
      exits: ["/core-concepts/events/", "/production/observability/", "/advanced/observability-interception/"]
    },
    {
      id: "score-reporting",
      source: "docs/src/production/score-reporting.md",
      route: "/production/score-reporting/",
      heading: "score-reporting",
      old_route: "/production/observability/",
      old_anchor: "score-reporting",
      exits: ["/optimization/evaluation/", "/advanced/custom-metrics/", "/production/observability/"]
    }
  ].freeze

  before(:context) do
    @root = Pathname(__dir__).join("../..").expand_path
    @docs = @root.join("docs")
    @output = @docs.join("output")
    @build_log, @build_status = Bundler.with_unbundled_env do
      Open3.capture2e(
        { "BRIDGETOWN_ENV" => "production" },
        "rbenv", "exec", "bundle", "exec", "bridgetown", "build",
        chdir: @docs.to_s
      )
    end
  end

  let(:root) { @root }
  let(:docs) { @docs }
  let(:output_path) { @output }
  let(:ledger) { YAML.safe_load_file(root.join("docs/editorial/long-page-dispositions.yml")) }

  def artifact(output_path, route)
    output_path.join(route.delete_prefix("/"), "index.html")
  end

  def contract_snapshot(output_path, docs)
    {
      nav: YAML.safe_load_file(docs.join("src/_data/documentation_navigation.yml")),
      sitemap: output_path.join("sitemap.xml").read(encoding: "UTF-8"),
      llms: {
        "llms.txt" => output_path.join("llms.txt").read(encoding: "UTF-8"),
        "llms-full.txt" => output_path.join("llms-full.txt").read(encoding: "UTF-8")
      },
      rendered: TASKS.to_h do |task|
        [
          task.fetch(:id),
          {
            page: artifact(output_path, task.fetch(:route)).read(encoding: "UTF-8"),
            old_page: artifact(output_path, task.fetch(:old_route)).read(encoding: "UTF-8")
          }
        ]
      end
    }
  end

  def contract_errors(snapshot)
    published = snapshot.fetch(:nav).fetch("items").select { _1["status"] == "published" }

    TASKS.flat_map do |task|
      errors = []
      item = published.find { _1["source"] == task.fetch(:source) && _1["url"] == task.fetch(:route) }
      errors << "#{task.fetch(:id)} nav" unless item
      task.fetch(:exits).each do |exit_route|
        errors << "#{task.fetch(:id)} nav exit #{exit_route}" unless item && Array(item["exits"]).any? { _1["url"] == exit_route }
      end
      errors << "#{task.fetch(:id)} sitemap" unless snapshot.fetch(:sitemap).include?("/dspy.rb#{task.fetch(:route)}")
      snapshot.fetch(:llms).each do |name, text|
        errors << "#{task.fetch(:id)} #{name}" unless text.include?("https://oss.vicente.services/dspy.rb#{task.fetch(:route)}")
      end

      pages = snapshot.fetch(:rendered).fetch(task.fetch(:id))
      errors << "#{task.fetch(:id)} heading" unless pages.fetch(:page).include?(%Q{id="#{task.fetch(:heading)}"})
      task.fetch(:exits).each do |exit_route|
        errors << "#{task.fetch(:id)} rendered exit #{exit_route}" unless pages.fetch(:page).include?(%Q{href="/dspy.rb#{exit_route}"})
      end
      errors << "#{task.fetch(:id)} old fragment" unless pages.fetch(:old_page).include?(%Q{id="#{task.fetch(:old_anchor)}"})
      errors << "#{task.fetch(:id)} old handoff" unless pages.fetch(:old_page).include?(%Q{href="/dspy.rb#{task.fetch(:route)}"})
      errors
    end
  end

  it "builds production output and validates measured and rendered contracts" do
    expect(@build_status).to be_success, @build_log

    validation, status = Open3.capture2e(
      "rbenv", "exec", "ruby", "scripts/validate_long_page_dispositions.rb",
      "--output", "output",
      chdir: docs.to_s
    )

    expect(status).to be_success, validation
    expect(validation).to include("rendered routes/fragments/sitemap verified")
  end

  it "enforces a hard-coded task lookup independent of the ledger" do
    expect(contract_errors(contract_snapshot(output_path, docs))).to be_empty
  end

  it "rejects independent nav, fragment, exit, and llms mutations" do
    baseline = contract_snapshot(output_path, docs)

    missing_nav = Marshal.load(Marshal.dump(baseline))
    missing_nav.fetch(:nav).fetch("items").reject! { _1["url"] == "/advanced/concurrent-predictions/" }
    expect(contract_errors(missing_nav)).to include("concurrent-predictions nav")

    missing_fragment = Marshal.load(Marshal.dump(baseline))
    missing_fragment.fetch(:rendered).fetch("module-lifecycle-callbacks")[:old_page]
                    .sub!(%q{id="lifecycle-callbacks"}, %q{id="removed-lifecycle-callbacks"})
    expect(contract_errors(missing_fragment)).to include("module-lifecycle-callbacks old fragment")

    missing_exit = Marshal.load(Marshal.dump(baseline))
    missing_exit.fetch(:rendered).fetch("score-reporting")[:page]
                .gsub!(%q{href="/dspy.rb/advanced/custom-metrics/"}, %q{href="/removed/"})
    expect(contract_errors(missing_exit)).to include("score-reporting rendered exit /advanced/custom-metrics/")

    missing_llms = Marshal.load(Marshal.dump(baseline))
    missing_llms.fetch(:llms)["llms-full.txt"]
                .gsub!("https://oss.vicente.services/dspy.rb/production/score-reporting/", "removed-score-route")
    expect(contract_errors(missing_llms)).to include("score-reporting llms-full.txt")

    missing_sitemap = Marshal.load(Marshal.dump(baseline))
    missing_sitemap[:sitemap]
      .gsub!("https://oss.vicente.services/dspy.rb/advanced/module-lifecycle-callbacks/", "removed-task-route")
    expect(contract_errors(missing_sitemap)).to include("module-lifecycle-callbacks sitemap")
  end

  it "rejects fabricated source anchors, missing rendered anchors, and unexplained no-anchor policies" do
    fabricated = Marshal.load(Marshal.dump(ledger))
    fabricated.fetch("dispositions").first.fetch("anchors") << "fabricated-retained-anchor"

    Tempfile.create(["long-page-dispositions", ".yml"]) do |file|
      file.write(YAML.dump(fabricated))
      file.flush
      validation, status = Open3.capture2e(
        "rbenv", "exec", "ruby", "scripts/validate_long_page_dispositions.rb",
        "--ledger", file.path,
        "--output", "output",
        chdir: docs.to_s
      )

      expect(status).not_to be_success
      expect(validation).to include("declared source anchor missing")
    end

    unexplained = Marshal.load(Marshal.dump(ledger))
    home = unexplained.fetch("dispositions").find { _1.fetch("source") == "docs/src/index.md" }
    home.delete("anchor_rationale")

    Tempfile.create(["long-page-dispositions", ".yml"]) do |file|
      file.write(YAML.dump(unexplained))
      file.flush
      validation, status = Open3.capture2e(
        "rbenv", "exec", "ruby", "scripts/validate_long_page_dispositions.rb",
        "--ledger", file.path,
        "--output", "output",
        chdir: docs.to_s
      )

      expect(status).not_to be_success
      expect(validation).to include("no-anchor policy needs a rationale")
    end

    Dir.mktmpdir("long-page-output") do |directory|
      mutated_output = Pathname(directory).join("output")
      FileUtils.cp_r(output_path, mutated_output)
      page = artifact(mutated_output, "/production/observability/")
      page.write(page.read(encoding: "UTF-8").sub('id="observability"', 'id="removed-observability"'))
      validation, status = Open3.capture2e(
        "rbenv", "exec", "ruby", "scripts/validate_long_page_dispositions.rb",
        "--output", mutated_output.to_s,
        chdir: docs.to_s
      )

      expect(status).not_to be_success
      expect(validation).to include("declared rendered anchor missing")
    end
  end

  it "treats the trigger as review, allowing over-trigger keeps and under-trigger splits" do
    fixtures = ledger.fetch("decision_fixtures")
    expect(fixtures).to include(
      include("measured_tokens" => 1501, "outcome" => "keep"),
      include("measured_tokens" => 1499, "outcome" => "split")
    )
  end
end
