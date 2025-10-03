---
layout: blog
title: "Enhanced Prompting vs Native Structured Outputs: A DSPy.rb Comparison"
date: 2025-09-18
description: "Head-to-head comparison of enhanced prompting vs native structured outputs across OpenAI, Anthropic, and Google models"
author: "Vicente Reig"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/json-modes-comparison/"
image: /images/og/json-modes-comparison.png
---

Getting reliable, structured data from Large Language Models is crucial for production applications. [DSPy.rb](https://github.com/vicentereig/dspy.rb) supports both enhanced prompting (universal) and native structured outputs (provider-specific). After benchmarking 6 latest models head-to-head, here's your complete guide to choosing the right approach.

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

This test compares [DSPy.rb](https://github.com/vicentereig/dspy.rb)'s two primary strategies: Enhanced Prompting (universal) and Native Structured Outputs (provider-specific) using the latest models from OpenAI, Anthropic, and Google as of October 2025.

## Two Strategies Compared

- **Enhanced Prompting**: Universal DSPy-style JSON Schema prompting with intelligent fallback handling. Works with any LLM provider.
- **Native Structured Outputs**: Provider-specific structured generation APIs:
  - OpenAI: JSON Schema with `strict: true` enforcement
  - Anthropic: Tool use with JSON schema validation
  - Google: Gemini native structured output mode

## Benchmark Results Overview

Both strategies achieved 100% success rate across all 6 models (12 tests total). Here are the head-to-head comparisons:

| Provider | Model | Enhanced Prompting | Native Structured | Winner |
|----------|-------|-------------------|-------------------|--------|
| **OpenAI** | gpt-4o | 3556ms / $0.002833 | 2733ms / $0.002443 | 🏆 Structured (23% faster, 14% cheaper) |
| **OpenAI** | gpt-4o-mini | 5636ms / $0.000169 | 1784ms / $0.000142 | 🏆 Structured (68% faster, 16% cheaper) |
| **Anthropic** | claude-sonnet-4-5 | 3630ms / $0.004581 | 4797ms / $0.007167 | 🏆 Enhanced (24% faster, 36% cheaper) |
| **Anthropic** | claude-opus-4-1 | 5077ms / $0.02238 | 5588ms / $0.031365 | 🏆 Enhanced (9% faster, 29% cheaper) |
| **Google** | gemini-2.5-pro | 8873ms / $0.001613 | 9850ms / $0.001578 | 🏆 Enhanced (10% faster, 2% more expensive) |
| **Google** | gemini-2.5-flash | 8650ms / $0.000084 | 17315ms / $0.000085 | 🏆 Enhanced (50% faster, 1% cheaper) |

### Response Time Comparison by Model

<table class="charts-css bar show-labels data-end data-spacing-8" style="height: 350px; --labels-size: 140px;">
  <thead>
    <tr>
      <th scope="col">Model / Strategy</th>
      <th scope="col">Response Time (seconds)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">gpt-4o-mini (Structured)</th>
      <td style="--size: calc(1.784 / 17.315); --color: #22c55e;">
        <span class="data">1.784s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Structured)</th>
      <td style="--size: calc(2.733 / 17.315); --color: #16a34a;">
        <span class="data">2.733s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Enhanced)</th>
      <td style="--size: calc(3.556 / 17.315); --color: #3b82f6;">
        <span class="data">3.556s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Enhanced)</th>
      <td style="--size: calc(3.630 / 17.315); --color: #8b5cf6;">
        <span class="data">3.630s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Structured)</th>
      <td style="--size: calc(4.797 / 17.315); --color: #a78bfa;">
        <span class="data">4.797s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Enhanced)</th>
      <td style="--size: calc(5.077 / 17.315); --color: #c084fc;">
        <span class="data">5.077s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Structured)</th>
      <td style="--size: calc(5.588 / 17.315); --color: #d8b4fe;">
        <span class="data">5.588s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Enhanced)</th>
      <td style="--size: calc(5.636 / 17.315); --color: #60a5fa;">
        <span class="data">5.636s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Enhanced)</th>
      <td style="--size: calc(8.650 / 17.315); --color: #34d399;">
        <span class="data">8.650s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Enhanced)</th>
      <td style="--size: calc(8.873 / 17.315); --color: #fbbf24;">
        <span class="data">8.873s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Structured)</th>
      <td style="--size: calc(9.850 / 17.315); --color: #fb923c;">
        <span class="data">9.850s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Structured)</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">17.315s</span>
      </td>
    </tr>
  </tbody>
</table>

*Based on [benchmark data](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb) from September 18, 2025. GPT-4o-mini with structured outputs is the fastest at 1.784s (68% faster than enhanced prompting), while Gemini 2.5-flash shows dramatic slowdown with structured outputs (17.315s vs 8.650s with enhanced prompting).*

## Token Consumption Analysis

Token usage varies by both model and strategy. Native structured outputs typically add more input tokens (schema) but reduce output tokens (tighter generation).

### Token Usage by Model and Strategy

| Model | Enhanced Prompting | Native Structured | Difference |
|-------|-------------------|-------------------|------------|
| **gpt-4o** | 477→164 (641 total) | 589→97 (686 total) | +112 input, -67 output (+45 total) |
| **gpt-4o-mini** | 477→163 (640 total) | 589→89 (678 total) | +112 input, -74 output (+38 total) |
| **claude-sonnet-4-5** | 597→186 (783 total) | 1339→210 (1549 total) | +742 input, +24 output (+766 total) |
| **claude-opus-4-1** | 597→179 (776 total) | 1066→205 (1271 total) | +469 input, +26 output (+495 total) |
| **gemini-2.5-pro** | 554→184 (738 total) | 554→177 (731 total) | Same input, -7 output (-7 total) |
| **gemini-2.5-flash** | 554→140 (694 total) | 554→145 (699 total) | Same input, +5 output (+5 total) |

**Key Insights:**
- **OpenAI**: Structured outputs add significant input tokens (+112) but reduce output tokens significantly (-67 to -74)
- **Anthropic**: Structured outputs dramatically increase token consumption (+495 to +766 total tokens)
- **Google**: Minimal token difference between strategies (-7 to +5 tokens)

### Token Efficiency by Model Family

<table class="charts-css column show-labels data-end data-spacing-6" style="height: 350px; --labels-size: 40px;">
  <thead>
    <tr>
      <th scope="col">Model</th>
      <th scope="col">Avg Tokens (Both Strategies)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">gpt-4o-mini</th>
      <td style="--size: calc(659 / 1166); --color: #22c55e;">
        <span class="data">659 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o</th>
      <td style="--size: calc(663.5 / 1166); --color: #16a34a;">
        <span class="data">664 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash</th>
      <td style="--size: calc(696.5 / 1166); --color: #3b82f6;">
        <span class="data">697 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro</th>
      <td style="--size: calc(734.5 / 1166); --color: #60a5fa;">
        <span class="data">735 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1</th>
      <td style="--size: calc(1023.5 / 1166); --color: #f59e0b;">
        <span class="data">1024 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">1166 tokens</span>
      </td>
    </tr>
  </tbody>
</table>

*OpenAI and Google models are most token-efficient (659-735 tokens average), while Anthropic Claude models use significantly more tokens (1024-1166 tokens average).*

### Cost Comparison: All Models and Strategies

<table class="charts-css column show-labels data-end data-spacing-4" style="height: 400px; --labels-size: 50px;">
  <thead>
    <tr>
      <th scope="col">Model / Strategy</th>
      <th scope="col">Cost per Extraction</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">gemini-2.5-flash (Enhanced)</th>
      <td style="--size: calc(0.000084 / 0.031365); --color: #22c55e;">
        <span class="data">$0.000084</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Structured)</th>
      <td style="--size: calc(0.000085 / 0.031365); --color: #16a34a;">
        <span class="data">$0.000085</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Structured)</th>
      <td style="--size: calc(0.000142 / 0.031365); --color: #3b82f6;">
        <span class="data">$0.000142</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Enhanced)</th>
      <td style="--size: calc(0.000169 / 0.031365); --color: #60a5fa;">
        <span class="data">$0.000169</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Structured)</th>
      <td style="--size: calc(0.001578 / 0.031365); --color: #34d399;">
        <span class="data">$0.001578</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Enhanced)</th>
      <td style="--size: calc(0.001613 / 0.031365); --color: #10b981;">
        <span class="data">$0.001613</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Structured)</th>
      <td style="--size: calc(0.002443 / 0.031365); --color: #8b5cf6;">
        <span class="data">$0.002443</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Enhanced)</th>
      <td style="--size: calc(0.002833 / 0.031365); --color: #a78bfa;">
        <span class="data">$0.002833</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Enhanced)</th>
      <td style="--size: calc(0.004581 / 0.031365); --color: #f59e0b;">
        <span class="data">$0.004581</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Structured)</th>
      <td style="--size: calc(0.007167 / 0.031365); --color: #fbbf24;">
        <span class="data">$0.007167</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Enhanced)</th>
      <td style="--size: calc(0.02238 / 0.031365); --color: #fb923c;">
        <span class="data">$0.02238</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Structured)</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">$0.031365</span>
      </td>
    </tr>
  </tbody>
</table>

*Gemini 2.5 Flash with Enhanced Prompting delivers the lowest cost at $0.000084 per extraction—373x cheaper than Claude Opus with Structured Outputs. [View benchmark source](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb).*

### Performance by Provider (Average across models)

<table class="charts-css bar multiple show-labels data-end data-spacing-8" style="height: 300px; --labels-size: 120px;">
  <thead>
    <tr>
      <th scope="col">Provider</th>
      <th scope="col">Enhanced Prompting</th>
      <th scope="col">Native Structured</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">OpenAI</th>
      <td style="--size: calc(4.596 / 13.583); --color: #3b82f6;">
        <span class="data">4.596s</span>
      </td>
      <td style="--size: calc(2.259 / 13.583); --color: #60a5fa;">
        <span class="data">2.259s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic</th>
      <td style="--size: calc(4.354 / 13.583); --color: #8b5cf6;">
        <span class="data">4.354s</span>
      </td>
      <td style="--size: calc(5.193 / 13.583); --color: #a78bfa;">
        <span class="data">5.193s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Google</th>
      <td style="--size: calc(8.762 / 13.583); --color: #f59e0b;">
        <span class="data">8.762s</span>
      </td>
      <td style="--size: 1.0; --color: #fbbf24;">
        <span class="data">13.583s</span>
      </td>
    </tr>
  </tbody>
</table>

*OpenAI shows dramatic improvement with structured outputs (51% faster average). Anthropic and Google both perform better with enhanced prompting—Anthropic is 16% faster with enhanced prompting, while Google is 35% faster with enhanced prompting.*

## Quick Decision Matrix

| Use Case | Recommended Strategy | Model | Cost | Speed |
|----------|---------------------|-------|------|-------|
| **OpenAI Users** | Native Structured | gpt-4o-mini | $0.000142 | 1.784s |
| **Cost-Optimized** | Enhanced Prompting | gemini-2.5-flash | $0.000084 | 8.650s |
| **Speed-Optimized** | Native Structured | gpt-4o-mini | $0.000142 | 1.784s |
| **Anthropic Users** | Enhanced Prompting | claude-sonnet-4-5 | $0.004581 | 3.630s |
| **Multi-Provider** | Enhanced Prompting | Varies | Varies | Varies |
| **Google Users** | Enhanced Prompting | gemini-2.5-pro | $0.001613 | 8.873s |

## Key Findings

- **OpenAI Wins Big**: Structured outputs are 23-68% faster and 14-16% cheaper for GPT models
- **Anthropic Favors Enhanced**: Enhanced prompting is 9-24% faster and 29-36% cheaper than structured outputs
- **Google Favors Enhanced**: Enhanced prompting is 10-50% faster for both Pro and Flash models
- **Cost Champion**: Gemini 2.5 Flash with enhanced prompting at $0.000084 per extraction
- **Speed Champion**: GPT-4o-mini with structured outputs at 1.784s
- **Universal Reliability**: 100% success rate across all 12 tests (6 models × 2 strategies)

## Implementation

[DSPy.rb](https://github.com/vicentereig/dspy.rb) uses [Signatures](https://vicentereig.github.io/dspy.rb/core-concepts/signatures/) to define structured inputs and outputs. Here's an example using [T::Enum types](https://vicentereig.github.io/dspy.rb/advanced/complex-types/):

```ruby
class ActionType < T::Enum
  enums do
    Create = new('create')
    Update = new('update')
    Delete = new('delete')
  end
end

class TodoAction < T::Struct
  const :action_type, ActionType
  const :task, String
  const :priority, String, default: 'medium'
end

class TodoListManagement < DSPy::Signature
  description "Parse user request into structured todo actions"

  input do
    const :user_request, String, description: "Natural language request about todos"
  end

  output do
    const :actions, T::Array[TodoAction], description: "Actions to execute"
    const :summary, String, description: "Brief summary of what will be done"
  end
end

# Configure DSPy with structured outputs for optimal performance
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',              # Fast and cost-effective
    api_key: ENV['OPENAI_API_KEY'],
    structured_outputs: true            # 68% faster than enhanced prompting
  )
end

predictor = DSPy::Predict.new(TodoListManagement)
result = predictor.call(
  user_request: "Add task to buy groceries and schedule team meeting for Friday"
)

puts "Summary: #{result.summary}"
result.actions.each do |action|
  puts "  #{action.action_type.serialize}: #{action.task} [#{action.priority}]"
end
```

This example shows [DSPy.rb](https://github.com/vicentereig/dspy.rb)'s core components working together:
- **[Configuration](https://vicentereig.github.io/dspy.rb/getting-started/core-concepts/)**: Set up your language model
- **[Predictors](https://vicentereig.github.io/dspy.rb/core-concepts/predictors/)**: The `DSPy::Predict` class handles JSON extraction automatically

## Recommendations

**For OpenAI users**: Enable `structured_outputs: true` for 23-68% faster responses and 14-16% cost savings. This is a clear win with no downsides, especially for gpt-4o-mini (68% faster).

**For Anthropic users**: Use enhanced prompting for 9-24% faster responses and 29-36% cost savings. Structured outputs significantly increase token consumption and costs for Claude models.

**For Google Gemini users**:
- **Both Pro and Flash**: Use enhanced prompting for 10-50% faster performance
- **Flash models**: Enhanced prompting avoids dramatic slowdown (8.65s vs 17.32s with structured)
- **Pro models**: Enhanced prompting is 10% faster and only slightly more expensive

**For multi-provider applications**: Enhanced prompting is the best default strategy, offering excellent performance across all providers.

**Budget-conscious applications**: Use Gemini 2.5 Flash with enhanced prompting ($0.000084 per extraction)—373x cheaper than Claude Opus with structured outputs.

**Speed-critical applications**: Use GPT-4o-mini with structured outputs (1.784s average)—the fastest option tested.

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

*Benchmark data: 12 tests across 2 strategies and 6 latest AI models (September 2025). Total cost: $0.0744. View [benchmark source code](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb) and [raw data](https://github.com/vicentereig/dspy.rb/blob/main/benchmark_20251003_155004.json).*
