# DSPy Datasets & Parquet Migration Plan

## Goals
- Ship three gems from the monorepo root: `dspy`, `dspy-datasets`, and `gepa`.
- Introduce a shared dataset registry exposing `DSPy::Datasets.list` and `DSPy::Datasets.fetch`.
- Migrate ADE examples onto the new dataset loader backed by HuggingFace Parquet files.
- Keep CI fast and green while system dependencies for Apache Arrow/Parquet are introduced.

## Dependency Checklist

### macOS (development)
- Homebrew packages: `apache-arrow` and `apache-arrow-glib`.
- Ruby build deps via `rbenv`: `ruby-build` up to date, ensure `pkg-config`, `gobject-introspection`, and `glib` headers are present.
- Bundler: add `red-parquet (~> 21.0)` to `dspy-datasets`.

### Debian / Ubuntu
```sh
sudo apt update
sudo apt install -y ca-certificates lsb-release wget build-essential ruby-dev pkg-config gobject-introspection libglib2.0-dev zlib1g-dev liblzma-dev
wget https://packages.apache.org/artifactory/arrow/$(lsb_release --id --short | tr 'A-Z' 'a-z')/apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb
sudo apt install -y ./apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb
sudo apt update
sudo apt install -y libarrow-glib-dev libparquet-glib-dev
```

### AlmaLinux / CentOS / RHEL
```sh
sudo yum install -y epel-release || sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(cut -d: -f5 /etc/system-release-cpe | cut -d. -f1).noarch.rpm
sudo yum install -y https://packages.apache.org/artifactory/arrow/centos/$(cut -d: -f5 /etc/system-release-cpe | cut -d. -f1)/apache-arrow-release-latest.rpm
sudo yum install -y gcc gcc-c++ make ruby-devel pkgconfig gobject-introspection-devel arrow-glib-devel parquet-glib-devel
```

### Amazon Linux 2023
```sh
sudo dnf install -y https://packages.apache.org/artifactory/arrow/amazon-linux/$(cut -d: -f6 /etc/system-release-cpe)/apache-arrow-release-latest.rpm
sudo dnf install -y gcc gcc-c++ make ruby-devel pkgconfig gobject-introspection-devel arrow-glib-devel parquet-glib-devel
```

### Alpine (fallback)
- Prefer glibc-based images; Alpine requires compiling Arrow from source with `apk add build-base cmake ninja gobject-introspection-dev glib-dev zlib-dev lz4-dev zstd-dev` and enabling Parquet+GLib manually.

## Work Breakdown (Bottom-Up Execution)
1. **Dependencies & Tooling**
   - Validate red-parquet install path under `rbenv` (done locally).
   - Write Debian/RHEL installation snippets for CI/docker images.
   - Capture local `bundle config` updates if native gems need flags.
2. **Gem Split groundwork**
   - Create `dspy-datasets.gemspec` and `gepa.gemspec`; update `Gemfile`, `Rakefile`, and `bundle exec` tasks.
   - Re-home library files under each gem without changing APIs.
   - Add minimal specs/CI jobs to ensure each gem still builds.
3. **Dataset Registry**
   - Introduce manifest (YAML/JSON) describing datasets, parity-tested on ADE first.
   - Implement `DSPy::Datasets.list` and `DSPy::Datasets.fetch` on top of red-parquet with JSON fallback.
   - Cover with unit specs and regression tests for cache behaviour.
4. **Consumers & Examples**
   - Update ADE helper modules/tests to use registry-backed loader.
   - Refactor `examples/ade_optimizer_gepa/main.rb` and `examples/ade_optimizer_miprov2/main.rb`.
   - Re-run demos with `bundle exec ruby …` ensuring rbenv Ruby in use.
5. **CI / Release Hygiene**
   - Convert GitHub Actions to matrix over `dspy`, `dspy-datasets`, `gepa`.
   - Configure tag-triggered release workflow for each gem.
   - Document Arrow system-deps in README / Wiki.

## Why Bottom-Up?
- Establishing dependency support and gem boundaries first keeps downstream changes (registry, examples, CI) straightforward.
- Once low-level loading and packaging are stable, higher-level APIs/examples can iterate quickly without fighting packaging regressions.
- Each milestone creates a natural commit/pr checkpoint for the early PR flow.
