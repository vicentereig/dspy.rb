# Design — DSPy.rb docs

A locked design system for this site. Every page redesign reads this file before
emitting code. Do not regenerate per page — extend or amend this file when the
system needs to grow.

Genre: **editorial** (content-led developer documentation). The voice is the
blog's: left-biased, serif-led, hairlines instead of card borders, generous
whitespace, quiet motion. The home and docs pages are pulled up to this voice.

## Macrostructure family

Pages within a family share the family's shape; they vary only in component
archetypes.

- **Marketing pages** (`/`): **Workbench** — the code demo is the centerpiece,
  headline is left-biased, composition is asymmetric. No centered hero stack.
- **Content pages** (docs, blog posts): **Long Document** — editorial prose,
  hairline rules, strong typographic hierarchy, asymmetric sidebar.
- **Hub pages** (blog index, section landings): **Editorial list** — left-aligned
  serif title, quiet metadata, link list with descriptions.

## Theme

Warm paper, warm ink, coral accent held under ~5% per viewport. No pure white,
no pure black (editorial rule). Brand hues preserved exactly; only paper/ink are
newly tinted warm.

- `--color-paper`    oklch(98.8% 0.006 70)   /* warm ivory */
- `--color-paper-2`  oklch(96.6% 0.008 70)   /* alternating band */
- `--color-ink`      oklch(22% 0.02 50)       /* warm near-black — headings */
- `--color-ink-2`    oklch(42% 0.02 55)       /* warm gray — body */
- `--color-ink-3`    oklch(55% 0.015 60)      /* muted — captions */
- `--color-rule`     oklch(90% 0.01 70)       /* hairline */
- `--color-accent`   oklch(69.4% 0.169 35.3)  /* coral #f26f4e (exact) */
- `--color-accent-hover` oklch(62% 0.17 35)   /* coral pressed */
- `--color-accent-ink`   oklch(99% 0 0)       /* text on coral fill */
- `--color-link`     oklch(52% 0.10 166)      /* green, darkened for AA on paper */
- `--color-highlight` oklch(87.7% 0.071 169.7)/* mint — selection + mark band */
- `--color-focus`    oklch(69.4% 0.169 35.3)  /* coral ring */

Note: `#4aa885` at its native lightness (66.5%) fails AA as body-size text on
paper, so `--color-link` darkens the green to ~52% L. Coral is fills/borders/
large-text only — never body-size text on paper.

## Typography

- Display: **Newsreader**, weight 600–700, style **normal** (roman only).
- Body:    **Manrope**, weight 400–600.
- Mono:    **JetBrains Mono**, weight 400–700.
- Display tracking: -0.02em on large sizes.
- Type scale anchor: `--text-display` = clamp(2.5rem, 6vw, 4.5rem).

## Spacing

4-point named scale. Values live in `tokens.css`. Pages use named tokens
(`var(--space-md)`), never raw values.

## Motion

- Easings: `--ease-out` = cubic-bezier(0.16, 1, 0.3, 1).
- Reveal pattern: one orchestrated entrance fade (+ small slide) per page. No
  scroll-triggered cascades, no bounces.
- Reduced-motion fallback: opacity-only, ≤ 150 ms.

## Microinteractions stance

- Silent success. No celebratory toasts.
- Hover delay 800 ms on tooltips; focus delay 0 ms.
- Links: draw an underline on hover, don't just recolor.

## CTA voice

- Primary CTA: coral fill, `--color-accent-ink` text, `--radius-input` corners,
  padding `--space-2xs --space-md`. Copy is an imperative verb ("Get started").
- Secondary CTA: text + arrow, ink color, underline on hover. No second fill.

## Per-page allowances

- Marketing pages MAY use Tier-A CSS art / Tier-B SVG enrichment.
- Content pages: typography only.
- Hub pages: typography only.

## What pages MUST share

- The wordmark (`DSPy.rb`, Newsreader 600).
- The coral accent and its placement (≤ 5% per viewport).
- Newsreader display + Manrope body.
- The CTA voice (shape, radius, padding rhythm).
- Hairlines (`--color-rule`) instead of card borders + shadows.

## What pages MAY differ on

- Macrostructure within the page-type family.
- Hero archetype (marketing only).
- Enrichment — marketing pages only, Tier-A or Tier-B.

## Exports

See `tokens.css` at the docs root for the drop-in `:root` block. The Tailwind
config maps its color utilities (`dspy-coral`, `dspy-link`, etc.) onto these
tokens so existing utility classes keep working.
