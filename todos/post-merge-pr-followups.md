# Post-merge follow-ups (open PRs #230-#233)

- [ ] PR #230: Restore cross-platform lockfile support in `Gemfile.lock`
  - Add platforms back: `ruby` (and `x86_64-linux` if CI uses Linux)
  - Suggested command: `bundle lock --add-platform ruby x86_64-linux`

- [ ] PR #231: Preserve zero values for Anthropic cache token fields
  - In `AnthropicUsage#to_h`, include `0` values (avoid truthy checks)
  - In LM tracing attribute emission, include cache token attributes when value is `0`

- [ ] PR #233: Add regression tests for trailing-comma JSON workaround
  - Add tests in `spec/integration/dspy/lm/json_strategy_spec.rb`
  - Case 1: malformed Anthropic JSON ending with `,}` is repaired and parseable
  - Case 2: valid JSON input is unchanged by extraction

- [ ] Anthropic model support validation (4.6 generation)
  - Verify Beta structured outputs support for Claude 4.6 Sonnet and Claude 4.6 Opus
  - If supported, update `CHANGELOG.md` and docs model compatibility list

## Release candidates (post-merge)

- [ ] `dspy` current `0.34.3` -> proposed `0.34.4`
  - Includes core changes from PR #231, #232, #233 (`LM`, `Usage`, `TypeCoercion`, `JSONStrategy`)

- [ ] `dspy-anthropic` current `1.0.3` -> proposed `1.0.4`
  - Includes Anthropic Beta structured outputs from PR #230 and dependency floor update (`anthropic >= 1.16.2`)
