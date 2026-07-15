# DSPy.rb Documentation Site

This directory contains the DSPy.rb documentation site built with Bridgetown and Tailwind CSS.

## Quick Start

### Prerequisites
- Ruby from the repository's `.ruby-version` (the authoritative rbenv/CI version)
- Bun 1.3.14
- Bundler

`.tool-versions` retains Ruby 3.3.7 for asdf compatibility; it does not override
the `.ruby-version` pin used by this repository's documented commands and CI.

### Development

1. From the repository's `docs/` directory, install dependencies:
```bash
rbenv exec bundle install
bun install --frozen-lockfile
```

2. From `docs/`, start the development server:
```bash
rbenv exec bundle exec bridgetown start
```

3. Open http://localhost:4000.

### Building for Production

From the repository root:

```bash
cd docs
BRIDGETOWN_ENV=production rbenv exec bundle exec bridgetown build
```

Bridgetown writes the built site to `output/`.

### Documentation quality

From the repository root, install both bundles and the asset dependencies once:

```bash
rbenv exec bundle install
cd docs
rbenv exec bundle install
bun install --frozen-lockfile
bunx playwright install chromium
cd ..
```

Then run the one local and CI quality command from the repository root:

```bash
ruby docs/scripts/check_documentation_quality.rb
```

With rbenv, the repository's shim selects `.ruby-version` automatically;
`rbenv exec` is an equivalent explicit wrapper.

The command runs 22 fail-fast steps: it validates source structure and redirect
script escaping, runs only the explicitly marked Quick Start, Toolsets, and
long-page snippet specs, cleans and builds the production site once, and
validates rendered routes, fragments, packages, and `llms*.txt`.
Generic Ruby fences, Rails/provider recipes, and VCR examples are not selected
for execution. Snippet specs use sentinel credentials and must prove that no
live HTTP request occurs. The internal-link check resolves local links and
anchors without fetching external URLs. The economy audit is advisory: its
findings do not fail the command, while invocation, configuration, parse, and
read failures do.

## Structure

- `src/` - Source files for the documentation
  - `_layouts/` - Page layouts (home, docs)
  - `getting-started/` - Getting started guides
  - `core-concepts/` - Core concepts documentation
  - `optimization/` - Optimization guides
  - `advanced/` - Advanced topics
  - `production/` - Production deployment guides
- `frontend/` - JavaScript and CSS assets
- `output/` - Built site (git ignored)

## Design System

The site uses Tailwind components for its documentation layout:
- Sidebar navigation
- Mobile and desktop layouts
- Syntax highlighting for code blocks
- Typography styles from `@tailwindcss/typography`

## GitHub Pages Deployment

Pushing to `main` triggers the GitHub Actions build and deployment. The published site is at https://oss.vicente.services/dspy.rb/.

## Site Components

- **Navigation**: Sidebar, mobile menu, breadcrumbs, and previous/next traversal
- **Code rendering**: Syntax-highlighted fenced code blocks
- **Metadata**: Page frontmatter and generated social cards
- **Deployment**: GitHub Actions builds and publishes the Bridgetown output

## Writing Documentation

1. Create markdown files in the appropriate directory
2. Add frontmatter with `layout`, `title`, and `description`
3. Use the `docs` layout for documentation pages
4. Add the page once to `src/_data/documentation_navigation.yml`

Example frontmatter:
```yaml
---
layout: docs
title: Your Page Title
description: Brief summary for route and search discovery
---
```

The navigation manifest is the only source for task buckets, sidebar labels,
breadcrumbs, contextual exits, and previous/next traversal. Each entry has
`section`, `label`, normalized `url`, repository-relative `source`, `status`,
and `traversal`. Use `published` for rendered pages,
`unpublished` or `draft` for existing pages excluded from navigation, and
`planned` for a page without a source file yet. Use `none` when a direct-entry
or multi-audience page should remain in navigation without joining a pager.
Never add `breadcrumb`, `nav`,
`prev`, `next`, `nav_order`, `order`, or `parent` to page frontmatter.

Run the root documentation-quality command after a navigation change. It checks
the source manifest before the build, then checks the desktop sidebar, mobile
sidebar, breadcrumbs, contextual exits, and traversal boundaries against the
fresh production output.

## Troubleshooting

Run these commands from `docs/`.

If Bundler reports missing dependencies:
```bash
rbenv exec bundle check
rbenv exec bundle install
```

If Bun reports missing front-end packages:
```bash
bun install --frozen-lockfile
```
