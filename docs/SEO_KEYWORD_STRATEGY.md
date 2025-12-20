# SEO Keyword Strategy: Low-CTR High-Impression Keywords

This document outlines the strategy for identifying and improving pages with high impressions but low click-through rates.

## Current Status (December 2025)

Based on the Google Search Console report:
- **Average CTR**: 1.1% (target: 2-3%)
- **Average Position**: 7.4
- **Total Impressions**: 12.1K over 3 months

### Already Addressed

The following pages had meta content optimized in the December 2025 SEO update:

| Page | Impressions | Old CTR | Changes Made |
|------|-------------|---------|--------------|
| Homepage | 516 | 1% | Stanford authority signal, benefit bullets |
| TOON vs CSV | 1,086 | 0.5% | Search intent matching, "nested data" keywords |
| JSON Modes Comparison | 729 | 1% | Benchmark teaser, model names |
| GEPA | 737 | 0.7% | "Optimizer" keyword, demo emphasis |
| Prompt Optimization | 300 | - | MIPROv2 & GEPA algorithm keywords |

## Strategy for Ongoing Improvement

### 1. Monthly Keyword Review

Check Search Console monthly for queries with:
- **High impressions (>100/month)** + **Low CTR (<2%)**
- These represent ranking success but messaging failure

### 2. Content Gap Analysis

For each low-CTR keyword, ask:
1. Does the page title contain the exact search term?
2. Does the meta description address the searcher's intent?
3. Is there a clear value proposition in the first 160 characters?

### 3. Intent Matching Framework

| Search Intent | Strategy |
|---------------|----------|
| **Informational** ("what is DSPy") | Lead with definition, promise clarity |
| **Comparative** ("dspy vs langchain") | Highlight benchmark data, direct comparison |
| **Tutorial** ("dspy ruby tutorial") | Promise step count, timeframe |
| **Research** ("miprov2 paper") | Cite sources, academic credibility |

### 4. Title Formula Templates

Based on search intent:

**For Tutorials:**
```
[Topic] in Ruby: [Benefit] in [Time] | DSPy.rb
Example: "ReAct Agents in Ruby: Build Your First Agent in 10 Minutes"
```

**For Comparisons:**
```
[A] vs [B]: [Key Differentiator] | DSPy.rb
Example: "TOON vs CSV: Why Nested Data Needs a New Format"
```

**For Features:**
```
[Feature]: [Benefit] in Ruby | DSPy.rb
Example: "Automatic Prompt Optimization: Stop Guessing at Prompts"
```

**For Research:**
```
[Paper/Topic]: [Implementation Angle] | DSPy.rb
Example: "MIPROv2 Paper: How Stanford's Optimizer Works in Ruby"
```

### 5. Description Formula Templates

Use the AIDA framework in 150-160 characters:

```
[Pain Point]. [Solution]. [Proof Point]. [CTA].

Example:
"CSV breaks with nested LLM data. TOON preserves Ruby structs while cutting tokens. See the benchmark."
```

## Priority Keywords to Monitor

Based on the SEO report, watch these query patterns:

### High Priority (Research Interest)
- "miprov2" / "miprov2 paper" / "miprov2 prompt optimization"
- "dspy python" / "dspy ruby" (comparison searches)
- "prompt optimization" / "automatic prompt optimization"

### Medium Priority (Feature Discovery)
- "ruby llm" / "ruby ai" / "ruby openai"
- "structured outputs ruby"
- "chain of thought ruby"

### Lower Priority (Long-tail)
- Specific model combinations ("gemini ruby", "anthropic ruby")
- Error-related queries ("json parsing llm")

## Implementation Checklist

For each low-CTR keyword identified:

1. [ ] Find the ranking page in Search Console
2. [ ] Read the current title and description
3. [ ] Check if the exact search term appears
4. [ ] Verify the intent matches the content
5. [ ] Update meta content following templates above
6. [ ] Build and deploy
7. [ ] Monitor CTR change over 2-4 weeks

## Measurement

Track in Search Console:
- **Before/After CTR** for each updated page
- **Position stability** (ensure optimization doesn't hurt rankings)
- **Click growth** (absolute clicks, not just rate)

Review quarterly to assess strategy effectiveness.

---

*Last updated: December 2025*
*Next review: January 2025*
