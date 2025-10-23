# ADR 011: CI Matrix Bundler Caching Strategy

**Status:** Accepted
**Date:** 2025-10-23
**Deciders:** Vicente Reig

## Context

DSPy.rb uses a monorepo structure with multiple gems (dspy, dspy-datasets, dspy-miprov2, gepa, dspy-evals) that have different system dependencies:
- `dspy-datasets` requires Apache Arrow libraries (native extensions)
- `dspy-miprov2` requires OpenBLAS/LAPACK libraries (native extensions)
- Other gems have no special system requirements

The Gemfile uses environment variables to conditionally include gems:

```ruby
if ENV.fetch('DSPY_WITH_DATASETS', '1') == '1'
  gemspec name: "dspy-datasets"
end

if ENV.fetch('DSPY_WITH_MIPROV2', '1') == '1'
  gemspec name: "dspy-miprov2"
end
```

The CI workflow uses a GitHub Actions matrix to test each gem separately, setting different environment variables per job to only install required dependencies.

### The Problem

When enabling `bundler-cache: true` in ruby/setup-ruby, all matrix jobs failed with:

```
The gemspecs for path gems changed, but the lockfile can't be updated because
frozen mode is set

You have deleted from the Gemfile:
* dspy-datasets
* dspy-miprov2
```

**Root Cause Analysis:**

1. **Shared Cache Key**: ruby/setup-ruby generates cache keys based on:
   - Gemfile.lock hash
   - Ruby version
   - Working directory
   - BUNDLE_WITH environment variable
   - **NOT** custom environment variables like DSPY_WITH_DATASETS

2. **Dynamic Gemfile Problem**: The Gemfile content changes based on environment variables, but all matrix jobs share the same Gemfile.lock file.

3. **Frozen Mode Conflict**: ruby/setup-ruby uses `bundle install --deployment` which sets frozen mode, preventing Gemfile.lock updates. When a job tries to use a cached bundle built with all gems, but its Gemfile excludes some gems, bundler detects a mismatch and fails.

4. **Race Condition**: The first matrix job to run determines what's in the shared cache. Subsequent jobs with different configurations try to use an incompatible cache.

### Failed Attempts

Multiple strategies were attempted:

1. **Commit f5a8faf**: Enabled bundler-cache globally
   - Result: All jobs shared same cache, incompatible with different configs

2. **Commits 98523e9-92e097b**: Various cache strategies (artifacts, shared installs)
   - Result: Still used shared cache key without environment variables

3. **Commit d62c2db**: Disabled bundler-cache completely
   - Result: ✅ Works but slow (~3-5 minutes per job for gem installation)

## Decision

**Use the `cache-version` parameter to create separate caches per gem configuration.**

The `cache-version` parameter is specifically designed for cases where gems with C extensions depend on system libraries or environment-specific configurations. Each unique cache-version creates a separate cache entry.

### Implementation

```yaml
- name: Set up Ruby
  uses: ruby/setup-ruby@v1
  with:
    ruby-version: ${{ steps.ruby-version.outputs.version }}
    bundler-cache: true
    cache-version: "d${{ matrix.datasets }}-m${{ matrix.miprov2 }}-e${{ matrix.evals }}"
  env:
    DSPY_WITH_DATASETS: ${{ matrix.datasets }}
    DSPY_WITH_MIPROV2: ${{ matrix.miprov2 }}
    DSPY_WITH_EVALS: ${{ matrix.evals }}
    BUNDLE_WITH: development:test
```

### Cache Distribution

- **d0-m0-e1**: DSPy Core, GEPA, DSPy Evaluations (shared, ~240MB)
- **d1-m0-e1**: DSPy Datasets (unique, needs Arrow, ~240MB)
- **d0-m1-e1**: DSPy MIPROv2 (unique, needs OpenBLAS, ~240MB)

Total: 3 separate caches instead of 1 shared or 5 individual.

## Consequences

### Positive

- ✅ **Resolves frozen mode errors**: Each configuration gets a consistent cache
- ✅ **Fast CI builds**: After first run, bundler uses cached gems
- ✅ **Efficient cache usage**: Jobs with identical configs share caches
- ✅ **No code changes**: Only workflow modification needed
- ✅ **Self-healing**: Can bump cache-version to force rebuild if needed
- ✅ **Official solution**: Uses documented ruby/setup-ruby feature

### Negative

- ⚠️ **Multiple caches**: Uses ~720MB total instead of ~240MB
- ⚠️ **First run overhead**: Each unique configuration builds cache on first run
- ⚠️ **Cache management**: GitHub Actions has 10GB limit (plenty of room)

### Neutral

- Changes cache invalidation behavior - must update cache-version if system dependencies change
- Jobs with identical gem configurations benefit from shared cache (Core, GEPA, Evaluations)

## Alternatives Considered

### 1. Install All System Dependencies Everywhere
- Set all matrix jobs to `datasets: '1'`, `miprov2: '1'`
- Install Arrow and OpenBLAS in every job
- **Rejected**: Wasteful, adds 2-3 minutes to each job

### 2. Disable Bundler Cache Completely
- Set `bundler-cache: false`
- Accept slow CI builds
- **Rejected**: Used as working baseline but too slow

### 3. Multiple Gemfiles with Separate Lockfiles
- Create Gemfile.datasets, Gemfile.miprov2, etc.
- Use BUNDLE_GEMFILE environment variable
- **Rejected**: Major refactor, complex to maintain

### 4. Manual Cache Management
- Use actions/cache directly with custom keys
- **Rejected**: More complex, error-prone, reinventing the wheel

## References

- [ruby/setup-ruby documentation](https://github.com/ruby/setup-ruby)
- [GitHub Actions cache documentation](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- Issue thread: Multiple failed CI attempts from commits f5a8faf through 92e097b
- Working baseline: Commit d62c2db (bundler-cache: false)

## Notes

The cache-version parameter was explicitly designed for this use case: "In rare scenarios where you need to ignore the cache contents and rebuild all gems anew (such as when using gems with C extensions whose functionality depends on system libraries), you can use the cache-version option."

This solution aligns with the official recommendation and leverages the built-in cache management of ruby/setup-ruby rather than implementing a custom solution.
