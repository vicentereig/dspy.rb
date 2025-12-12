---
layout: blog
title: "DSPy.rb + Sidekiq: Non-blocking LLM Processing in Production"
date: 2025-09-01
description: "How DSPy.rb's async architecture enables efficient background processing with Sidekiq, avoiding thread blocking during LLM API calls"
author: "Vicente Reig"
tags: ["async", "sidekiq", "performance", "production", "concurrency"]
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/dspy-async-sidekiq-integration/"
image: /images/og/dspy-async-sidekiq-integration.png
---

LLM API calls take 2-5 seconds each. In a Sidekiq worker processing hundreds of jobs, this can quickly exhaust your thread pool and create bottlenecks. DSPy.rb's async architecture solves this by using Ruby's `async` gem for non-blocking I/O operations.

## How DSPy.rb Handles Async Operations

### LM#chat Uses Sync Blocks Internally

Every DSPy predictor call uses `Sync` blocks for non-blocking HTTP requests:

```ruby
# From lib/dspy/lm.rb - DSPy's internal implementation
def chat(inference_module, input_values, &block)
  Sync do  # Non-blocking fiber context
    signature_class = inference_module.signature_class
    
    # Build messages from inference module
    messages = build_messages(inference_module, input_values)
    
    # Execute with instrumentation - HTTP calls don't block threads
    response = instrument_lm_request(messages, signature_class.name) do
      chat_with_strategy(messages, signature_class, &block)
    end
    
    # Parse response
    parse_response(response, input_values, signature_class)
  end
end
```

When you call `predictor.call()`, DSPy automatically wraps the HTTP request in a `Sync` block. This means:

- **HTTP requests don't block threads** - other work can proceed
- **Fibers yield control** during I/O operations
- **Concurrent operations** are possible within the same thread

## The Sidekiq Threading Problem

### Blocking Approach - Inefficient Thread Usage

```ruby
# ❌ Blocking approach - ties up worker thread during API calls
class BlockingLLMProcessor
  include Sidekiq::Worker
  sidekiq_options concurrency: 5  # Only 5 workers can run
  
  def perform(task_id)
    # Each call blocks the worker thread for 2-5 seconds
    classification = classifier.call(text: input_text)     # Blocks ~2s
    summary = summarizer.call(content: long_content)       # Blocks ~3s  
    analysis = analyzer.call(data: classification)         # Blocks ~2s
    
    # Total: ~7s of blocked thread time per job
    # With 5 workers = maximum 5 jobs can process concurrently
    # Throughput: ~43 jobs/minute (5 workers * 60s / 7s per job)
    
    save_results(classification, summary, analysis)
  end
end
```

### Non-blocking Approach - Efficient Resource Utilization

```ruby
# ✅ Non-blocking approach - efficient thread utilization
class AsyncLLMProcessor
  include Sidekiq::Worker
  sidekiq_options concurrency: 5
  
  def perform(task_id)
    Async do |task|
      # LLM calls can run concurrently, threads yield during I/O
      classification_task = task.async { classifier.call(text: input_text) }
      summary_task = task.async { summarizer.call(content: long_content) }
      
      # Wait for dependencies
      classification = classification_task.wait
      analysis_task = task.async { analyzer.call(data: classification) }
      
      # Collect results
      summary = summary_task.wait
      analysis = analysis_task.wait
      
      # Total wall-clock time: ~3s (longest single operation)
      # Worker threads can handle other jobs during I/O waits
      # Throughput: ~100 jobs/minute (much higher due to better utilization)
      
      save_results(classification, summary, analysis)
    end.wait  # Ensure completion before worker finishes
  end
end
```

## Real-World Example: Document Processing Pipeline

Here's a complete example processing documents with multiple LLM operations:

```ruby
require 'sidekiq'

class DocumentProcessor
  include Sidekiq::Worker
  sidekiq_options queue: 'document_processing', retry: 2
  
  def perform(document_id)
    document = Document.find(document_id)
    document.update!(status: :processing)
    
    # Process with concurrent LLM operations
    result = Async do |task|
      # Stage 1: Parallel extraction (independent operations)
      title_task = task.async { title_extractor.call(content: document.content) }
      keywords_task = task.async { keyword_extractor.call(content: document.content) }
      category_task = task.async { categorizer.call(content: document.content) }
      
      # Stage 2: Wait for extraction results
      title = title_task.wait
      keywords = keywords_task.wait  
      category = category_task.wait
      
      # Stage 3: Dependent operations using extraction results
      summary_task = task.async do
        summarizer.call(
          content: document.content,
          title: title.title,
          keywords: keywords.keywords
        )
      end
      
      quality_task = task.async do
        quality_checker.call(
          title: title.title,
          category: category.category,
          content: document.content
        )
      end
      
      # Wait for all results
      summary = summary_task.wait
      quality = quality_task.wait
      
      {
        title: title,
        keywords: keywords,
        category: category,
        summary: summary,
        quality_score: quality.score
      }
    end.wait
    
    # Save results and update status
    document.update!(
      processed_title: result[:title].title,
      extracted_keywords: result[:keywords].keywords.join(', '),
      category: result[:category].category,
      summary: result[:summary].summary,
      quality_score: result[:quality_score],
      status: :completed
    )
    
  rescue => e
    document.update!(status: :failed, error_message: e.message)
    raise  # Let Sidekiq handle retry
  end
  
  private
  
  # Memoize DSPy predictors to avoid recreation
  def title_extractor
    @title_extractor ||= DSPy::Predict.new(TitleExtractor)
  end
  
  def keyword_extractor  
    @keyword_extractor ||= DSPy::Predict.new(KeywordExtractor)
  end
  
  def categorizer
    @categorizer ||= DSPy::Predict.new(DocumentCategorizer)
  end
  
  def summarizer
    @summarizer ||= DSPy::ChainOfThought.new(DocumentSummarizer)
  end
  
  def quality_checker
    @quality_checker ||= DSPy::Predict.new(QualityChecker)
  end
end
```

## Performance Comparison

### Sequential vs Concurrent Processing

```ruby
# Sequential approach (blocking)
start_time = Time.now
title = title_extractor.call(content: content)          # 2s
keywords = keyword_extractor.call(content: content)     # 2s  
category = categorizer.call(content: content)           # 2s
summary = summarizer.call(title: title, content: content) # 3s
# Total: 9 seconds wall-clock time

# Concurrent approach (non-blocking)
start_time = Time.now
result = Async do |task|
  # Stage 1: Independent operations (parallel)
  title_task = task.async { title_extractor.call(content: content) }
  keywords_task = task.async { keyword_extractor.call(content: content) }  
  category_task = task.async { categorizer.call(content: content) }
  
  # Stage 2: Dependent operation (waits for title)
  title = title_task.wait
  summary_task = task.async { summarizer.call(title: title, content: content) }
  
  # Collect results
  {
    title: title,
    keywords: keywords_task.wait,
    category: category_task.wait,
    summary: summary_task.wait
  }
end.wait
# Total: ~3 seconds wall-clock time (longest single operation)
```

## Sidekiq Configuration for DSPy.rb

### Optimal Worker Configuration

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.concurrency = 10  # Increase since workers don't block during I/O
end

# Separate queues by priority and resource requirements
Sidekiq.configure_client do |config|
  config.default_queue_name = 'default'
end

# Queue configuration
class LLMProcessor
  include Sidekiq::Worker
  sidekiq_options queue: 'llm_processing',    # LLM operations
                  retry: 3,
                  backtrace: true
end

class FastProcessor  
  include Sidekiq::Worker
  sidekiq_options queue: 'fast_processing',   # Quick operations
                  retry: 5
end
```

### Monitoring Async Performance

```ruby
# Add timing instrumentation to measure async benefits
class InstrumentedProcessor
  include Sidekiq::Worker
  
  def perform(task_id)
    start_time = Time.now
    
    result = Async do |task|
      # Track individual operation times
      operations = []
      
      title_task = task.async do
        op_start = Time.now
        result = title_extractor.call(content: content)
        operations << { operation: 'title_extraction', duration: Time.now - op_start }
        result
      end
      
      # ... other operations
      
      title_task.wait
    end.wait
    
    total_time = Time.now - start_time
    
    # Log performance metrics
    Sidekiq.logger.info("Processed #{task_id} in #{total_time}s with #{operations.length} LLM calls")
    operations.each do |op|
      Sidekiq.logger.info("  #{op[:operation]}: #{op[:duration]}s")
    end
  end
end
```

## Best Practices

### 1. Design for Concurrency

Structure your DSPy pipelines to maximize concurrent operations:

```ruby
# ✅ Good: Independent operations can run in parallel
Async do |task|
  extract_task = task.async { extract_entities(document) }
  classify_task = task.async { classify_document(document) }
  
  entities = extract_task.wait
  classification = classify_task.wait
end

# ❌ Less efficient: Sequential dependencies
classification = classify_document(document)  # Must finish first
entities = extract_entities(document, classification)  # Depends on classification
```

### 2. Memoize DSPy Objects

Create DSPy predictors once, reuse across jobs:

```ruby
class EfficientProcessor
  include Sidekiq::Worker
  
  private
  
  # ✅ Good: Memoized predictors
  def summarizer
    @summarizer ||= DSPy::ChainOfThought.new(Summarizer)
  end
  
  # ❌ Bad: Creating new instances every time
  def summarizer
    DSPy::ChainOfThought.new(Summarizer)  # Expensive recreation
  end
end
```

### 3. Handle Failures Gracefully

```ruby
def perform(document_id)
  Async do |task|
    operations = [
      task.async { safe_llm_call { title_extractor.call(content) } },
      task.async { safe_llm_call { categorizer.call(content) } }
    ]
    
    # Wait for all, handle partial failures
    results = operations.map do |op_task|
      begin
        op_task.wait
      rescue => e
        Sidekiq.logger.warn("LLM operation failed: #{e.message}")
        nil  # Partial failure, continue processing
      end
    end
    
    # Process non-nil results
    results.compact.each { |result| save_result(result) }
  end.wait
end

private

def safe_llm_call(&block)
  retries = 0
  begin
    yield
  rescue => e
    retries += 1
    if retries < 3
      sleep(retries * 0.5)  # Exponential backoff
      retry
    else
      raise
    end
  end
end
```

## Key Takeaways

DSPy.rb's async architecture enables efficient background processing:

- **Non-blocking I/O**: Worker threads can handle other jobs during LLM API waits
- **Concurrent operations**: Multiple LLM calls can run simultaneously  
- **Better throughput**: Significantly higher jobs/minute with proper async usage
- **Resource efficiency**: More work with the same thread pool size

Understanding these patterns is crucial for production DSPy.rb applications that need to process high volumes of LLM operations efficiently.

---

*For more DSPy.rb production patterns, check out our [production guide](/dspy.rb/production/) and [observability documentation](/dspy.rb/production/observability/).*
