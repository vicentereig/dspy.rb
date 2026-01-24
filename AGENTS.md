# Repository Guidelines

## Environment & Tooling
- Use `rbenv` with the pinned Ruby in `.ruby-version` (3.4.5). For asdf users, `.tool-versions` lists 3.3.7, but rbenv contributors should honor `.ruby-version`.
- Install dependencies through Bundler: `rbenv exec bundle install`. Provider toggles live in the `Gemfile` via `DSPY_WITH_*` env vars (e.g., `DSPY_WITH_OPENAI=1`).
- Keep secrets in `.env` (see `.env.sample`); required keys include at least one provider API key (OpenAI, Anthropic, Gemini, etc.).

## Project Structure & Module Organization
- `lib/` – core DSPy.rb code and sibling gems (adapters, evals, o11y, etc.).
- `examples/` – runnable demos (predictors, agents, evaluator loops).
- `spec/` – RSpec suites; VCR/WebMock fixtures under `spec/vcr_cassettes/`.
- `docs/` – site sources (markdown under `docs/src`).
- `adr/` – architectural decision records; `release_notes/` for version changelogs.

## Build, Test, and Development Commands
- Install deps: `rbenv exec bundle install`.
- Run tests: `rbenv exec bundle exec rspec`.
- Type check (where present): `rbenv exec bundle exec srb tc`.
- Lint (when RuboCop is enabled locally): `rbenv exec bundle exec rubocop`.
- Run an example: `rbenv exec bundle exec ruby examples/first_predictor.rb` (or any script in `examples/`).

## Coding Style & Naming Conventions
- Ruby, 2-space indent; prefer frozen string literals (`# frozen_string_literal: true`).
- Favor Sorbet types (`T::Struct`, `T::Enum`) for inputs/outputs; keep method signatures typed.
- Filenames use snake_case; classes/modules use CamelCase aligned with Ruby constants.
- Keep environment flags uppercase (`DSPY_WITH_*`, `DSPY_*_MODEL`).

## Testing Guidelines
- Write RSpec examples under `spec/`; name files `*_spec.rb`.
- Use VCR/WebMock for external HTTP; place new cassettes in `spec/vcr_cassettes/`.
- Aim to cover new signatures/predictors with at least one happy-path spec; include failure/validation cases when adding type changes.

## Commit & Pull Request Guidelines
- Commit messages: concise imperative (“Add eval coverage for GEPA loop”); group related changes in a single commit.
- PRs should include: summary, rationale, screenshots/logs when touching user-visible behavior, and linked issues if applicable.
- Ensure CI green locally (`bundle exec rspec` and, if touched, `srb tc`/`rubocop`) before opening a PR.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
