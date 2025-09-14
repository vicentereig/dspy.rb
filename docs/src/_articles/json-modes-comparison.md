---
layout: blog
title: "JSON Extraction in Production: When to Use Each DSPy.rb Strategy"
date: 2025-09-14
description: "Performance analysis and decision guide for choosing the right JSON extraction strategy across AI providers"
author: "Vicente Reig"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/json-modes-comparison/"
---

Getting reliable, structured data from Large Language Models is crucial for production applications. While LLMs excel at generating human-like text, they struggle with consistently producing valid JSON that matches your application's type requirements.

DSPy.rb solves this challenge with five different JSON extraction strategies, each optimized for specific AI providers and use cases. After benchmarking these strategies across 13 AI models using complex nested types, we can now provide clear guidance on when to use each approach.

## The Structured Output Problem

Modern applications need structured, validated data from AI models:

```ruby
# What you want: Type-safe, validated structures
class TodoItem < DSPy::Struct
  const :title, String
  const :priority, T.enum(['high', 'medium', 'low'])
  const :due_date, T.nilable(String)
  const :assignee, UserProfile
end

# What LLMs often give you: Unreliable JSON
'{"title": "Fix bug", "priority": "urgent", "due_date": null, "assignee": "John"}'
# ❌ Invalid priority value, wrong assignee type
```

DSPy.rb automatically handles this complexity, selecting the optimal extraction strategy based on your target model and ensuring type-safe results every time.

## DSPy.rb's Five Extraction Strategies

### Universal Strategy: Enhanced Prompting
**Works with all AI models** - Your reliable fallback

DSPy.rb generates JSON Schema from your Ruby types and embeds clear formatting instructions in prompts. This strategy works across every provider and model, making it perfect for applications that need broad compatibility.

**Best for:** Multi-provider applications, legacy model support, maximum reliability

### Provider-Optimized Strategies

#### OpenAI Structured Output
**GPT-4o, GPT-4o-mini, GPT-5 series** - Native API enforcement

Uses OpenAI's structured output API with function calling to enforce your schema at the API level. Provides the strongest guarantees for OpenAI models.

**Best for:** OpenAI-exclusive applications requiring maximum reliability

#### Anthropic Tool Use  
**All Claude models** - Function calling approach

Leverages Claude's sophisticated tool use capabilities to structure outputs through function parameters. Excellent reasoning about complex type relationships.

**Best for:** Applications requiring complex reasoning and structured outputs

#### Anthropic Extraction
**All Claude models** - Text completion with guided parsing

Specialized extraction using Claude's text completion with custom parsing logic. Optimized fallback for Anthropic models.

**Best for:** Complex document processing, custom extraction patterns

#### Gemini Structured Output
**Gemini 1.5 Pro** - Native structured generation

Google's native structured output capability. Emerged as the speed champion in our benchmarks while maintaining excellent accuracy.

**Best for:** High-throughput applications, cost-sensitive deployments

## Performance Benchmark Results

We tested all strategies across 13 AI models using sophisticated nested types including enums, unions, and arrays. Here are the results from our September 2025 benchmark:

### Speed Rankings

| Strategy | Avg Response Time | Success Rate | Models Tested |
|----------|------------------|-------------|---------------|
| **Gemini Structured** | 3.42s | 100% (1/1) | Gemini 1.5 Pro only |
| **Anthropic Tool Use** | 6.23s | 100% (4/4) | All Claude models |
| **Anthropic Extraction** | 6.41s | 100% (4/4) | All Claude models |
| **Enhanced Prompting** | 7.52s | 92.3% (12/13) | Universal compatibility |
| **OpenAI Structured** | 9.39s | 100% (5/5) | GPT models with structured output |

**Key Finding:** While Gemini leads in speed, Enhanced Prompting delivers competitive performance across all providers with 92.3% success rate—making it the most versatile choice for production applications.

### Reliability Analysis

**Perfect Success Rates (100%):**
- All provider-specific strategies achieved 100% success on their compatible models
- OpenAI Structured Output: 5/5 successful extractions
- Anthropic Tool Use: 4/4 successful extractions  
- Anthropic Extraction: 4/4 successful extractions
- Gemini Structured Output: 1/1 successful extraction

**Enhanced Prompting: 92.3% Success Rate**
- 12 successful extractions out of 13 attempts
- Single failure occurred with the `o1` model
- Works across all provider ecosystems with minor tradeoffs

### Cost Analysis: Production Economics

Based on our benchmark of 27 total tests across all strategies:

**Most Cost-Effective:**
1. Gemini 1.5 Flash + Enhanced Prompting: $0.000114 per extraction
2. GPT-5-nano + any strategy: $0.000165 per extraction  
3. GPT-4o-mini + any strategy: $0.000342 per extraction

**Premium Tiers:**
1. Claude Opus 4.1: $0.0495 per extraction (144x more expensive than Gemini Flash)
2. Claude Sonnet 4: $0.00792 per extraction
3. GPT-5: $0.005813 per extraction

**Total benchmark cost: $0.2302** for comprehensive testing across all combinations.

**Economic Insight:** The 144x cost difference between Gemini Flash and Claude Opus means you can perform 144 extractions with Gemini for the cost of one premium Claude extraction.

### Model Compatibility Matrix

```
Strategy              OpenAI  Anthropic  Gemini  Total Models
Enhanced Prompting      ✅        ✅        ✅        13/13
Anthropic Tool Use      ❌        ✅        ❌         4/13  
Anthropic Extraction    ❌        ✅        ❌         4/13
OpenAI Structured       ✅        ❌        ❌         5/13
Gemini Structured       ❌        ❌        ✅         1/13
```

**Insight:** Enhanced Prompting's universal compatibility means you can write once and deploy across any AI provider without code changes.

## Real-World Decision Guide

### For Startups & MVPs
**Recommendation: Enhanced Prompting + Gemini Flash**
- Universal compatibility as you experiment with providers
- $0.000114 per extraction keeps costs minimal
- 7.52s response time adequate for most use cases
- 92.3% success rate across all models tested
- Easy to switch providers later without code changes

### For High-Volume Production
**Recommendation: Gemini Structured Output + Gemini Pro**
- 3.42s response time handles high throughput (fastest strategy)
- 100% success rate in testing
- Native structured output provides reliability
- Limitation: Single model compatibility (Gemini 1.5 Pro only)

### For Enterprise Applications  
**Recommendation: Enhanced Prompting across multiple providers**
- Deploy on Claude for complex reasoning (6.23-6.41s response time)
- Use OpenAI for general-purpose tasks (9.39s response time)
- Fallback to Gemini for cost optimization (3.42s response time)
- Single codebase, multiple backends
- 92.3% overall success rate provides good reliability

### For Maximum Reliability
**Recommendation: Provider-specific strategies**
- OpenAI Structured Output: 100% success rate, 9.39s response time
- Anthropic Tool Use: 100% success rate, 6.23s response time  
- Anthropic Extraction: 100% success rate, 6.41s response time
- Worth the provider lock-in for mission-critical applications
- Note: Enhanced Prompting's single failure was with the experimental `o1` model

## Complex Type Handling

All strategies successfully handled sophisticated Ruby types:

```ruby
# Union types with automatic discrimination
ActionType = T.type_alias do
  T.any(CreateTodoAction, UpdateTodoAction, DeleteTodoAction)
end

# Nested structures with validation
class ProjectSummary < DSPy::Struct
  const :total_todos, Integer
  const :team_members, T::Array[UserProfile]
  const :next_actions, T::Array[ActionType]
  const :completion_rate, Float, description: "Between 0.0 and 1.0"
end
```

**Key Insight:** DSPy.rb's type system works identically across all strategies. Your Ruby type definitions become the single source of truth, regardless of which provider you choose.

## Implementation Simplicity

DSPy.rb handles strategy selection automatically:

```ruby
# Single line - works with any provider
lm = DSPy::LM.new('gemini/gemini-1.5-pro')  # or openai/gpt-4o, anthropic/claude-3-sonnet
predictor = DSPy::Predictor.new(YourSignature, lm: lm)

# DSPy.rb automatically selects optimal strategy
result = predictor.call(input: your_data)
# Returns fully validated Ruby objects
```

No strategy configuration needed—DSPy.rb chooses the best approach based on your model.

## Observability and Monitoring

Track performance across strategies with built-in observability:

```ruby
# Monitor performance metrics
DSPy.events.subscribe('lm.tokens') do |event_name, attributes|
  puts "Response time: #{attributes['duration']}s"
  puts "Tokens used: #{attributes[:total_tokens]}"
  puts "Model: #{attributes['gen_ai.request.model']}"
  puts "Request ID: #{attributes['request_id']}"
end
```

This enables A/B testing between strategies and providers with real performance data.

## Looking Forward: sorbet-baml Integration

We're working on integrating [BAML (Boundary ML)](https://github.com/vicentereig/sorbet-baml) signatures with DSPy.rb to provide:

- **Alternative type definition syntax** for teams preferring BAML's approach
- **Cross-library compatibility** between DSPy.rb and pure BAML projects  
- **Migration paths** for existing BAML users wanting DSPy.rb's optimization features
- **Performance comparisons** between type definition approaches

This integration will give Ruby developers choice in how they define structured outputs while maintaining DSPy.rb's automatic provider optimization.

## Choosing Your Strategy

Our comprehensive benchmark reveals clear performance patterns across 27 test combinations:

**For most applications:** Start with Enhanced Prompting. Despite one failure (with the experimental `o1` model), its 92.3% success rate and universal compatibility across 13 models make it the safest default choice. You can always optimize later.

**For speed-critical applications:** Gemini Structured Output delivers the fastest performance at 3.42s, but limits you to a single model. Anthropic strategies offer good speed (6.23-6.41s) with broader model choices.

**For cost-sensitive deployments:** Gemini Flash with Enhanced Prompting provides production-quality results at $0.000114 per extraction—144x cheaper than premium alternatives.

**For maximum reliability:** Provider-specific strategies achieve 100% success rates on their compatible models. If you can accept provider lock-in, these offer the strongest guarantees.

**The Enhanced Prompting advantage:** While provider-specific strategies achieved perfect success rates, Enhanced Prompting's ability to work across all providers with competitive performance makes it uniquely valuable for production systems that need flexibility.

The beauty of DSPy.rb's approach is that your type definitions remain constant regardless of strategy. This means you can start with Enhanced Prompting for universal compatibility, then optimize with provider-specific strategies for critical use cases, all without changing your data structures.

---

*Performance data from September 14, 2025 benchmarks: 27 total tests across 5 strategies and 13 AI models using DSPy.rb. Total benchmark cost: $0.2302. Individual results may vary based on model versions and API changes.*
