# frozen_string_literal: true

require "pathname"

RSpec.describe "Editorial review gate" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:template) { root.join(".github/PULL_REQUEST_TEMPLATE.md").read(encoding: "UTF-8") }
  let(:contributing) { root.join("CONTRIBUTING.md").read(encoding: "UTF-8") }

  it "is conditional and leaves code-only contributors outside the documentation workflow" do
    expect(template).to include("<details>", "</details>")
    expect(template).to match(/Code-only change\? Skip this section\./)
    expect(template).to match(/public.*or.*history/im)
  end

  it "requires the five meaning-changing author prompts without treating them as approval" do
    prompts = [
      "Reader change or decision", "Supporting mechanism, source, or test",
      "Guarantee and application-owned limit", "Public pages and semantic anchors",
      "Slogan or portable-claim risk"
    ]

    expect(prompts).to all(satisfy { template.include?(_1) })
    expect(template).to include("reviewed, none — reason")
    expect(template).to match(/author self-check.*not approval/i)
  end

  it "does not let meaning-changing edits use the typo-only path" do
    forbidden_changes = %w[meaning headings links code frontmatter routes]

    expect(template).to include("spelling, grammar, or punctuation")
    expect(forbidden_changes).to all(satisfy { template.match?(/#{Regexp.escape(_1)}/i) })
    expect(template).to match(/anchor locators/i)
    expect(template).to match(/Pages touched/)
    expect(template).to match(/Typo-only attestation/)
    expect(template).to match(/bypasses the five prompts and scanner queue/i)
    expect(template).to match(/reviewer\s+must reject the typo-only path/i)
  end

  it "makes the reviewer own candidate dispositions without requiring zero findings" do
    dispositions = ["DELETE", "EDIT", "KEEP technical", "KEEP voice"]

    expect(template).to match(/reviewer\W+not the author\W+owns/i)
    expect(dispositions).to all(satisfy { template.include?(_1) })
    expect(template).to match(/Findings are candidates/i)
    expect(template).to match(/zero findings are not required/i)
    expect(template).to match(/do not create a\s+subjective CI failure/i)
    expect(template).to match(/Reviewer verified that the completed path matches the diff/i)
  end

  it "bounds voice exceptions and keeps ordinary decisions in the pull request" do
    exception_fields = %w[audience evidence evidence_locator scope editor reviewed_on re_review]

    expect(template).to include("house-voice-samples.yml")
    expect(contributing).to include(*exception_fields)
    expect(contributing).to include("rhetorical-form-only")
    expect(template).to match(/Prior\s+approval never makes a new or changed factual claim accurate/i)
    expect(contributing).to match(/ordinary\s+candidate dispositions in the pull request/i)
  end
end
