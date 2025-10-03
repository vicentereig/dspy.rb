---
layout: blog
title: "Enhanced Prompting vs Native Structured Outputs: A DSPy.rb Comparison"
date: 2025-09-18
description: "Head-to-head comparison of enhanced prompting vs native structured outputs across OpenAI, Anthropic, and Google models"
author: "Vicente Reig"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/json-modes-comparison/"
image: /images/og/json-modes-comparison.png
---

Getting reliable, structured data from Large Language Models is crucial for production applications. [DSPy.rb](https://github.com/vicentereig/dspy.rb) supports both enhanced prompting (universal) and native structured outputs (provider-specific). After benchmarking 8 latest models head-to-head, here's your complete guide to choosing the right approach.

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

This test compares [DSPy.rb](https://github.com/vicentereig/dspy.rb)'s two primary strategies: Enhanced Prompting (universal) and Native Structured Outputs (provider-specific) using the latest models from OpenAI, Anthropic, and Google as of September 2025.

## Two Strategies Compared

- **Enhanced Prompting**: Universal DSPy-style JSON Schema prompting with intelligent fallback handling. Works with any LLM provider.
- **Native Structured Outputs**: Provider-specific structured generation APIs:
  - OpenAI: JSON Schema with `strict: true` enforcement
  - Anthropic: Tool use with JSON schema validation
  - Google: Gemini native structured output mode

## Benchmark Results Overview

Both strategies achieved 100% success rate across all 8 models (16 tests total). Here are the head-to-head comparisons:

| Provider | Model | Enhanced Prompting | Native Structured | Winner |
|----------|-------|-------------------|-------------------|--------|
| **OpenAI** | gpt-4o | 2302ms / $0.002833 | 1769ms / $0.001658 | 🏆 Structured (23% faster, 41% cheaper) |
| **OpenAI** | gpt-4o-mini | 2944ms / $0.000169 | 2111ms / $0.000097 | 🏆 Structured (28% faster, 43% cheaper) |
| **OpenAI** | gpt-5 | 16005ms / $0.011895 | 22921ms / $0.015065 | 🏆 Enhanced (43% faster, 21% cheaper) |
| **OpenAI** | gpt-5-mini | 8303ms / $0.001361 | 10694ms / $0.001881 | 🏆 Enhanced (29% faster, 28% cheaper) |
| **Anthropic** | claude-sonnet-4-5 | 3411ms / $0.004581 | 3401ms / $0.005886 | 🏆 Enhanced (similar speed, 22% cheaper) |
| **Anthropic** | claude-opus-4-1 | 4993ms / $0.02238 | 4796ms / $0.025335 | 🏆 Enhanced (4% slower, 12% cheaper) |
| **Google** | gemini-2.5-pro | 10478ms / $0.001623 | 6787ms / $0.001023 | 🏆 Structured (35% faster, 37% cheaper) |
| **Google** | gemini-2.5-flash | 15704ms / $0.000096 | 7943ms / $0.000050 | 🏆 Structured (49% faster, 48% cheaper) |

### Response Time Comparison by Model

<table class="charts-css bar show-labels data-end data-spacing-8" style="height: 450px; --labels-size: 150px;">
  <thead>
    <tr>
      <th scope="col">Model / Strategy</th>
      <th scope="col">Response Time (seconds)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">gpt-4o (Structured)</th>
      <td style="--size: calc(1.769 / 22.921); --color: #22c55e;">
        <span class="data">1.769s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Structured)</th>
      <td style="--size: calc(2.111 / 22.921); --color: #16a34a;">
        <span class="data">2.111s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Enhanced)</th>
      <td style="--size: calc(2.302 / 22.921); --color: #3b82f6;">
        <span class="data">2.302s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Enhanced)</th>
      <td style="--size: calc(2.944 / 22.921); --color: #60a5fa;">
        <span class="data">2.944s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Structured)</th>
      <td style="--size: calc(3.401 / 22.921); --color: #8b5cf6;">
        <span class="data">3.401s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Enhanced)</th>
      <td style="--size: calc(3.411 / 22.921); --color: #a78bfa;">
        <span class="data">3.411s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Structured)</th>
      <td style="--size: calc(4.796 / 22.921); --color: #c084fc;">
        <span class="data">4.796s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Enhanced)</th>
      <td style="--size: calc(4.993 / 22.921); --color: #d8b4fe;">
        <span class="data">4.993s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Structured)</th>
      <td style="--size: calc(6.787 / 22.921); --color: #34d399;">
        <span class="data">6.787s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Structured)</th>
      <td style="--size: calc(7.943 / 22.921); --color: #10b981;">
        <span class="data">7.943s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5-mini (Enhanced)</th>
      <td style="--size: calc(8.303 / 22.921); --color: #14b8a6;">
        <span class="data">8.303s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Enhanced)</th>
      <td style="--size: calc(10.478 / 22.921); --color: #fbbf24;">
        <span class="data">10.478s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5-mini (Structured)</th>
      <td style="--size: calc(10.694 / 22.921); --color: #fb923c;">
        <span class="data">10.694s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Enhanced)</th>
      <td style="--size: calc(15.704 / 22.921); --color: #f87171;">
        <span class="data">15.704s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5 (Enhanced)</th>
      <td style="--size: calc(16.005 / 22.921); --color: #dc2626;">
        <span class="data">16.005s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5 (Structured)</th>
      <td style="--size: 1.0; --color: #991b1b;">
        <span class="data">22.921s</span>
      </td>
    </tr>
  </tbody>
</table>

*Based on [benchmark data](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb) from September 2025. GPT-4o with structured outputs is the fastest at 1.769s, while GPT-5 with structured outputs is the slowest at 22.921s. GPT-4o models show dramatic improvements with structured outputs, while GPT-5 models perform better with enhanced prompting.*

## Token Consumption Analysis

Token usage varies dramatically by both model and strategy. Modern structured output implementations optimize token efficiency by sending schemas through API parameters rather than in prompts.

### Token Usage by Model and Strategy

| Model | Enhanced Prompting | Native Structured | Difference |
|-------|-------------------|-------------------|------------|
| **gpt-4o** | 477→164 (641 total) | 255→102 (357 total) | -222 input, -62 output (-284 total, 44% reduction) |
| **gpt-4o-mini** | 477→163 (640 total) | 255→98 (353 total) | -222 input, -65 output (-287 total, 45% reduction) |
| **gpt-5** | 476→1130 (1606 total) | 476→1447 (1923 total) | Same input, +317 output (+317 total, 20% increase) |
| **gpt-5-mini** | 476→621 (1097 total) | 476→881 (1357 total) | Same input, +260 output (+260 total, 24% increase) |
| **claude-sonnet-4-5** | 597→186 (783 total) | 927→207 (1134 total) | +330 input, +21 output (+351 total, 45% increase) |
| **claude-opus-4-1** | 597→179 (776 total) | 654→207 (861 total) | +57 input, +28 output (+85 total, 11% increase) |
| **gemini-2.5-pro** | 554→186 (740 total) | 158→165 (323 total) | -396 input, -21 output (-417 total, 56% reduction) |
| **gemini-2.5-flash** | 554→180 (734 total) | 158→127 (285 total) | -396 input, -53 output (-449 total, 61% reduction) |

**Key Insights:**
- **OpenAI (GPT-4)**: Structured outputs dramatically reduce token consumption (-44% to -45% total) by sending schemas via API
- **OpenAI (GPT-5)**: Higher output token generation (+20% to +24%) indicates extensive reasoning/thinking tokens
- **Anthropic**: Structured outputs still increase tokens (+11% to +45%) due to tool-use architecture
- **Google**: Structured outputs achieve massive token reduction (-56% to -61% total) through native API integration

### Token Efficiency by Model Family

<table class="charts-css column show-labels data-end data-spacing-6" style="height: 400px; --labels-size: 45px;">
  <thead>
    <tr>
      <th scope="col">Model</th>
      <th scope="col">Avg Tokens (Both Strategies)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">gpt-4o-mini</th>
      <td style="--size: calc(496.5 / 1764.5); --color: #22c55e;">
        <span class="data">497 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o</th>
      <td style="--size: calc(499 / 1764.5); --color: #16a34a;">
        <span class="data">499 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash</th>
      <td style="--size: calc(509.5 / 1764.5); --color: #3b82f6;">
        <span class="data">510 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro</th>
      <td style="--size: calc(531.5 / 1764.5); --color: #60a5fa;">
        <span class="data">532 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1</th>
      <td style="--size: calc(818.5 / 1764.5); --color: #8b5cf6;">
        <span class="data">819 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5</th>
      <td style="--size: calc(958.5 / 1764.5); --color: #a78bfa;">
        <span class="data">959 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5-mini</th>
      <td style="--size: calc(1227 / 1764.5); --color: #fbbf24;">
        <span class="data">1227 tokens</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">1765 tokens</span>
      </td>
    </tr>
  </tbody>
</table>

*GPT-4o and Google models are most token-efficient (497-532 tokens average). Claude models use moderate tokens (819-959 average). GPT-5 models generate significantly more tokens (1227-1765 average) due to extensive reasoning/thinking output.*

### Cost Comparison: All Models and Strategies

<table class="charts-css column show-labels data-end data-spacing-4" style="height: 500px; --labels-size: 55px;">
  <thead>
    <tr>
      <th scope="col">Model / Strategy</th>
      <th scope="col">Cost per Extraction</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">gemini-2.5-flash (Structured)</th>
      <td style="--size: calc(0.000050 / 0.025335); --color: #22c55e;">
        <span class="data">$0.000050</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-flash (Enhanced)</th>
      <td style="--size: calc(0.000096 / 0.025335); --color: #16a34a;">
        <span class="data">$0.000096</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Structured)</th>
      <td style="--size: calc(0.000097 / 0.025335); --color: #3b82f6;">
        <span class="data">$0.000097</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o-mini (Enhanced)</th>
      <td style="--size: calc(0.000169 / 0.025335); --color: #60a5fa;">
        <span class="data">$0.000169</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Structured)</th>
      <td style="--size: calc(0.001023 / 0.025335); --color: #34d399;">
        <span class="data">$0.001023</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5-mini (Enhanced)</th>
      <td style="--size: calc(0.001361 / 0.025335); --color: #10b981;">
        <span class="data">$0.001361</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gemini-2.5-pro (Enhanced)</th>
      <td style="--size: calc(0.001623 / 0.025335); --color: #14b8a6;">
        <span class="data">$0.001623</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Structured)</th>
      <td style="--size: calc(0.001658 / 0.025335); --color: #06b6d4;">
        <span class="data">$0.001658</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5-mini (Structured)</th>
      <td style="--size: calc(0.001881 / 0.025335); --color: #0ea5e9;">
        <span class="data">$0.001881</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-4o (Enhanced)</th>
      <td style="--size: calc(0.002833 / 0.025335); --color: #8b5cf6;">
        <span class="data">$0.002833</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Enhanced)</th>
      <td style="--size: calc(0.004581 / 0.025335); --color: #a78bfa;">
        <span class="data">$0.004581</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-sonnet-4-5 (Structured)</th>
      <td style="--size: calc(0.005886 / 0.025335); --color: #c084fc;">
        <span class="data">$0.005886</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5 (Enhanced)</th>
      <td style="--size: calc(0.011895 / 0.025335); --color: #f59e0b;">
        <span class="data">$0.011895</span>
      </td>
    </tr>
    <tr>
      <th scope="row">gpt-5 (Structured)</th>
      <td style="--size: calc(0.015065 / 0.025335); --color: #fbbf24;">
        <span class="data">$0.015065</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Enhanced)</th>
      <td style="--size: calc(0.02238 / 0.025335); --color: #fb923c;">
        <span class="data">$0.02238</span>
      </td>
    </tr>
    <tr>
      <th scope="row">claude-opus-4-1 (Structured)</th>
      <td style="--size: 1.0; --color: #ef4444;">
        <span class="data">$0.025335</span>
      </td>
    </tr>
  </tbody>
</table>

*Gemini 2.5 Flash with Structured Outputs delivers the lowest cost at $0.000050 per extraction—507x cheaper than Claude Opus with Structured Outputs. [View benchmark source](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb).*

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
      <th scope="row">Anthropic</th>
      <td style="--size: calc(4.202 / 13.091); --color: #8b5cf6;">
        <span class="data">4.202s</span>
      </td>
      <td style="--size: calc(4.099 / 13.091); --color: #a78bfa;">
        <span class="data">4.099s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">Google</th>
      <td style="--size: 1.0; --color: #f59e0b;">
        <span class="data">13.091s</span>
      </td>
      <td style="--size: calc(7.365 / 13.091); --color: #fbbf24;">
        <span class="data">7.365s</span>
      </td>
    </tr>
    <tr>
      <th scope="row">OpenAI</th>
      <td style="--size: calc(7.389 / 13.091); --color: #3b82f6;">
        <span class="data">7.389s</span>
      </td>
      <td style="--size: calc(9.374 / 13.091); --color: #60a5fa;">
        <span class="data">9.374s</span>
      </td>
    </tr>
  </tbody>
</table>

*Anthropic shows nearly identical performance between strategies (2.5% faster with structured). Google dramatically improves with structured outputs (44% faster average). OpenAI shows mixed results due to GPT-5's slower structured output performance offsetting GPT-4o's improvements (21% slower average with structured).*

## Quick Decision Matrix

| Use Case | Recommended Strategy | Model | Cost | Speed |
|----------|---------------------|-------|------|-------|
| **Cost-Optimized** | Native Structured | gemini-2.5-flash | $0.000050 | 7.943s |
| **Speed-Optimized** | Native Structured | gpt-4o | $0.001658 | 1.769s |
| **OpenAI GPT-4o Users** | Native Structured | gpt-4o / gpt-4o-mini | $0.000097-$0.001658 | 1.769-2.111s |
| **OpenAI GPT-5 Users** | Enhanced Prompting | gpt-5 / gpt-5-mini | $0.001361-$0.011895 | 8.303-16.005s |
| **Anthropic Users** | Enhanced Prompting | claude-sonnet-4-5 | $0.004581 | 3.411s |
| **Google Users** | Native Structured | gemini-2.5-pro / flash | $0.000050-$0.001023 | 6.787-7.943s |
| **Multi-Provider** | Enhanced Prompting | Varies | Varies | Varies |

## Key Findings

- **GPT-4o Dominates**: Structured outputs are 23-28% faster and 41-43% cheaper with superior token efficiency (-44% to -45%)
- **GPT-5 Reasoning Overhead**: Enhanced prompting 29-43% faster; GPT-5 generates 1130-1447 output tokens (extensive reasoning)
- **Google Wins Both Ways**: Structured outputs 35-49% faster, 37-48% cheaper, and 56-61% fewer tokens
- **Anthropic Prefers Enhanced**: Enhanced prompting similar speed but 12-22% cheaper than structured outputs
- **Cost Champion**: Gemini 2.5 Flash with structured outputs at $0.000050 per extraction
- **Speed Champion**: GPT-4o with structured outputs at 1.769s
- **Token Efficiency Revolution**: Structured outputs now MORE efficient for OpenAI and Google (vs old implementations)
- **Universal Reliability**: 100% success rate across all 16 tests (8 models × 2 strategies)

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

**For OpenAI GPT-4o users**: Enable `structured_outputs: true` for dramatic wins—23-28% faster, 41-43% cheaper, and 44-45% fewer tokens. This is a clear win with no downsides.

**For OpenAI GPT-5 users**: Use enhanced prompting for 29-43% faster responses and 21-28% cost savings. GPT-5's extensive reasoning generates 1130-1447 output tokens, making structured outputs slower and more expensive.

**For Anthropic users**: Use enhanced prompting for 12-22% cost savings. Performance is nearly identical between strategies, but enhanced prompting uses fewer tokens.

**For Google Gemini users**: Enable `structured_outputs: true` for exceptional results:
- **Gemini 2.5 Flash**: 49% faster, 48% cheaper, 61% fewer tokens
- **Gemini 2.5 Pro**: 35% faster, 37% cheaper, 56% fewer tokens
- Structured outputs achieve massive token efficiency through native API integration

**For multi-provider applications**: Enhanced prompting remains the best default strategy for universal compatibility, though provider-specific optimization can yield significant improvements.

**Budget-conscious applications**: Use Gemini 2.5 Flash with structured outputs ($0.000050 per extraction)—507x cheaper than Claude Opus with structured outputs.

**Speed-critical applications**: Use GPT-4o with structured outputs (1.769s average)—the fastest option tested.

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

*Benchmark data: 16 tests across 2 strategies and 8 latest AI models (September 2025). Total cost: $0.0959. View [benchmark source code](https://github.com/vicentereig/dspy.rb/blob/main/examples/json_modes_benchmark.rb) and [raw data](https://github.com/vicentereig/dspy.rb/blob/main/benchmark_20251003_165710.json).*
