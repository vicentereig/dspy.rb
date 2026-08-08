# Agent Instructions

These instructions apply to agents working in DSPy.rb. User and system instructions take precedence.

## Start with evidence

- Read the relevant source, tests, README, `CONTRIBUTING.md`, `docs/README.md`, and ADR index before changing behavior.
- Code and tests define current behavior. Gemfiles and lockfiles define dependency constraints. CI defines supported commands and feature flags. ADRs record intent; they do not prove that the code still matches it.
- Inspect `git status --short` and the relevant diff before editing. Preserve unrelated changes.
- State assumptions when a choice is not material. Ask one short question when a missing choice would change the result.

## Repository map

- `lib/` — DSPy.rb, providers, adapters, evaluation, observability, GEPA, datasets, and sibling gems.
- `spec/` — unit, integration, and feature-flagged tests.
- `examples/` — runnable examples.
- `docs/src/` — documentation sources.
- `docs/scripts/` — documentation validators and audits.
- `adr/` — architectural decisions.
- `release_notes/` — release notes.

## Environment

- Use the Ruby version in `.ruby-version` (currently 3.4.5).
- Install Ruby dependencies with `rbenv exec bundle install`.
- Use the `DSPY_WITH_*` flags documented in `Gemfile` and CI for optional providers and sibling gems.
- Copy `.env.sample` to `.env` when needed. Never commit `.env`, API keys, provider tokens, customer data, or recorded secrets.
- Keep library code compatible with each affected gemspec's `required_ruby_version`; the development pin is not the compatibility floor.

## Writing code

- Use two-space Ruby indentation, snake_case filenames, CamelCase constants, and frozen string literals where the surrounding code does.
- Prefer small, testable methods and existing abstractions. Avoid speculative refactors and comments that merely restate code.
- Preserve public API and domain vocabulary unless the task changes them deliberately.
- Verify a public contract against its implementation and tests before updating documentation.

## Documentation writing

- Write for a reader who needs to decide or do something.
- Prefer concrete nouns, active verbs, short sentences, and headings that name the reader's task.
- Give each paragraph one job. Remove boilerplate, repetition, inflated claims, and generic advice.
- Show a working example or label the example as pseudocode. Do not present a vendor placeholder as an implementation.
- State ownership and boundaries: what DSPy.rb provides, what the application provides, and what the example does not establish.
- Keep claims proportional to evidence. Technical visibility is not buyer demand; schema eligibility is not ranking; a score on one dataset is not general performance.
- Preserve the voice and genre of essays. Do not add forced FAQs, keyword lists, generic calls to action, or sales copy to unrelated work.
- Keep `docs/src/` synchronized with behavior, examples, YARD comments, and release notes when a public contract changes. Do not hand-edit generated output when a source file exists.

## Verification

Choose the narrowest useful checks first. Do not run paid provider calls or unrelated full suites by default.

| Change | Minimum check |
| --- | --- |
| Core or pure Ruby logic | Focused unit specs, then the relevant broader unit specs |
| Provider or adapter | Focused specs and existing VCR coverage when the boundary changes |
| GEPA, optimizer, dataset, or sibling gem | The affected feature-flagged CI slice and focused specs |
| Documentation source | `rbenv exec ruby docs/scripts/check_documentation_quality.rb` |
| Cross-gem or release change | Relevant focused suites and the CI-equivalent suite when requested |

Do not advertise `srb tc` or RuboCop as required gates unless their dependencies, configuration, and CI jobs exist. If a check is unavailable, say so.

Keep pure tests separate from tests that contact an LLM. Use public synthetic inputs. Do not record live requests or replace VCR cassettes without explicit authorization. Inspect cassette diffs for secrets.

## Manual DSPy docs deployment to Fly

`oss.vicente.services` is served by the `vicente.services` Fly app. It is not served by the DSPy.rb GitHub Pages artifact.

A push to DSPy.rb does not automatically rebuild the Fly image. After pushing a docs commit, dispatch the website workflow manually with the exact DSPy revision:

```bash
DSPY_SHA="$(git rev-parse HEAD)"
gh workflow run deploy.yml -R vicentereig/vicente.services -f dspy_ref="$DSPY_SHA"
```

The website workflow checks out that SHA, builds `docs/`, assembles it under `/dspy.rb/`, records the SHA in `BUILD-METADATA.txt`, and deploys the pinned OpenResty image to Fly.

Do not add `GH_TOKEN` or another cross-repository credential to the public DSPy.rb workflow. Manual dispatch is intentional. The separate `vicentereig.github.io` GitHub Pages surface must remain available because it provides the 301 compatibility redirects to `oss.vicente.services`.

After deployment, verify the app health endpoint, the docs route, and Fly logs. Plausible pageviews are asynchronous and may be filtered or lost during a restart; Fly logs remain the traffic audit source.

## Delegation

Delegate only bounded, independent work. Reviewers should be read-only by default. Do not delegate secrets, paid calls, remote mutations, or overlapping edits. The parent agent integrates the work and reports changed files, checks, evidence, and uncertainty.

## External state and handoff

- Commits, pushes, issue changes, releases, and other external mutations require explicit user authorization or a task that clearly includes them.
- Before an authorized commit, run the applicable checks and inspect the staged diff for secrets and generated files.
- Never clear stashes, overwrite another contributor's work, or use a blanket `git add` in a dirty worktree.
- If delivery is not authorized, leave a handoff with changed files, checks run, remaining risks, and exact next steps.
