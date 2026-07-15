# DSPy.rb Documentation Site

This is the documentation website for DSPy.rb, built with Bridgetown and styled with TailwindUI components.

## 🚀 Quick Start

### Prerequisites
- Ruby 3.0+
- Bun 1.0+
- Bundler

### Development

1. Install dependencies:
```bash
bundle install
bun install
```

2. Start the development server:
```bash
bundle exec bridgetown start
```

3. View the site at http://localhost:4000

### Building for Production

```bash
BRIDGETOWN_ENV=production bundle exec bridgetown build
```

The built site will be in the `output/` directory.

## 📁 Structure

- `src/` - Source files for the documentation
  - `_layouts/` - Page layouts (home, docs)
  - `getting-started/` - Getting started guides
  - `core-concepts/` - Core concepts documentation
  - `optimization/` - Optimization guides
  - `advanced/` - Advanced topics
  - `production/` - Production deployment guides
- `frontend/` - JavaScript and CSS assets
- `output/` - Built site (git ignored)

## 🎨 Design System

The site uses TailwindUI components for a professional, consistent design:
- Modern documentation layout with sidebar navigation
- Responsive design for mobile and desktop
- Syntax highlighting for code blocks
- Type-safe typography with @tailwindcss/typography

## 🚀 GitHub Pages Deployment

The site is configured for GitHub Pages deployment:

1. Push to the `main` branch
2. GitHub Actions will automatically build and deploy
3. View at https://oss.vicente.services/dspy.rb/

## 🛠️ Key Features

- **TailwindUI Integration**: Professional documentation design
- **Responsive Navigation**: Collapsible sidebar for mobile
- **Syntax Highlighting**: Beautiful code blocks
- **SEO Optimized**: Meta tags and structured content
- **Fast Build Times**: Optimized asset pipeline
- **GitHub Pages Ready**: Automated deployment workflow

## 📝 Writing Documentation

1. Create markdown files in the appropriate directory
2. Add frontmatter with `layout`, `title`, and `description`
3. Use the `docs` layout for documentation pages
4. Add the page once to `src/_data/documentation_navigation.yml`

Example frontmatter:
```yaml
---
layout: docs
title: Your Page Title
description: Brief description for SEO
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

Run `rbenv exec ruby scripts/validate_documentation_navigation.rb` from `docs/`
after a navigation change. Pass `--output output` after a production build to
check the desktop sidebar, mobile sidebar, breadcrumbs, contextual exits, and
each traversal's boundaries.

## 🐛 Troubleshooting

If you encounter bundler version conflicts:
```bash
bundle exec bridgetown build
bundle exec bridgetown start
```

For missing dependencies:
```bash
bundle install
bun install
```
