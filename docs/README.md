# DSPy.rb Documentation Site

This is the documentation website for DSPy.rb, built with Bridgetown.

The site now centers on a **single long-form homepage tutorial** instead of the usual docs-portal structure. The homepage is the primary reading experience. The rest of the site remains as secondary reference material.

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
  - `_layouts/` - Page layouts, including the long-form homepage layout
  - `index.md` - The primary single-page agent tutorial
  - `_articles/` - Supporting blog-style articles
  - `getting-started/`, `core-concepts/`, `optimization/`, `advanced/`, `production/` - Secondary reference material
- `frontend/` - JavaScript and CSS assets
- `output/` - Built site (git ignored)

## 🎨 Design Direction

The homepage borrows from the `vicente.services` long-form blog style:

- editorial typography instead of docs-portal chrome
- a visible table of contents for long reading sessions
- responsive single-page layout for desktop and mobile
- syntax highlighting for code blocks
- predictable anchor structure for human and agent readers

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

Prefer adding or improving content in the homepage tutorial first.

Reach for secondary pages only when the material is genuinely reference-heavy or too detailed for the main narrative.

For the homepage:

1. Edit `src/index.md`
2. Keep major sections anchored and easy to scan
3. Follow the `What? / So What? / What Not?` section pattern
4. Prefer diffs and small code blocks over broad feature catalogs

For secondary reference pages, continue using the existing page layouts and frontmatter conventions where appropriate.

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
