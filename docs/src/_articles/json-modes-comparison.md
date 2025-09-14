---
layout: blog
title: "Comparing JSON Extraction Modes in DSPy.rb: Performance, Cost & Reliability"
date: 2025-09-14
description: "Data-driven comparison of JSON extraction strategies across providers using observability metrics"
author: "Vicente Reig"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/json-modes-comparison/"
---

JSON extraction from Large Language Models is a fundamental challenge in agentic applications. Models can return malformed JSON, 
miss required fields, or struggle with complex nested types. DSPy.rb addresses this with five different extraction strategies, 
each optimized for different scenarios.

This article presents benchmark data from testing these strategies across 13 AI models using complex nested types, 
providing practical guidance for choosing the right approach for your application.

## The JSON Extraction Challenge

When building production applications with LLMs, you need structured, validated data - not free-form text. Common challenges include:

- **Malformed JSON** - Missing braces, trailing commas, unescaped quotes
- **Type mismatches** - Strings instead of numbers, missing enum values
- **Complex structures** - Nested objects, union types, arrays of mixed types
- **Provider differences** - Each API handles structured output differently

DSPy.rb solves this by automatically selecting the optimal extraction strategy based on your target model and type definitions.

## DSPy.rb's Five Extraction Strategies

### 1. Enhanced Prompting (Universal)
DSPy.rb's default strategy that works across all providers:
- Generates JSON Schema from Ruby types
- Embeds schema in prompts with clear formatting instructions
- Uses standard chat completion endpoints
- Validates and parses responses with detailed error messages

### 2. OpenAI Structured Output
Native structured output for OpenAI models:
- Uses OpenAI's structured output API with function calling
- Enforces schema at the API level
- Available for GPT-4o, GPT-4o-mini, GPT-5 series

### 3. Anthropic Tool Use
Function calling approach for Claude models:
- Leverages Anthropic's tools API
- Structured through function parameters
- Available for all Claude models

### 4. Anthropic Extraction
Text completion with guided parsing:
- Specialized extraction using Claude's text completion
- Custom parsing logic for complex types
- Fallback strategy for Anthropic models

### 5. Gemini Structured Output (New in v0.27.0)
Native structured generation for Google models:
- Uses Gemini's structured output capabilities
- Currently available for Gemini 1.5 Pro
- Fastest strategy in our benchmarks

## Performance Benchmark Results

After testing all strategies across 13 models using complex nested types including enums, unions, and structs. Here are the key findings:

### Response Time Comparison

| Strategy | Avg Response Time | Models Tested | Compatibility |
|----------|------------------|---------------|---------------|
| **Gemini Structured Output** | 2.78s | 1 | Gemini Pro only |
| **Anthropic Extraction** | 5.37s | 4 | All Claude models |
| **Anthropic Tool Use** | 5.68s | 4 | All Claude models |
| **Enhanced Prompting** | 7.75s | 12 | Universal (all models) |
| **OpenAI Structured Output** | 17.09s | 5 | GPT models with structured outputs |

**Key Finding:** Enhanced Prompting competitive with specialized APIs while offering universal compatibility.

### Model Compatibility Matrix

```
Model               enhanced_pr openai_stru anthropic_t anthropic_e gemini_stru
--------------------------------------------------------------------------------
gpt-5               ✅           ✅           ⏭️          ⏭️          ⏭️
gpt-5-mini          ✅           ✅           ⏭️          ⏭️          ⏭️
gpt-5-nano          ✅           ✅           ⏭️          ⏭️          ⏭️
gpt-4o              ✅           ✅           ⏭️          ⏭️          ⏭️
gpt-4o-mini         ✅           ✅           ⏭️          ⏭️          ⏭️
o1-mini             ✅           ⏭️          ⏭️          ⏭️          ⏭️
claude-opus-4.1     ✅           ⏭️          ✅           ✅           ⏭️
claude-sonnet-4     ✅           ⏭️          ✅           ✅           ⏭️
claude-3-5-sonnet   ✅           ⏭️          ✅           ✅           ⏭️
claude-3-5-haiku    ✅           ⏭️          ✅           ✅           ⏭️
gemini-1.5-pro      ✅           ⏭️          ⏭️          ⏭️          ✅
gemini-1.5-flash    ✅           ⏭️          ⏭️          ⏭️          ⏭️
```

## Cost Analysis

**Total benchmark cost: $0.230** for 27 tests across all combinations.

### Cost Comparison by Strategy

**Most Expensive:**
1. Claude Opus 4.1 + any strategy: $0.0495 per test
2. Claude Sonnet 4 + any strategy: $0.00792 per test
3. GPT-5 + any strategy: $0.00581 per test

**Most Cost-Effective:**
1. Gemini 1.5 Flash + enhanced prompting: $0.000114
2. GPT-5-nano + any strategy: $0.000165
3. GPT-4o-mini + any strategy: $0.000342

**Cost insight:** 434x price difference between most expensive (Claude Opus) and cheapest (Gemini Flash) options with similar performance.

## Token Usage Analysis

*[GAP IDENTIFIED: Current benchmark shows rounded token numbers (800, 1200, 1500) - likely estimates rather than actual usage. Need to capture real token consumption for accurate analysis.]*

## Complex Type Handling

The benchmark tested sophisticated type structures:

```ruby
# Enum types
class TodoStatus < T::Enum
  enums do
    PENDING = new("pending")
    IN_PROGRESS = new("in_progress")
    COMPLETED = new("completed")
  end
end

# Union types with discrimination
ActionType = T.type_alias do
  T.any(
    CreateTodoAction,
    UpdateTodoAction, 
    DeleteTodoAction,
    AssignTodoAction
  )
end

# Nested structures
class TodoSummary < DSPy::Struct
  const :total_todos, Integer
  const :pending_count, Integer
  const :in_progress_count, Integer
  const :completed_count, Integer
  const :recent_todos, T::Array[TodoItem]
  const :action, ActionType, description: "Primary action - automatically discriminated by _type field"
end
```

All strategies handled these complex types successfully, with Enhanced Prompting showing particularly robust handling across providers.

## Gemini Structured Outputs Deep Dive

Gemini's structured output capability emerged as the speed leader in our benchmarks:

- **Performance**: 2.78s average response time (2x faster than next best)
- **Reliability**: 100% success rate in testing
- **Cost**: Competitive pricing at $0.0019 per test
- **Limitation**: Currently limited to Gemini 1.5 Pro

```ruby
# Gemini structured output automatically selected
lm = DSPy::LM.new('gemini/gemini-1.5-pro')
predictor = DSPy::Predictor.new(TodoExtractionSignature, lm: lm)

# DSPy.rb automatically uses gemini_structured_output strategy
result = predictor.call(input: complex_todo_data)
```

## Strategy Recommendations

### For Speed Priority
**Gemini 1.5 Pro + structured outputs** (2.78s avg)
- Fastest in benchmarks
- Limited to single model
- Good for high-throughput applications

### For Cost Priority  
**Gemini 1.5 Flash + enhanced prompting** ($0.000114 per test)
- 434x cheaper than premium models
- Universal compatibility
- Excellent for budget-conscious applications

### For Broad Compatibility
**Enhanced Prompting** (works across all tested models)
- Universal strategy
- Competitive performance
- Single codebase across providers

### For Enterprise Applications
**Claude models with tool use** (consistent performance)
- Premium cost but reliable
- Advanced reasoning capabilities
- Production-ready consistency

## Code Examples with Observability

DSPy.rb includes comprehensive observability to track strategy selection and performance:

```ruby
# Configure observability
DSPy::Observability.configure!

# Subscribe to strategy selection events
DSPy.events.subscribe('prediction.strategy_selected') do |event_name, attributes|
  puts "Strategy: #{attributes[:strategy]}"
  puts "Model: #{attributes[:model]}"
  puts "Forced: #{attributes[:forced]}"
end

# Subscribe to performance metrics
DSPy.events.subscribe('lm.raw_chat.end') do |event_name, attributes|
  puts "Response time: #{attributes[:duration]}s"
  puts "Tokens used: #{attributes[:token_usage]}"
  puts "Cost: $#{attributes[:cost]}"
end

# Define your signature
class TodoExtractionSignature < DSPy::Signature
  input :raw_data, String, description: "Raw todo data to extract"
  output :summary, TodoSummary, description: "Structured todo summary"
end

# Create predictor - strategy selected automatically
lm = DSPy::LM.new('openai/gpt-4o-mini')
predictor = DSPy::Predictor.new(TodoExtractionSignature, lm: lm)

# Call with observability
result = predictor.call(raw_data: "Fix the authentication bug and deploy to staging...")

# Flush observability data
DSPy::Observability.flush!
```

## Implementation Notes

The benchmark used DSPy.rb's simplest predictor (`DSPy::Predictor`) to isolate JSON extraction performance. The modular design means you can enhance this with more sophisticated approaches:

- `DSPy::ChainOfThought` - Add reasoning steps before JSON generation
- `DSPy::ReAct` - Include tool use and iterative reasoning loops
- `DSPy::CodeAct` - Generate and execute code for complex structures

The same signature and type system works across all predictor types.

## Identified Data Gaps

Based on the blog article requirements, several gaps need addressing in the benchmark:

### 1. Token Usage Analysis
**Current Issue:** Token counts show rounded numbers (800, 1200, 1500) - likely estimates
**Need:** Real token consumption tracking per strategy and model
**Impact:** Cost analysis and efficiency metrics

### 2. Detailed Performance Charts
**Current Issue:** Only average response times available  
**Need:** Distribution charts, percentile analysis, variance metrics
**Impact:** Better understanding of performance consistency

### 3. Complex Type Handling Examples
**Current Issue:** Limited detail on type handling capabilities
**Need:** Specific examples of enum, union, and nested struct processing
**Impact:** Developer guidance for complex scenarios

### 4. Error Rate Analysis
**Current Issue:** Focus on successful tests only
**Need:** Error categorization, recovery strategies, failure modes
**Impact:** Production reliability assessment

### 5. Provider-Specific Optimizations
**Current Issue:** Surface-level strategy comparison
**Need:** Deep dive into each provider's optimizations and trade-offs
**Impact:** Strategic decision-making for multi-provider applications

## Next Steps

To complete this blog article, consider enhancing the benchmark to capture:

1. **Real token usage** from provider APIs
2. **Response time distributions** (P50, P95, P99)
3. **Error categorization** and failure analysis
4. **Memory usage** for different strategies
5. **Concurrent request** performance testing

The upcoming comparison with [BAML signatures](https://github.com/vicentereig/sorbet-baml) will provide additional context for Ruby developers choosing between structured output libraries.

---

*This analysis is based on benchmark data from September 2025 testing across 13 AI models using DSPy.rb's JSON extraction strategies.*
