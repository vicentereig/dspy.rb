---
layout: blog
title: "Enhanced Prompting vs Native Structured Outputs: A DSPy.rb Comparison"
date: 2025-10-02
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
| **OpenAI** | gpt-4o | 3959ms / $0.002793 | 2728ms / $0.002543 | 🏆 Structured (31% faster, 9% cheaper) |
| **OpenAI** | gpt-4o-mini | 4505ms / $0.000171 | 2782ms / $0.000148 | 🏆 Structured (38% faster, 13% cheaper) |
| **Anthropic** | claude-sonnet-4-5 | 4257ms / $0.007167 | 4498ms / $0.007167 | Tie (identical) |
| **Anthropic** | claude-opus-4-1 | 4888ms / $0.031365 | 4741ms / $0.031365 | Tie (identical) |
| **Google** | gemini-2.5-pro | 14208ms / $0.001668 | 16002ms / $0.001573 | 🏆 Enhanced (13% faster, but 6% more expensive) |
| **Google** | gemini-2.5-flash | 9458ms / $0.000098 | 5062ms / $0.000074 | 🏆 Structured (46% faster, 24% cheaper) |

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
      <th scope="row">gpt-4o (Structured)</th>
      <td style="--size: calc(2.728 / 16.002); --color: #22c55e;">
        <span class="data">2.728s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Structured)</th>
      <td style="--size: calc(2.782 / 16.002); --color: #16a34a;">
        <span class="data">2.782s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Enhanced)</th>
      <td style="--size: calc(3.959 / 16.002); --color: #3b82f6;">
        <span class="data">3.959s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Enhanced)</th>
      <td style="--size: calc(4.257 / 16.002); --color: #8b5cf6;">
        <span class="data">4.257s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Structured)</th>
      <td style="--size: calc(4.498 / 16.002); --color: #a78bfa;">
        <span class="data">4.498s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Enhanced)</th>
      <td style="--size: calc(4.505 / 16.002); --color: #60a5fa;">
        <span class="data">4.505s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Structured)</th>
      <td style="--size: calc(4.741 / 16.002); --color: #c084fc;">
        <span class="data">4.741s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Enhanced)</th>
      <td style="--size: calc(4.888 / 16.002); --color: #d8b4fe;">
        <span class="data">4.888s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Structured)</th>
      <td style="--size: calc(5.062 / 16.002); --color: #34d399;">
        <span class="data">5.062s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Enhanced)</th>
      <td style="--size: calc(9.458 / 16.002); --color: #fbbf24;">
        <span class="data">9.458s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Enhanced)</th>
      <td style="--size: calc(14.208 / 16.002); --color: #fb923c;">
        <span class="data">14.208s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Structured)</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">16.002s</span>
      </td>
    </tr>
  </tbody>
</table>

*Based on [benchmark data](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb) from October 2, 2025. OpenAI models show the biggest improvement with structured outputs (31-38% faster), while Gemini 2.5-pro actually performs worse with structured outputs.*

## Token Consumption Analysis

Token usage varies by both model and strategy. Native structured outputs typically add more input tokens (schema) but reduce output tokens (tighter generation).

### Token Usage by Model and Strategy

| Model | Enhanced Prompting | Native Structured | Difference |
|-------|-------------------|-------------------|------------|
| **gpt-4o** | 477→160 (637 total) | 589→107 (696 total) | +112 input, -53 output (+59 total) |
| **gpt-4o-mini** | 477→166 (643 total) | 589→100 (689 total) | +112 input, -66 output (+46 total) |
| **claude-sonnet-4-5** | 1339→210 (1549 total) | 1339→210 (1549 total) | Identical |
| **claude-opus-4-1** | 1066→205 (1271 total) | 1066→205 (1271 total) | Identical |
| **gemini-2.5-pro** | 554→195 (749 total) | 554→176 (730 total) | Same input, -19 output (-19 total) |
| **gemini-2.5-flash** | 554→187 (741 total) | 554→109 (663 total) | Same input, -78 output (-78 total) |

**Key Insights:**
- **OpenAI**: Structured outputs add significant input tokens but reduce output tokens
- **Anthropic**: No token difference between strategies
- **Google**: Structured outputs reduce output tokens with no input overhead

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
      <th scope="row">gpt-4o</th>
      <td style="--size: calc(666.5 / 1410); --color: #3b82f6;">
        <span class="data">667 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini</th>
      <td style="--size: calc(666 / 1410); --color: #60a5fa;">
        <span class="data">666 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro</th>
      <td style="--size: calc(739.5 / 1410); --color: #22c55e;">
        <span class="data">740 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash</th>
      <td style="--size: calc(702 / 1410); --color: #16a34a;">
        <span class="data">702 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1</th>
      <td style="--size: calc(1271 / 1410); --color: #f59e0b;">
        <span class="data">1271 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">1549 tokens</span>
      </td>
    </tr>
  </tbody>
</table>

*OpenAI and Google models are most token-efficient (660-740 tokens average), while Anthropic Claude models use significantly more tokens (1271-1549 tokens).*

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
      <th scope="row">gemini-2.5-flash (Structured)</th>
      <td style="--size: calc(0.000074 / 0.031365); --color: #22c55e;">
        <span class="data">$0.000074</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Enhanced)</th>
      <td style="--size: calc(0.000098 / 0.031365); --color: #16a34a;">
        <span class="data">$0.000098</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Structured)</th>
      <td style="--size: calc(0.000148 / 0.031365); --color: #3b82f6;">
        <span class="data">$0.000148</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Enhanced)</th>
      <td style="--size: calc(0.000171 / 0.031365); --color: #60a5fa;">
        <span class="data">$0.000171</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Structured)</th>
      <td style="--size: calc(0.001573 / 0.031365); --color: #34d399;">
        <span class="data">$0.001573</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Enhanced)</th>
      <td style="--size: calc(0.001668 / 0.031365); --color: #10b981;">
        <span class="data">$0.001668</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Structured)</th>
      <td style="--size: calc(0.002543 / 0.031365); --color: #8b5cf6;">
        <span class="data">$0.002543</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Enhanced)</th>
      <td style="--size: calc(0.002793 / 0.031365); --color: #a78bfa;">
        <span class="data">$0.002793</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Both)</th>
      <td style="--size: calc(0.007167 / 0.031365); --color: #f59e0b;">
        <span class="data">$0.007167</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Both)</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">$0.031365</span>
      </td>
    </tr>
  </tbody>
</table>

*Gemini 2.5 Flash with Structured Outputs delivers the lowest cost at $0.000074 per extraction—424x cheaper than Claude Opus. [View benchmark source](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb).*

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
      <td style="--size: calc(4.232 / 11.833); --color: #3b82f6;">
        <span class="data">4.232s</span>
      </td>
      <td style="--size: calc(2.755 / 11.833); --color: #60a5fa;">
        <span class="data">2.755s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Anthropic</th>
      <td style="--size: calc(4.573 / 11.833); --color: #8b5cf6;">
        <span class="data">4.573s</span>
      </td>
      <td style="--size: calc(4.620 / 11.833); --color: #a78bfa;">
        <span class="data">4.620s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Google</th>
      <td style="--size: 1.0; --color: #f59e0b;">
        <span class="data">11.833s</span>
      </td>
      <td style="--size: calc(10.532 / 11.833); --color: #fbbf24;">
        <span class="data">10.532s</span>
      </td>
    </tr>
  </tbody>
</table>

*OpenAI shows the most dramatic improvement with structured outputs (35% faster average), Anthropic performs identically with both strategies, and Google shows moderate improvement (11% faster average with structured outputs).*

## Quick Decision Matrix

| Use Case | Recommended Strategy | Model | Cost | Speed |
|----------|---------------------|-------|------|-------|
| **OpenAI Users** | Native Structured | gpt-4o-mini | $0.000148 | 2.782s |
| **Cost-Optimized** | Native Structured | gemini-2.5-flash | $0.000074 | 5.062s |
| **Speed-Optimized** | Native Structured | gpt-4o | $0.002543 | 2.728s |
| **Anthropic Users** | Either Strategy | claude-sonnet-4-5 | $0.007167 | ~4.4s |
| **Multi-Provider** | Enhanced Prompting | Varies | Varies | Varies |
| **Google Pro** | Enhanced Prompting | gemini-2.5-pro | $0.001668 | 14.208s |

## Key Findings

- **OpenAI Wins Big**: Structured outputs are 31-38% faster and 9-13% cheaper for GPT models
- **Anthropic Agnostic**: Both strategies perform identically (same speed, cost, tokens)
- **Google Mixed**: Flash benefits from structured (46% faster, 24% cheaper), but Pro doesn't (13% slower)
- **Cost Champion**: Gemini 2.5 Flash with structured outputs at $0.000074 per extraction
- **Speed Champion**: GPT-4o with structured outputs at 2.728s
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
    structured_outputs: true            # 38% faster than enhanced prompting
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

**For OpenAI users**: Enable `structured_outputs: true` for 31-38% faster responses and 9-13% cost savings. This is a clear win with no downsides.

**For Anthropic users**: Use either strategy—performance is identical. Enhanced prompting offers more flexibility if you plan to switch providers.

**For Google Gemini users**:
- **Flash models**: Enable structured outputs for 46% faster, 24% cheaper extractions
- **Pro models**: Stick with enhanced prompting (13% faster, though slightly more expensive)

**For multi-provider applications**: Start with enhanced prompting for universal compatibility, then selectively enable structured outputs for OpenAI and Gemini Flash when deployed.

**Budget-conscious applications**: Use Gemini 2.5 Flash with structured outputs ($0.000074 per extraction)—424x cheaper than Claude Opus.

**Speed-critical applications**: Use GPT-4o with structured outputs (2.728s average)—the fastest option tested.

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

*Benchmark data: 12 tests across 2 strategies and 6 latest AI models (October 2025). Total cost: $0.0861. View [benchmark source code](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb) and [raw data](https://github.com/vicentereig/dspy.rb/blob/main/benchmark_20251002_134641.json).*
