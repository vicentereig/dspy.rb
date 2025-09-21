---
layout: blog
title: "JSON Native or Enhanced Prompting? Choosing the Right DSPy.rb Strategy"
date: 2025-09-14
description: "Why Enhanced Prompting beats JSON Native APIs in cost and compatibility plus when to break the rule"
author: "Vicente Reig"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/json-modes-comparison/"
image: /images/og/json-modes-comparison.png
---

Getting reliable, structured data from Large Language Models is crucial for production applications. [DSPy.rb](https://github.com/vicentereig/dspy.rb) solves this with five different JSON extraction strategies, each optimized for specific AI providers. After benchmarking across 14 AI models, here's your complete guide to choosing the right approach.

<style>
/* Charts.css Custom Styling for JSON Modes Comparison */
.charts-css table {
  margin: 2rem auto;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
  border-radius: 8px;
  overflow: hidden;
  background: linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%);
}

.charts-css th {
  background: linear-gradient(135deg, #dc2626 0%, #b91c1c 100%);
  color: white;
  font-weight: 600;
  font-size: 0.875rem;
  text-align: center;
  padding: 0.75rem 0.5rem;
}

.charts-css th[scope="row"] {
  background: linear-gradient(135deg, #374151 0%, #1f2937 100%);
  color: white;
  text-align: left;
  padding-left: 1rem;
  font-size: 0.8rem;
  font-weight: 500;
}

.charts-css td {
  border: 1px solid rgba(209, 213, 219, 0.3);
  transition: all 0.3s ease;
}

.charts-css td:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15);
}

.charts-css .data {
  font-weight: 600;
  font-size: 0.75rem;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
  color: white;
}

/* Responsive adjustments */
@media (max-width: 768px) {
  .charts-css table {
    --labels-size: 80px !important;
    height: 250px !important;
    margin: 1rem auto;
  }
  
  .charts-css th {
    font-size: 0.75rem;
    padding: 0.5rem 0.25rem;
  }
  
  .charts-css th[scope="row"] {
    font-size: 0.7rem;
    padding-left: 0.5rem;
  }
  
  .charts-css .data {
    font-size: 0.7rem;
  }
}

/* Chart specific colors and animations */
.charts-css.bar td::before {
  animation: growWidth 1.5s ease-out;
}

.charts-css.column td::before {
  animation: growHeight 1.5s ease-out;
}

@keyframes growWidth {
  from { width: 0; }
  to { width: var(--size); }
}

@keyframes growHeight {
  from { height: 0; }
  to { height: var(--size); }
}
</style>

This test used baseline [DSPy.rb](https://github.com/vicentereig/dspy.rb)'s Enhanced Prompts without any optimization beyond writing modular and typed Signatures. For production workloads, consider [prompt optimization](https://vicentereig.github.io/dspy.rb/optimization/prompt-optimization/) to improve performance further.

## Five Extraction Strategies

- **Enhanced Prompting**: Universal compatibility (works with all 14 models tested). This is [DSPy's](https://dspy.ai) style JSON Schema prompting.
- **OpenAI Structured Output**: Native API enforcement for GPT models. Including nuances on their JSON Schema implementation.
- **Anthropic Tool Use**: Function calling for all Claude models.
- **Anthropic Extraction**: Text completion with guided parsing for Claude.
- **Gemini Structured Output**: Native structured generation for Gemini models.

## Performance Benchmark Results

Even though reliability wasn't the goal of this benchmark, all strategies achieved 100% success rate in generating JSON
and handling potentially invalid responses.

| Strategy | Response Time | Success Rate | Token Efficiency | Cost (Best Model) |
|----------|---------------|--------------|------------------|-------------------|
| **Gemini Structured** | 4.09s | 100% | 800 tokens | $0.000114 |
| **Anthropic Extraction** | 5.46s | 100% | 800-1500 tokens | $0.001408 |
| **Anthropic Tool Use** | 5.67s | 100% | 800-1500 tokens | $0.001408 |
| **Enhanced Prompting** | 7.98s | 100% | 800-1500 tokens | $0.000114 |
| **OpenAI Structured** | 11.53s | 100% | 1200-1500 tokens | $0.000342 |

### Average Response Times by Strategy

<table class="charts-css bar show-labels data-end data-spacing-8" style="height: 300px; --labels-size: 120px;">
  <thead>
    <tr>
      <th scope="col">Strategy</th>
      <th scope="col">Avg Response Time (seconds)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">Gemini Structured</th>
      <td style="--size: calc(4.09 / 11.53); --color: #22c55e;">
        <span class="data">4.09s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic Extraction</th>
      <td style="--size: calc(5.46 / 11.53); --color: #3b82f6;">
        <span class="data">5.46s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic Tool Use</th>
      <td style="--size: calc(5.67 / 11.53); --color: #8b5cf6;">
        <span class="data">5.67s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Enhanced Prompting</th>
      <td style="--size: calc(7.98 / 11.53); --color: #f59e0b;">
        <span class="data">7.98s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">OpenAI Structured</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">11.53s</span>
      </td>
    </tr>
  </tbody>
</table>

*Based on [benchmark data](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb) across 32 test runs. Gemini Structured Output leads with 4.09s average, while OpenAI Structured Output takes the longest at 11.53s.*

## Token Consumption Analysis

**Most Token Efficient (800 tokens):**
- Claude 3.5 Haiku, Gemini models

**Standard Usage (1200 tokens):**  
- GPT-4o series, Claude Sonnet 4

**Highest Usage (1500 tokens):**
- GPT-5 series, Claude Opus 4.1

**Cost per Token Leaders:**
1. Gemini 1.5 Flash: $0.0000001425 per token
2. GPT-5-nano: $0.00000011 per token  
3. GPT-4o-mini: $0.000000285 per token

### Token Efficiency Distribution Across Models

<table class="charts-css column show-labels data-end data-spacing-4" style="height: 300px; --labels-size: 30px;">
  <thead>
    <tr>
      <th scope="col">Token Usage</th>
      <th scope="col">Number of Models</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">800 tokens</th>
      <td style="--size: 1.0; --color: #22c55e;">
        <span class="data">4 models</span>
      </td>
    </tr>
    <tr>
      <th scope="row">1000 tokens</th>
      <td style="--size: 0.5; --color: #3b82f6;">
        <span class="data">2 models</span>
      </td>
    </tr>
    <tr>
      <th scope="row">1200 tokens</th>
      <td style="--size: 0.75; --color: #f59e0b;">
        <span class="data">3 models</span>
      </td>
    </tr>
    <tr>
      <th scope="row">1500 tokens</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">4 models</span>
      </td>
    </tr>
  </tbody>
</table>

*Most models cluster around maximum efficiency (800 tokens) or maximum context (1500 tokens). Claude 3.5 Haiku and Gemini models lead in efficiency.*

**Token Insight:** Strategy choice doesn't significantly impact token usage—it's primarily model-dependent. Focus on model selection for token efficiency.

### Cost Efficiency by Strategy (Best Model per Strategy)

<table class="charts-css column show-labels data-end data-spacing-6" style="height: 350px; --labels-size: 40px;">
  <thead>
    <tr>
      <th scope="col">Strategy</th>
      <th scope="col">Cost per Extraction</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">Enhanced Prompting</th>
      <td style="--size: calc(0.000114 / 0.0019); --color: #22c55e;">
        <span class="data">$0.000114</span>
      </td>
    </tr>
    <tr>
      <th scope="row">OpenAI Structured</th>
      <td style="--size: calc(0.000165 / 0.0019); --color: #3b82f6;">
        <span class="data">$0.000165</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Gemini Structured</th>
      <td style="--size: calc(0.000114 / 0.0019); --color: #ef4444;">
        <span class="data">$0.000114</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic Tool Use</th>
      <td style="--size: calc(0.001408 / 0.0019); --color: #8b5cf6;">
        <span class="data">$0.001408</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic Extraction</th>
      <td style="--size: calc(0.001408 / 0.0019); --color: #f59e0b;">
        <span class="data">$0.001408</span>
      </td>
    </tr>
  </tbody>
</table>

*Both Enhanced Prompting and Gemini Structured Output with Flash models deliver the lowest cost at $0.000114 per extraction—12x cheaper than OpenAI's cheapest option. [View benchmark source](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb).*

### Speed Variability by Strategy (Min/Max/Average)

<table class="charts-css column multiple show-labels data-end data-spacing-6" style="height: 400px; --labels-size: 50px;">
  <thead>
    <tr>
      <th scope="col">Strategy</th>
      <th scope="col">Min Time</th>
      <th scope="col">Average Time</th>
      <th scope="col">Max Time</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">Gemini Structured</th>
      <td style="--size: calc(1.53 / 24.67); --color: #22c55e;">
        <span class="data">1.53s</span>
      </td>
      <td style="--size: calc(4.09 / 24.67); --color: #16a34a;">
        <span class="data">4.09s</span>
      </td>
      <td style="--size: calc(11.47 / 24.67); --color: #15803d;">
        <span class="data">11.47s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic Extraction</th>
      <td style="--size: calc(3.12 / 24.67); --color: #3b82f6;">
        <span class="data">3.12s</span>
      </td>
      <td style="--size: calc(5.46 / 24.67); --color: #2563eb;">
        <span class="data">5.46s</span>
      </td>
      <td style="--size: calc(10.53 / 24.67); --color: #1d4ed8;">
        <span class="data">10.53s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic Tool Use</th>
      <td style="--size: calc(2.26 / 24.67); --color: #8b5cf6;">
        <span class="data">2.26s</span>
      </td>
      <td style="--size: calc(5.67 / 24.67); --color: #7c3aed;">
        <span class="data">5.67s</span>
      </td>
      <td style="--size: calc(11.22 / 24.67); --color: #6d28d9;">
        <span class="data">11.22s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Enhanced Prompting</th>
      <td style="--size: calc(1.53 / 24.67); --color: #f59e0b;">
        <span class="data">1.53s</span>
      </td>
      <td style="--size: calc(7.98 / 24.67); --color: #d97706;">
        <span class="data">7.98s</span>
      </td>
      <td style="--size: 1.0; --color: #b45309;">
        <span class="data">24.67s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">OpenAI Structured</th>
      <td style="--size: calc(2.90 / 24.67); --color: #ef4444;">
        <span class="data">2.90s</span>
      </td>
      <td style="--size: calc(11.53 / 24.67); --color: #dc2626;">
        <span class="data">11.53s</span>
      </td>
      <td style="--size: calc(21.08 / 24.67); --color: #b91c1c;">
        <span class="data">21.08s</span>
      </td>
    </tr>
  </tbody>
</table>

*Enhanced Prompting shows the highest speed variability (1.53s to 24.67s) due to model diversity, while Gemini Structured offers good performance consistency. Provider-specific strategies show more predictable ranges.*

## Quick Decision Matrix

| Use Case | Recommended Strategy | Model | Cost | Speed |
|----------|---------------------|-------|------|-------|
| **Startup/MVP** | Enhanced Prompting | Gemini Flash | $0.000114 | 1.87s |
| **High Volume** | Gemini Structured | Gemini Flash | $0.000114 | 1.58s |
| **Enterprise Multi-Provider** | Enhanced Prompting | Multiple | Varies | 7.98s |
| **Maximum Reliability** | Provider-Specific | Any Compatible | Varies | 4.09-11.53s |
| **Cost-Sensitive** | Enhanced Prompting or Gemini Structured | Gemini Flash | $0.000114 | 1.58-1.87s |

## Key Findings

- **Speed Champion**: Gemini Flash with Structured Output (1.58s average) beats all other combinations
- **Universal Choice**: Enhanced Prompting works across all providers with 100% success  
- **Cost Winner**: Tie between Gemini Flash + Enhanced Prompting and Gemini Flash + Structured Output at $0.000114 per extraction
- **Reliability**: All strategies achieve 100% success rates across 32 test runs
- **Token Efficiency**: Choose Claude Haiku (800 tokens) or Gemini models (800 tokens) for lowest consumption
- **Best Value**: Gemini Flash delivers both lowest cost and fastest speeds regardless of strategy

## Implementation

[DSPy.rb](https://github.com/vicentereig/dspy.rb) uses [Signatures](https://vicentereig.github.io/dspy.rb/core-concepts/signatures/) to define structured inputs and outputs. Here's an example using [T::Enum types](https://vicentereig.github.io/dspy.rb/advanced/complex-types/):

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
  c.lm = DSPy::LM.new('gemini/gemini-1.5-flash',
                      api_key: ENV['GEMINI_API_KEY'], 
                      structured_outputs: true)  # Supports gemini-1.5-pro, gemini-1.5-flash, gemini-2.0-flash, gemini-2.5-*
end

predictor = DSPy::Predict.new(DeepResearch)
search_result = predictor.call(query: "How does Stripe's API design influence developer adoption?")
puts "Summary: #{search_result.summary}"
```

This example shows [DSPy.rb](https://github.com/vicentereig/dspy.rb)'s core components working together:
- **[Configuration](https://vicentereig.github.io/dspy.rb/getting-started/core-concepts/)**: Set up your language model
- **[Predictors](https://vicentereig.github.io/dspy.rb/core-concepts/predictors/)**: The `DSPy::Predict` class handles JSON extraction automatically

## Recommendations

**Start with Gemini Flash** for most applications:
- Lowest cost at $0.000114 per extraction
- Fastest speeds (1.58s structured, 1.87s enhanced)
- Works with both Enhanced Prompting (universal) and Structured Output (Gemini-specific)
- Consider [benchmarking your own workloads](https://vicentereig.github.io/dspy.rb/optimization/benchmarking-raw-prompts/)

**Optimize later** with provider-specific strategies for critical use cases, or use [prompt optimization](https://vicentereig.github.io/dspy.rb/optimization/prompt-optimization/) to improve Enhanced Prompting performance. Set up [evaluation metrics](https://vicentereig.github.io/dspy.rb/optimization/evaluation/) to measure improvement.

**Economic Reality:** Gemini Flash costs 35x less than Claude Opus while delivering production-quality results—you can perform 35 extractions for the cost of one premium extraction.

For enterprise deployments, implement [production observability](https://vicentereig.github.io/dspy.rb/production/observability/) to monitor extraction quality across providers.

## Future: BAML-Inspired Enhanced Prompting

We're developing [sorbet-baml](https://vicentereig.github.io/sorbet-baml/), a next-generation approach to Enhanced Prompting that could reduce token usage by 50-70% while improving accuracy. This initiative ([GitHub #70](https://github.com/vicentereig/dspy.rb/issues/70)) transforms verbose JSON schemas into TypeScript-like syntax with inline comments:

**Current JSON Schema:** 150 tokens
**BAML Format:** 45 tokens (70% reduction)

Expected benefits:
- **Lower costs**: Dramatically reduced token consumption for complex schemas
- **Better accuracy**: Up to 20% improvement for nested structures
- **Universal compatibility**: Works with all providers (OpenAI, Anthropic, Gemini, Ollama)

This enhancement will integrate seamlessly with [DSPy.rb](https://github.com/vicentereig/dspy.rb)'s existing Enhanced Prompting strategy, providing automatic optimization without code changes.

## Related Articles

- [Type-Safe Prediction Objects](https://vicentereig.github.io/dspy.rb/blog/articles/type-safe-prediction-objects/) - Deep dive into [DSPy.rb](https://github.com/vicentereig/dspy.rb)'s type system
- [Under the Hood: JSON Extraction](https://vicentereig.github.io/dspy.rb/blog/articles/under-the-hood-json-extraction/) - Technical details of extraction strategies
- [JSON Parsing Reliability](https://vicentereig.github.io/dspy.rb/blog/articles/json-parsing-reliability/) - Techniques for robust JSON handling

---

## Anthropic's Dual JSON Strategies: Tool Use vs Extraction

Anthropic offers two distinct approaches for structured outputs, each optimized for different use cases:

### Tool Use Strategy
- **How it works**: Models call a predefined "extraction" function with the desired JSON structure
- **Performance**: 5.67s average (2.26s to 11.22s range)
- **Best use case**: When you want the model to explicitly "decide" to extract data
- **Advantage**: More explicit about the extraction action, better for complex workflows

### Extraction Strategy  
- **How it works**: Direct prompt-based extraction using Anthropic's JSON parsing
- **Performance**: 5.46s average (3.12s to 10.53s range)
- **Best use case**: Simple, direct data extraction tasks
- **Advantage**: Slightly faster and more straightforward

### Which to Choose?
Both strategies deliver identical reliability (100% success rate) and cost ($0.001408 with Claude 3.5 Haiku). The performance difference is minimal (0.21s), so choose based on your workflow:

- **Use Tool Use** for agentic workflows where extraction is one of many possible actions
- **Use Extraction** for dedicated extraction tasks where speed matters most

Both are significantly slower and more expensive than Gemini options but offer the reliability of a premium provider.

---

*Benchmark: 32 tests across 5 strategies and 14 AI models. Total cost: $0.2354. September 21, 2025.*
