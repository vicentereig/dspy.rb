---
layout: blog
title: "Fiber-Local LM Contexts: Clean Multi-Model Management in Ruby"
description: "DSPy.rb v0.20.0 introduces DSPy.with_lm for elegant temporary language model overrides using Ruby's fiber-local storage, enabling clean concurrent patterns and better model management."
date: 2025-08-26
author: "Vicente Reig"
category: "Features"
reading_time: "3 min read"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/fiber-local-lm-contexts/"
image: /images/og/fiber-local-lm-contexts.png
---

DSPy.rb v0.20.0 introduces a powerful new feature for managing language models in complex applications: `DSPy.with_lm`. Thanks to Stefan Froelich's excellent contribution, you can now temporarily override language models using Ruby's fiber-local storage, enabling cleaner concurrent patterns and more flexible model management.

## The Problem: Complex Model Management

Modern AI applications often need different models for different tasks:
- **Fast models** for rapid iteration and testing
- **Powerful models** for production accuracy  
- **Local models** for privacy-sensitive data
- **Specialized models** for domain-specific tasks

Previously, managing these scenarios required complex configuration juggling or passing models throughout your call stack. `DSPy.with_lm` solves this elegantly.

## Introducing DSPy.with_lm

`DSPy.with_lm` creates a temporary language model context that affects all DSPy modules within its block, using Ruby's fiber-local storage for clean, thread-safe model switching:

```ruby
require 'dspy'

# Configure a global default model
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])
end

class SentimentAnalyzer < DSPy::Module
  def initialize
    @predictor = DSPy::Predict.new(SentimentSignature)
  end
  
  def call(text:)
    @predictor.forward(text: text)
  end
end

analyzer = SentimentAnalyzer.new

# Uses global LM (gpt-4o)
result1 = analyzer.call(text: "This is amazing!")

# Temporarily switch to a different model
fast_model = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

DSPy.with_lm(fast_model) do
  # All modules in this block use the fast model
  result2 = analyzer.call(text: "This is amazing!")
  # result2 was generated using gpt-4o-mini
end

# Back to global LM (gpt-4o)
result3 = analyzer.call(text: "This is amazing!")
```

## LM Resolution Hierarchy

DSPy resolves language models in a clear hierarchy:

1. **Instance-level LM** - Explicitly set on a module instance (highest priority)
2. **Fiber-local LM** - Set via `DSPy.with_lm` 
3. **Global LM** - Set via `DSPy.configure` (lowest priority)

```ruby
# Global configuration
DSPy.configure do |config|
  config.lm = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])
end

# Module with explicit instance-level LM
analyzer = SentimentAnalyzer.new
analyzer.config.lm = DSPy::LM.new("anthropic/claude-3-sonnet", api_key: ENV['ANTHROPIC_API_KEY'])

# Instance-level LM takes precedence over everything
result1 = analyzer.call(text: "Test") # Uses Claude Sonnet

# Fiber-local doesn't override instance-level
fast_model = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
DSPy.with_lm(fast_model) do
  result2 = analyzer.call(text: "Test") # Still uses Claude Sonnet
end

# Module without instance-level LM
analyzer2 = SentimentAnalyzer.new

DSPy.with_lm(fast_model) do
  result3 = analyzer2.call(text: "Test") # Uses gpt-4o-mini (fiber-local)
end

result4 = analyzer2.call(text: "Test") # Uses gpt-4o (global)
```

## Practical Use Cases

### 1. A/B Testing Models

Compare different models on the same task without code duplication:

```ruby
class ProductRecommender < DSPy::Module
  def initialize
    @analyzer = DSPy::Predict.new(ProductAnalysisSignature)
  end
  
  def recommend(user_data:, product_catalog:)
    @analyzer.forward(
      user_data: user_data,
      product_catalog: product_catalog
    )
  end
end

recommender = ProductRecommender.new
test_user = { preferences: "tech gadgets", budget: "$500" }

# Test with different models
models = {
  "gpt-4o" => DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY']),
  "claude-3-sonnet" => DSPy::LM.new("anthropic/claude-3-sonnet", api_key: ENV['ANTHROPIC_API_KEY']),
  "gemini-1.5-pro" => DSPy::LM.new("gemini/gemini-1.5-pro", api_key: ENV['GEMINI_API_KEY'])
}

results = models.map do |model_name, model|
  DSPy.with_lm(model) do
    recommendation = recommender.recommend(
      user_data: test_user,
      product_catalog: catalog
    )
    
    {
      model: model_name,
      recommendation: recommendation,
      confidence: recommendation.confidence
    }
  end
end

# Compare results across models
results.each do |result|
  puts "#{result[:model]}: #{result[:recommendation].product_name} (#{result[:confidence]})"
end
```

### 2. Development/Production Model Switching

Use different models based on environment automatically:

```ruby
class DocumentProcessor < DSPy::Module
  def initialize
    @summarizer = DSPy::Predict.new(DocumentSummarySignature)
    @classifier = DSPy::Predict.new(DocumentTypeSignature)
  end
  
  def process(document:)
    summary = @summarizer.forward(document: document)
    classification = @classifier.forward(
      document: document,
      summary: summary.text
    )
    
    { summary: summary, classification: classification }
  end
end

def with_environment_model(&block)
  model = case Rails.env
           when 'development'
             # Fast, cheap model for development
             DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
           when 'test'
             # Consistent model for testing
             DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
           when 'production'
             # Best model for production
             DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])
           end
           
  DSPy.with_lm(model, &block)
end

# Usage throughout your app
processor = DocumentProcessor.new

with_environment_model do
  result = processor.process(document: user_document)
  # Uses appropriate model for current environment
end
```

### 3. Privacy-Sensitive Processing

Switch to local models for sensitive data:

```ruby
class MedicalRecordAnalyzer < DSPy::Module
  def initialize
    @analyzer = DSPy::Predict.new(MedicalAnalysisSignature)
  end
  
  def analyze(record:, sensitivity_level:)
    case sensitivity_level
    when :public
      # Use cloud model for non-sensitive data
      @analyzer.forward(record: record)
    when :sensitive
      # Use local model for sensitive data
      local_model = DSPy::LM.new("ollama/llama3.1:70b")
      
      DSPy.with_lm(local_model) do
        @analyzer.forward(record: record)
      end
    when :highly_sensitive
      # Use specialized local model
      secure_model = DSPy::LM.new("ollama/medllama", base_url: "https://secure-local-instance")
      
      DSPy.with_lm(secure_model) do
        @analyzer.forward(record: record)
      end
    end
  end
end

analyzer = MedicalRecordAnalyzer.new

# Public health data - uses cloud model
public_result = analyzer.analyze(
  record: public_health_data,
  sensitivity_level: :public
)

# Patient data - uses local model automatically
patient_result = analyzer.analyze(
  record: patient_record,
  sensitivity_level: :sensitive
)
```

### 4. Optimization and Fine-Tuning

Use different models during optimization phases:

```ruby
class SearchQueryOptimizer < DSPy::Module
  def initialize
    @query_enhancer = DSPy::Predict.new(QueryEnhancementSignature)
    @results_ranker = DSPy::Predict.new(ResultsRankingSignature)
  end
  
  def optimize_search(query:, results:)
    enhanced_query = @query_enhancer.forward(original_query: query)
    ranked_results = @results_ranker.forward(
      query: enhanced_query.enhanced_query,
      results: results
    )
    
    { enhanced_query: enhanced_query, ranked_results: ranked_results }
  end
end

optimizer = SearchQueryOptimizer.new

# Phase 1: Rapid iteration with fast model
fast_model = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])

test_queries = load_test_queries()
results = []

DSPy.with_lm(fast_model) do
  test_queries.each do |query|
    result = optimizer.optimize_search(
      query: query,
      results: sample_results
    )
    results << result
  end
end

# Phase 2: Final optimization with powerful model
powerful_model = DSPy::LM.new("openai/gpt-4o", api_key: ENV['OPENAI_API_KEY'])

best_queries = select_best_queries(results)

DSPy.with_lm(powerful_model) do
  best_queries.each do |query|
    final_result = optimizer.optimize_search(
      query: query,
      results: full_results_set
    )
    save_optimized_query(final_result)
  end
end
```

## Nested Contexts and Exception Safety

`DSPy.with_lm` supports nesting and guarantees cleanup even when exceptions occur:

```ruby
# Global model
DSPy.configure { |c| c.lm = global_model }

DSPy.with_lm(model_a) do
  puts DSPy.current_lm # => model_a
  
  DSPy.with_lm(model_b) do
    puts DSPy.current_lm # => model_b
    
    # Exception handling works correctly
    begin
      DSPy.with_lm(model_c) do
        puts DSPy.current_lm # => model_c
        raise "Something went wrong!"
      end
    rescue => e
      puts DSPy.current_lm # => model_b (correctly restored)
    end
    
    puts DSPy.current_lm # => model_b
  end
  
  puts DSPy.current_lm # => model_a
end

puts DSPy.current_lm # => global_model
```

## Block Return Values

`DSPy.with_lm` transparently returns the block's result:

```ruby
result = DSPy.with_lm(fast_model) do
  analyzer = SentimentAnalyzer.new
  analysis = analyzer.call(text: "This feature is amazing!")
  
  {
    sentiment: analysis.sentiment,
    confidence: analysis.confidence,
    model_used: fast_model.model
  }
end

puts result[:sentiment]    # => "positive"
puts result[:model_used]   # => "gpt-4o-mini"
```

## Thread and Fiber Safety

Fiber-local storage ensures that each fiber (including the main fiber) has its own LM context:

```ruby
require 'async'

DSPy.configure { |c| c.lm = default_model }

Async do
  # Each async task runs in its own fiber
  model_a = DSPy::LM.new("openai/gpt-4o-mini", api_key: ENV['OPENAI_API_KEY'])
  
  DSPy.with_lm(model_a) do
    result_a = analyzer.call(text: "Task A")
    # This uses model_a
  end
end

Async do
  # This fiber has its own context
  model_b = DSPy::LM.new("anthropic/claude-3-sonnet", api_key: ENV['ANTHROPIC_API_KEY'])
  
  DSPy.with_lm(model_b) do
    result_b = analyzer.call(text: "Task B")
    # This uses model_b, completely independent of the other fiber
  end
end
```

## Best Practices

1. **Use for Temporary Overrides**: Perfect for testing, optimization, or special processing needs
2. **Respect the Hierarchy**: Remember that instance-level LMs always take precedence
3. **Keep Contexts Focused**: Use `with_lm` for specific tasks rather than large application sections
4. **Document Model Choices**: Make it clear why different models are used for different contexts

```ruby
# ✅ Good: Clear, focused usage
DSPy.with_lm(fast_model) do
  # Quick validation phase
  validation_results = validate_inputs(test_data)
end

DSPy.with_lm(accurate_model) do
  # Production processing
  final_results = process_for_production(validated_data)
end

# ❌ Avoid: Wrapping entire application logic
DSPy.with_lm(some_model) do
  # Entire application runs here - defeats the purpose
  run_entire_application()
end
```

## Migration Guide

If you're currently passing models around manually, migration is straightforward:

```ruby
# Before: Manual model passing
def process_documents(documents, model)
  documents.map do |doc|
    processor = DocumentProcessor.new(lm: model)
    processor.analyze(doc)
  end
end

# After: Clean fiber-local contexts
def process_documents(documents)
  documents.map do |doc|
    processor = DocumentProcessor.new
    processor.analyze(doc)  # Uses current fiber-local or global LM
  end
end

# Usage
DSPy.with_lm(specialized_model) do
  results = process_documents(sensitive_documents)
end
```

## Conclusion

`DSPy.with_lm` brings elegant model management to DSPy.rb applications. By leveraging Ruby's fiber-local storage, you get clean, thread-safe temporary model overrides without complex configuration juggling.

Key benefits:
- **Clean Code**: No need to pass models through call stacks
- **Thread Safety**: Each fiber maintains its own LM context
- **Exception Safety**: Automatic cleanup even when errors occur
- **Flexible Testing**: Easy A/B testing and environment switching
- **Privacy Control**: Seamless switching to local models for sensitive data

Special thanks to Stefan Froelich for implementing this powerful feature! Start using `DSPy.with_lm` today to simplify your multi-model applications. 🚀