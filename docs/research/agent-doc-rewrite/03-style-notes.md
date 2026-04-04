# Style Notes

Date: 2026-04-04

These notes capture the blog traits worth carrying into the DSPy.rb docs rewrite.

## Source

- `../website/src/_layouts/humanist_post.liquid`
- `../website/frontend/styles/humanist.css`
- `../website/src/_posts/2025-12-29-the-auditability-gap.md`

## Keep

### Humanist typography

- serif-forward headline voice
- calm sans-serif body copy
- comfortable line height
- readable measure, not dashboard-width prose

### Long-form rhythm

- short paragraphs
- strong section titles
- occasional visual emphasis instead of repeated card grids
- code blocks used as evidence, not decoration

### Gentle structure

- one page
- clear hero
- visible table of contents
- minimal chrome
- no sidebar-docs mental model

### Editorial emphasis

- highlighted words in the hero
- subtle dividers
- pull-quote / note / checklist patterns when needed
- fewer "feature" boxes, more argument

## Avoid

- docs-portal sidebars
- "getting started / core concepts / advanced" as the primary reading model
- repetitive marketing sections
- giant feature matrices above the actual tutorial
- overly saturated gradients that compete with the reading experience

## Practical Translation To This Repo

- use a custom long-form layout for the homepage
- add a sticky desktop ToC and a simple mobile ToC
- keep the page scannable for agents with explicit anchors and predictable subsection labels
- let the homepage be the documentation product

## Content Tone

The page should read like:

- a tutorial
- an argument
- a field guide

It should not read like:

- API reference first
- a landing page with docs attached
- a catalog of unrelated concepts
