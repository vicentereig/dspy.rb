# Contributing to DSPy.rb

Thanks for contributing to DSPy.rb. This guide gets you from zero to running tests in minutes.

## Development Setup

### Prerequisites

- Ruby 3.3 or later
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
export OPENAI_API_KEY=your-openai-api-key
export ANTHROPIC_API_KEY=your-anthropic-api-key
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
   ```bash
   cd docs
   BRIDGETOWN_ENV=production npm run build
   ```

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
- **Keep it simple:** Don't over-engineer. Small methods beat abstractions.
- **Test coverage:** Unit test logic, integration test LLM interactions

See [CLAUDE.md](CLAUDE.md) for detailed development best practices.

## Project Structure

- `lib/dspy/` - Core library code
- `lib/dspy/*/` - Sibling gems (datasets, miprov2, etc.)
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

## Getting Help

- **Questions:** Open a [Discussion](https://github.com/vicentereig/dspy.rb/discussions)
- **Bugs:** Open an [Issue](https://github.com/vicentereig/dspy.rb/issues)
- **Coordination:** Reach out at hey@vicente.services

## License

By contributing, you agree your contributions will be licensed under the MIT License.
