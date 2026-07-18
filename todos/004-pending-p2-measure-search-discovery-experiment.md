---
status: pending
priority: p2
issue_id: "004"
tags: [documentation, seo, geo, analytics]
dependencies: []
---

# Measure a Bounded Search-Discovery Experiment

## Problem Statement

DSPy.rb has strong technical documentation and basic search instrumentation, but there is no attributable evidence that additional GEO/AEO work would improve qualified library discovery, adoption intent, or support load. AI citations and prompt-panel mentions can increase without producing visits or usage.

## Findings

- Google treats GEO/AEO work as ordinary search optimization and says there are no special AI files or schema requirements.
- Bing exposes citation and grounding-query diagnostics, but warns that citation counts do not indicate placement, authority, or importance.
- The site already records Plausible pageviews and outbound-link events, but it does not yet define a qualified-discovery outcome or a treatment/control experiment.
- The current search strategy references the historical `vicentereig.github.io/dspy.rb` Search Console property; measurement should use the canonical `oss.vicente.services/dspy.rb` property.
- Two adversarial reviews recommended capping further work at a 90-day, 4–6-page experiment and rejecting citation-only success criteria.

## Proposed Solutions

### Option 1: Bounded Treatment/Control Experiment

**Approach:** Baseline 4–6 demand-backed pages and comparable control pages, instrument high-intent actions, improve only the treatment pages, and observe for 8–12 weeks.

**Pros:**
- Produces decision evidence tied to real documentation use.
- Caps maintenance cost and limits confounding from site-wide rewrites.
- Preserves improvements that help human readers even if AI-search effects are inconclusive.

**Cons:**
- Low traffic may make the result directional rather than statistically conclusive.
- Search-engine reporting and releases can still confound attribution.

**Effort:** Two maintainer-days initially, then one hour per week for 90 days.

**Risk:** Low

---

### Option 2: Site-Wide GEO/AEO Program

**Approach:** Rewrite the corpus, add query-variant pages, adopt paid AI-rank tracking, and optimize for citation coverage.

**Pros:**
- Produces more content and visibility diagnostics quickly.

**Cons:**
- High maintenance cost, weak causal evidence, duplicate/thin-content risk, and substantial vanity-metric exposure.
- Contradicts current Google guidance against special AI rewrites and scaled query-targeted content.

**Effort:** Multiple weeks plus ongoing tooling cost.

**Risk:** High

## Recommended Action

**To be filled during triage.** Prefer Option 1. Defer paid AI-rank tools, bespoke IndexNow, additional hand-maintained `llms.txt` work, and scaled content clusters until the experiment meets a primary outcome.

## Technical Details

**Likely affected files:**
- `docs/SEO_KEYWORD_STRATEGY.md`
- `docs/frontend/javascript/index.js`
- Four to six selected pages under `docs/src/`
- A versioned prompt panel and weekly measurement ledger

**Candidate primary outcomes:**
- At least 25% relative lift in engaged organic/AI landings versus control, with 30 incremental engaged visits; or
- At least 10 incremental high-intent GitHub, RubyGems, example, or quick-start actions; or
- At least 20% reduction in repeated treatment-topic support questions, with five documented self-served cases.

## Resources

- [Google AI optimization guide](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide)
- [Bing AI Performance](https://blogs.bing.com/webmaster/February-2026/Introducing-AI-Performance-in-Bing-Webmaster-Tools-Public-Preview)
- [OpenAI publisher and developer FAQ](https://help.openai.com/en/articles/12627856-publishers-and-developers-faq)
- [GEO paper](https://arxiv.org/abs/2311.09735)

## Acceptance Criteria

- [ ] Canonical Search Console and Bing Webmaster Tools properties are verified.
- [ ] Four to six treatment pages and comparable controls are preregistered from real demand.
- [ ] Plausible goals exist for selected high-intent actions before treatment begins.
- [ ] At least four weeks of available baseline data are captured.
- [ ] Treatment pages receive bounded, accuracy-preserving improvements and then remain stable.
- [ ] Results are reviewed at days 60 and 90 against primary outcomes and accuracy guardrails.
- [ ] The experiment stops or remains bounded if no primary outcome is met.

## Work Log

### 2026-07-18 - Initial Research and Audit

**By:** Codex

**Actions:**
- Researched current Google, Bing, OpenAI, Schema.org, and academic guidance.
- Audited the Bridgetown source and rendered website.
- Ran two adversarial reviews focused on technical causality and maintainer ROI.
- Defined a capped experiment and explicit stop criteria.

**Learnings:**
- GEO/AEO-specific mechanisms have weaker evidence than ordinary technical SEO and accurate, demand-backed documentation.
- Citation visibility must be evaluated alongside qualified actions and answer accuracy.

## Notes

- GitHub issue creation was unavailable during the audit because the local `gh` session returned HTTP 401, so this follow-up is recorded in the repository's file-todo system.
