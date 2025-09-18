---
layout: blog
title: "JSON Extraction in Production: When to Use Each DSPy.rb Strategy"
date: 2025-09-14
description: "Performance analysis and decision guide for choosing the right JSON extraction strategy across AI providers"
author: "Vicente Reig"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/json-modes-comparison/"
---

Getting reliable, structured data from Large Language Models is crucial for production applications. DSPy.rb solves this with five different JSON extraction strategies, each optimized for specific AI providers. After benchmarking across 13 AI models, here's your complete guide to choosing the right approach.

This test used baseline DSPy.rb's Enhanced Prompts without any optimization beyond writing modular and typed Signatures. For production workloads, consider [prompt optimization](https://vicentereig.github.io/dspy.rb/optimization/prompt-optimization/) to improve performance further.

## Five Extraction Strategies

- **Enhanced Prompting**: Universal compatibility (works with all 13 models tested). This is [DSPy's](https://dspy.ai) style JSON Schema prompting.
- **OpenAI Structured Output**: Native API enforcement for GPT models. Including nuances on their JSON Schema implementation.
- **Anthropic Tool Use**: Function calling for all Claude models.
- **Anthropic Extraction**: Text completion with guided parsing for Claude.
- **Gemini Structured Output**: Native structured generation for Gemini 1.5 Pro.

## Performance Benchmark Results

Even though reliability wasn't the goal of this benchmark, all strategies achieved 100% success rate in generating JSON
and handling potentially invalid responses.

| Strategy | Response Time | Success Rate | Token Efficiency | Cost (Best Model) |
|----------|---------------|--------------|------------------|-------------------|
| **Gemini Structured** | 3.42s | 100% | 800 tokens | $0.0019 |
| **Anthropic Tool Use** | 6.23s | 100% | 800-1500 tokens | $0.001408 |
| **Anthropic Extraction** | 6.41s | 100% | 800-1500 tokens | $0.001408 |
| **Enhanced Prompting** | 7.52s | 92.3% | 800-1500 tokens | $0.000114 |
| **OpenAI Structured** | 9.39s | 100% | 1200-1500 tokens | $0.000342 |

## Token Consumption Analysis

**Most Token Efficient (800 tokens):**
- Claude 3.5 Haiku, Gemini models, o1-mini

**Standard Usage (1200 tokens):**  
- GPT-4o series, Claude Sonnet 4

**Highest Usage (1500 tokens):**
- GPT-5 series, Claude Opus 4.1

**Cost per Token Leaders:**
1. Gemini 1.5 Flash: $0.0000001425 per token
2. GPT-5-nano: $0.00000011 per token  
3. GPT-4o-mini: $0.000000285 per token

**Token Insight:** Strategy choice doesn't significantly impact token usage—it's primarily model-dependent. Focus on model selection for token efficiency.

## Quick Decision Matrix

| Use Case | Recommended Strategy | Model | Cost | Speed |
|----------|---------------------|-------|------|-------|
| **Startup/MVP** | Enhanced Prompting | Gemini Flash | $0.000114 | 7.52s |
| **High Volume** | Gemini Structured | Gemini Pro | $0.0019 | 3.42s |
| **Enterprise Multi-Provider** | Enhanced Prompting | Multiple | Varies | 7.52s |
| **Maximum Reliability** | Provider-Specific | Any Compatible | Varies | 6.23-9.39s |
| **Cost-Sensitive** | Enhanced Prompting | Gemini Flash | $0.000114 | 7.52s |

## Key Findings

- **Speed Champion**: Gemini Structured Output (3.42s) but limited to one model
- **Universal Choice**: Enhanced Prompting works across all providers with 92.3% success  
- **Cost Winner**: Gemini Flash + Enhanced Prompting at $0.000114 per extraction
- **Reliability**: All provider-specific strategies achieve 100% success rates
- **Token Efficiency**: Choose Claude Haiku or Gemini for lowest token consumption

## Implementation

DSPy.rb uses [Signatures](https://vicentereig.github.io/dspy.rb/core-concepts/signatures/) to define structured inputs and outputs. Here's an example using [T::Enum types](https://vicentereig.github.io/dspy.rb/advanced/complex-types/):

```ruby
class SearchDepth < T::Enum
  enums do
    Shallow = new('shallow')
    Medium = new('medium')
    Deep = new('deep')
  end
end

class DeepResearch < DSPy::Signature
  input do
    const :query, String
    const :effort, SearchDepth, default: SearchDepth::Shallow
  end
  output { const :summary, String }
end

# Configure DSPy with your preferred model
DSPy.configure do |c|
  c.lm = DSPy::LM.new('gemini/gemini-1.5-flash')
end

predictor = DSPy::Predict.new(DeepResearch)
search_result = predictor.call(query: "How does Stripe's API design influence developer adoption?")
puts "Summary: #{search_result.summary}"
```

This example shows DSPy.rb's core components working together:
- **[Configuration](https://vicentereig.github.io/dspy.rb/getting-started/core-concepts/)**: Set up your language model
- **[Predictors](https://vicentereig.github.io/dspy.rb/core-concepts/predictors/)**: The `DSPy::Predict` class handles JSON extraction automatically

## Recommendations

**Start with Enhanced Prompting + Gemini Flash** for most applications:
- Universal compatibility across all providers
- Lowest cost at $0.000114 per extraction
- Easy provider switching without code changes
- Consider [benchmarking your own workloads](https://vicentereig.github.io/dspy.rb/optimization/benchmarking-raw-prompts/)

**Optimize later** with provider-specific strategies for critical use cases requiring 100% reliability, or use [prompt optimization](https://vicentereig.github.io/dspy.rb/optimization/prompt-optimization/) to improve Enhanced Prompting performance. Set up [evaluation metrics](https://vicentereig.github.io/dspy.rb/optimization/evaluation/) to measure improvement.

**Economic Reality:** Gemini Flash costs 144x less than Claude Opus while delivering production-quality results—you can perform 144 extractions for the cost of one premium extraction.

For enterprise deployments, implement [production observability](https://vicentereig.github.io/dspy.rb/production/observability/) to monitor extraction quality across providers.

## Future: BAML-Inspired Enhanced Prompting

We're developing [sorbet-baml](https://vicentereig.github.io/sorbet-baml/), a next-generation approach to Enhanced Prompting that could reduce token usage by 50-70% while improving accuracy. This initiative ([GitHub #70](https://github.com/vicentereig/dspy.rb/issues/70)) transforms verbose JSON schemas into TypeScript-like syntax with inline comments:

**Current JSON Schema:** 150 tokens
**BAML Format:** 45 tokens (70% reduction)

Expected benefits:
- **Lower costs**: Dramatically reduced token consumption for complex schemas
- **Better accuracy**: Up to 20% improvement for nested structures
- **Universal compatibility**: Works with all providers (OpenAI, Anthropic, Gemini, Ollama)

This enhancement will integrate seamlessly with DSPy.rb's existing Enhanced Prompting strategy, providing automatic optimization without code changes.

## Related Articles

- [Type-Safe Prediction Objects](https://vicentereig.github.io/dspy.rb/blog/articles/type-safe-prediction-objects/) - Deep dive into DSPy.rb's type system
- [Under the Hood: JSON Extraction](https://vicentereig.github.io/dspy.rb/blog/articles/under-the-hood-json-extraction/) - Technical details of extraction strategies
- [JSON Parsing Reliability](https://vicentereig.github.io/dspy.rb/blog/articles/json-parsing-reliability/) - Techniques for robust JSON handling

---

*Benchmark: 27 tests across 5 strategies and 13 AI models. Total cost: $0.2302. September 14, 2025.*
