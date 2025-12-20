# SEO Keyword Strategy: Low-CTR High-Impression Keywords

This document tracks keyword performance from Google Search Console and outlines improvement strategies.

## Current Status (December 2025)

Based on Google Search Console data (last 3 months):
- **Total Clicks**: 139
- **Total Impressions**: 12,146
- **Average CTR**: 1.1% (target: 2-3%)
- **Average Position**: 7.4
- **Total Queries**: 179

---

## Priority 1: High-Impression Low-CTR Keywords (Action Taken)

| Query | Impressions | CTR | Position | Status |
|-------|-------------|-----|----------|--------|
| toon vs csv | 380 | 0.5% | 9.0 | ✅ Title/desc optimized Dec 2025 |
| miprov2 paper | 103 | 1.9% | 7.3 | ✅ New article created Dec 2025 |
| mipro v2 | - | 4.1% | 5.4 | ✅ Covered by MIPROv2 docs |
| miprov2 prompt optimization | - | 3.8% | 8.2 | ✅ New article targets this |

## Priority 2: MIPROv2 Query Cluster

Strong search interest in MIPROv2 paper/research content:

| Query | Position | Notes |
|-------|----------|-------|
| miprov2 arxiv | 4.6 | 7.1% CTR - good |
| miprov2 optimizer | 3.7 | 14.3% CTR - good |
| miprov2 dspy paper | 5.9 | New article targets |
| miprov2 prompt optimizer paper | 5.8 | New article targets |
| dspy miprov2 | 64.0 | Poor position - need backlinks |

**Action**: Created `/blog/articles/miprov2-paper-implementation/` with paper citations and Ruby examples.

## Priority 3: TOON/CSV Query Cluster

| Query | CTR | Position | Notes |
|-------|-----|----------|-------|
| dspy toon | 66.7% | 3.0 | ✅ Excellent |
| toon nested data | 25% | 7.5 | Good |
| toon is just csv | 11.1% | 6.3 | Good |
| toon csv | - | 9.1 | Title optimized |
| csv vs toon | - | 8.3 | Title optimized |

**Action**: Updated TOON vs CSV article title to match search intent.

## Priority 4: DSPy Documentation Queries

Many queries for DSPy documentation land on our Ruby docs:

| Query | Position | Opportunity |
|-------|----------|-------------|
| dspy signatures documentation | 7.8 | ✅ Title added |
| dspy chainofthought module documentation | 7.4 | Consider dedicated page |
| dspy predict module documentation | 8.5 | ✅ Predictors title added |
| dspy codeact module | 6.2 | Existing page |
| dspy modules documentation | 5.0 | ✅ Title added |

---

## Well-Performing Queries (Monitor)

These queries have good CTR - protect their performance:

| Query | CTR | Position | Page |
|-------|-----|----------|------|
| dspy toon | 66.7% | 3.0 | TOON article |
| dspy evals | 50% | 21.0 | Evaluation docs |
| toon nested data | 25% | 7.5 | TOON vs CSV |
| gepa example | 25% | 9.0 | GEPA docs |
| miprov2 optimizer | 14.3% | 3.7 | MIPROv2 docs |
| toon is just csv | 11.1% | 6.3 | TOON vs CSV |

---

## Queries Needing Better Positioning

These queries have poor positions (>20) despite relevance:

| Query | Position | Notes |
|-------|----------|-------|
| dspy | 45.1 | Main Python DSPy ranks higher |
| dspy documentation | 47.0 | Python docs dominate |
| dspy github | 25.0 | Python repo ranks higher |
| dspy tutorial | 17.0 | Need more tutorial content |
| dspy prompt optimization | 63.4 | Poor position |
| dspy gemini | 32.0 | Consider Gemini-focused content |

**Strategy**: Focus on "dspy ruby" and "dspy.rb" variants where we can rank better.

---

## Content Gaps Identified

Based on search queries we're not fully serving:

1. **BAML queries** (baml docs, baml format, baml types)
   - Consider dedicated BAML documentation page
   - Current coverage is in articles only

2. **Evaluation/Metrics queries** (dspy evaluate metric, dspy evaluator)
   - Strengthen evaluation documentation SEO

3. **Tool class queries** (dspy tool class, dspy.tool)
   - Consider dedicated Toolsets SEO optimization

4. **Langfuse queries** (langfuse tracing, dspy langfuse)
   - Existing observability article could be optimized

---

## Implementation Log

### December 2025 Updates

1. **Meta Content Optimization** (9 pages)
   - Homepage: Stanford authority signal
   - TOON vs CSV: "nested data" in title
   - Prompt Optimization: MIPROv2 & GEPA keywords
   - GEPA: "Optimizer" keyword
   - JSON Modes: Benchmark teaser
   - Core Concepts: Component names
   - Signatures, Modules, Predictors: Explicit titles

2. **New Content**
   - Created MIPROv2 paper article targeting research queries
   - Added internal links from TOON articles to core docs

3. **Homepage Strengthening**
   - Stanford mention above fold
   - Benefit checkmarks
   - Clearer secondary CTA

---

## Measurement Schedule

- **Weekly**: Check Search Console for position changes
- **Monthly**: Full keyword performance review
- **After deployments**: Monitor CTR changes over 2-4 weeks

---

*Data source: Google Search Console for vicentereig.github.io/dspy.rb/*
*Last updated: December 20, 2025*
