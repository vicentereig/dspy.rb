# Contributing to DSPy.rb

Thanks for contributing to DSPy.rb. Use this guide to install the development dependencies and run the test suite.

## Development Setup

### Prerequisites

- Ruby (see `.ruby-version` for the pinned version; minimum 3.3.0)
- Bundler 2.0+

### System Dependencies

DSPy.rb uses native extensions that require system libraries. Install these first:

**macOS (Homebrew):**

```bash
# Required for red-arrow (Parquet dataset support)
brew install apache-arrow-glib

# Required for numo-tiny_linalg (MIPROv2 optimizer)
brew install openblas
```

**Note:** OpenBLAS is keg-only on macOS. Set these environment variables before running `bundle install`:

```bash
export LDFLAGS="-L/opt/homebrew/opt/openblas/lib"
export CPPFLAGS="-I/opt/homebrew/opt/openblas/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/openblas/lib/pkgconfig"
```

**Linux:**

```bash
# Ubuntu/Debian
sudo apt-get install libarrow-glib-dev libopenblas-dev

# Fedora/RHEL
sudo dnf install arrow-glib-devel openblas-devel
```

### Install Dependencies

```bash
# Clone the repository
git clone https://github.com/vicentereig/dspy.rb.git
cd dspy.rb

# Install dependencies
bundle install

# Set up API keys for testing
cp .env.sample .env
# Edit .env with your OPENAI_API_KEY and ANTHROPIC_API_KEY
```

## Running Tests

```bash
# Run all tests
bundle exec rspec

# Run only unit tests (fast, no API calls)
bundle exec rspec spec/unit

# Run integration tests (uses VCR cassettes)
bundle exec rspec spec/integration

# Run a specific test file
bundle exec rspec spec/path/to/file_spec.rb
```

## Development Workflow

### Making Changes

1. **Create a feature branch:**
   ```bash
   git checkout -b feat/your-feature-name
   ```

2. **Follow TDD:** Write tests first, then implement.

3. **Run tests frequently:**
   ```bash
   bundle exec rspec
   ```

4. **Verify documentation builds:**

   The documentation site requires its Ruby bundle, Bun dependencies, and a
   Playwright Chromium install for OG image generation:

   ```bash
   # Install Bun (if not already installed)
   curl -fsSL https://bun.sh/install | bash

   # Install root dependencies from the repository root
   rbenv exec bundle install

   # Install documentation dependencies
   cd docs
   bun install
   bunx playwright install chromium
   rbenv exec bundle install
   cd ..

   # Run the sole local and CI documentation gate
   ruby docs/scripts/check_documentation_quality.rb
   ```

   `.ruby-version` is authoritative for rbenv and CI. The divergent Ruby 3.3.7
   in `.tool-versions` remains an asdf compatibility declaration, not the
   version used by this command.

### Commit Guidelines

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scope): add new feature
fix(scope): fix bug
docs(scope): update documentation
test(scope): add tests
refactor(scope): refactor code
```

**Examples:**
```bash
git commit -m "feat(signatures): add support for nested types"
git commit -m "fix(anthropic): handle rate limit errors correctly"
git commit -m "docs(miprov2): clarify Bayesian optimization parameters"
```

### Code Quality

- **Follow Ruby idioms:** Use `Enumerable`, keyword arguments, pattern matching
- **Type safety:** Add Sorbet signatures for public APIs
- **Keep changes focused:** Add an abstraction only when the current change requires it.
- **Test coverage:** Unit test logic, integration test LLM interactions

See [CLAUDE.md](CLAUDE.md) for detailed development best practices.

## Project Structure

- `lib/dspy/` - Core library code (modules, LM adapters, tools, etc.)
- `lib/dspy/datasets/`, `lib/dspy/miprov2/` - Optional sibling gems with their own gemspecs
- `spec/unit/` - Fast unit tests
- `spec/integration/` - LLM integration tests with VCR
- `docs/` - Documentation site
- `examples/` - Runnable examples

## Documentation

When changing APIs or adding features, update the docs:

- **User docs:** `docs/src/**/*.md`
- **API docs:** Inline YARD comments in code
- **Examples:** Add to `examples/` directory

The documentation site is in `docs/` and built with Bridgetown. Always verify your changes build successfully.

Run `ruby docs/scripts/check_documentation_quality.rb` from the
repository root for every documentation change. It executes only snippets in
`docs/editorial/executable-snippets.yml`: the canonical Quick Start, Toolsets,
and long-page examples. Generic Ruby fences, Rails/provider examples, token
examples, and VCR recipes are not executed. The designated specs use sentinel
keys and enforce offline behavior. Rendered internal URLs and fragments are
resolved locally; redirect JavaScript escaping is checked with the docs bundle;
the gate never fetches external URLs. Economical-writing
findings remain an advisory reviewer queue and do not fail CI, although scanner
configuration, parsing, invocation, and read failures do.

The canonical command relies on the rbenv shim to select `.ruby-version`
locally and on `ruby/setup-ruby` to select the same file in CI. `rbenv exec` is
an equivalent explicit local wrapper, but CI does not require an rbenv binary.

### Review Public Documentation Changes

Use [`docs/editorial/public-doc-corpus.yml`](docs/editorial/public-doc-corpus.yml)
to classify a changed file. The review applies to entries marked `public` or
`history`; derived sources and excluded contributor, plan, and editorial files
are not scanner inputs.

For a meaning-changing edit:

1. Complete the five prompts in the pull request template. The author
   self-check supplies context; a reviewer makes the disposition.
2. Run the informational scanner with the exact changed public/history paths,
   not a directory or generated output. For example:

   ```bash
   ruby docs/scripts/audit_economical_writing.rb README.md docs/src/getting-started/quick-start.md
   ```

3. Search [`docs/editorial/semantic-anchors.yml`](docs/editorial/semantic-anchors.yml)
   for each changed path and claim. List affected anchor IDs in the pull
   request. If none apply, write `reviewed, none — reason`; do not create a
   second anchor list.
4. Leave every scanner candidate in the pull request's reviewer queue. The
   reviewer assigns exactly one of `DELETE`, `EDIT`, `KEEP technical`, or
   `KEEP voice` with a rationale. Findings are prompts for review: zero is not
   required, and a word match does not fail CI.

Use the typo-only path only when every edit is spelling, grammar, or punctuation
and does not change meaning, headings, links, code, frontmatter, routes, or
anchor locators. List the pages touched and confirm the restriction. Otherwise,
use the full review and scanner queue.

Escalate a disputed claim or semantic-anchor effect to a maintainer in the pull
request before approval. `KEEP voice` also requires a durable existing or new
exception in
[`docs/editorial/house-voice-samples.yml`](docs/editorial/house-voice-samples.yml)
with `audience`, `evidence`, `evidence_locator`, `scope`, `editor`, `reviewed_on`,
and `re_review`; set `approval` to `rhetorical-form-only`. The exception covers
the rhetorical form at that scope, never a new factual claim. Keep ordinary
candidate dispositions in the pull request rather than adding another ledger.

## Getting Help

- **Questions:** Open a [Discussion](https://github.com/vicentereig/dspy.rb/discussions)
- **Bugs:** Open an [Issue](https://github.com/vicentereig/dspy.rb/issues)
- **Coordination:** Reach out at hey@vicente.services

## License

By contributing, you agree your contributions will be licensed under the MIT License.
