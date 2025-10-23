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

**Use manual caching with `actions/cache` instead of ruby/setup-ruby's bundler-cache.**

After discovering that ruby/setup-ruby's `bundler-cache: true` ALWAYS uses `--deployment` mode (frozen), which is fundamentally incompatible with dynamic Gemfiles, we implemented manual caching that allows bundler to run without frozen mode.

### Why cache-version Failed

Initial attempt used `cache-version` parameter with `bundler-cache: true`. While this created separate caches per configuration (confirmed by cache key: `...v-d0-m0-e1...`), **the error persisted because frozen mode still enforced Gemfile = Gemfile.lock**.

The issue is NOT cache sharing - it's that:
1. ruby/setup-ruby with `bundler-cache: true` runs `bundle config --local deployment true`
2. Deployment mode = frozen mode = lockfile must exactly match Gemfile
3. Our Gemfile is dynamic (conditional gemspecs based on env vars)
4. Our Gemfile.lock is static (contains all gems)
5. **= Bundler refuses to work**

### Implementation

```yaml
- name: Cache gems
  uses: actions/cache@v4
  with:
    path: vendor/bundle
    key: gems-${{ runner.os }}-${{ matrix.datasets }}-${{ matrix.miprov2 }}-${{ matrix.evals }}-${{ hashFiles('**/Gemfile.lock') }}
    restore-keys: |
      gems-${{ runner.os }}-${{ matrix.datasets }}-${{ matrix.miprov2 }}-${{ matrix.evals }}-

- name: Set up Ruby
  uses: ruby/setup-ruby@v1
  with:
    ruby-version: ${{ steps.ruby-version.outputs.version }}
    bundler-cache: false  # MUST be false to avoid frozen mode

- name: Install dependencies
  env:
    DSPY_WITH_DATASETS: ${{ matrix.datasets }}
    DSPY_WITH_MIPROV2: ${{ matrix.miprov2 }}
    DSPY_WITH_EVALS: ${{ matrix.evals }}
  run: |
    bundle config set --local path vendor/bundle
    bundle install --jobs 4
```

### Cache Distribution

- **gems-Linux-0-0-1**: DSPy Core, GEPA, DSPy Evaluations (shared, ~240MB)
- **gems-Linux-1-0-1**: DSPy Datasets (unique, needs Arrow, ~240MB)
- **gems-Linux-0-1-1**: DSPy MIPROv2 (unique, needs OpenBLAS, ~240MB)

Total: 3 separate caches. Cache key includes matrix variables so each configuration gets appropriate gems.

## Consequences

### Positive

- ✅ **Resolves frozen mode errors**: Bundler runs without --deployment flag
- ✅ **Fast CI builds**: After first run, uses cached gems (~30-60s vs 3-5min)
- ✅ **Correct behavior**: Bundler can adapt to dynamic Gemfile
- ✅ **Efficient cache usage**: Jobs with identical configs share caches
- ✅ **Standard practices**: No weird workarounds or non-standard lockfile management
- ✅ **Transparent**: Cache key clearly shows what configuration is cached

### Negative

- ⚠️ **Manual cache management**: More verbose than bundler-cache: true
- ⚠️ **Multiple caches**: Uses ~720MB total instead of ~240MB
- ⚠️ **First run overhead**: Each unique configuration builds cache on first run (~5min)

### Neutral

- Jobs with identical gem configurations benefit from shared cache (Core, GEPA, Evaluations)
- Cache invalidation via Gemfile.lock hash changes

## Alternatives Considered

### 1. cache-version Parameter (TRIED - FAILED)
- Use `cache-version: "d${{ matrix.datasets }}-m${{ matrix.miprov2 }}-e${{ matrix.evals }}"`
- Create separate caches per configuration
- **Result**: Created separate caches but frozen mode still failed
- **Why it failed**: ruby/setup-ruby's bundler-cache always uses --deployment, incompatible with dynamic Gemfile
- **Evidence**: Cache key showed `v-d0-m0-e1` but error persisted: "You have deleted from the Gemfile"

### 2. Install All System Dependencies Everywhere
- Set all matrix jobs to `datasets: '1'`, `miprov2: '1'`
- Install Arrow and OpenBLAS in every job
- **Rejected**: Wasteful, adds 2-3 minutes to each job

### 3. Disable Bundler Cache Completely
- Set `bundler-cache: false`, run `bundle install` without caching
- **Considered**: Works (proven in commit d62c2db) but too slow (~3-5min per job)
- **Status**: Used as fallback if manual caching fails

### 4. Multiple Gemfiles with Separate Lockfiles
- Create Gemfile.datasets, Gemfile.miprov2, etc.
- Use BUNDLE_GEMFILE environment variable
- **Rejected**: Major refactor, non-standard, complex to maintain

## References

- [ruby/setup-ruby documentation](https://github.com/ruby/setup-ruby)
- [GitHub Actions cache documentation](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [actions/cache documentation](https://github.com/actions/cache)
- Issue thread: Multiple failed CI attempts from commits f5a8faf through e430187
- Working baseline: Commit d62c2db (bundler-cache: false)
- Failed cache-version attempt: Run https://github.com/vicentereig/dspy.rb/actions/runs/18749633544

## Notes

### Discovery Process

1. **Initial hypothesis**: ruby/setup-ruby's bundler-cache shares cache across matrix jobs
2. **First fix attempt (cache-version)**: Create separate caches per configuration
3. **Discovery**: Cache separation worked (key showed `v-d0-m0-e1`) but error persisted
4. **Root cause found**: ruby/setup-ruby ALWAYS uses `--deployment` mode with bundler-cache
5. **Final solution**: Manual caching without frozen mode

### Why Manual Caching is Necessary

The cache-version parameter works as documented - it DOES create separate caches. However, it doesn't solve the fundamental incompatibility between:
- Bundler's frozen mode (--deployment)
- Dynamic Gemfile (conditional gemspecs based on environment variables)
- Static Gemfile.lock (contains all possible gems)

Manual caching with actions/cache allows us to avoid frozen mode entirely, letting bundler adapt the lockfile to match the dynamic Gemfile at runtime.
