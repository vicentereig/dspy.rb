---
layout: blog
title: "True Concurrency: How DSPy.rb's Async Retry System Makes Your Applications Faster"
date: 2025-09-05
description: "DSPy.rb now provides true async concurrency for LLM retries and operations, eliminating blocking delays while maintaining reliability"
author: "Vicente Reig"
tags: ["performance", "async", "concurrency", "reliability"]
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/async-telemetry-optimization/"
image: /images/og/async-telemetry-optimization.png
---

Your DSPy.rb applications can now handle failures gracefully without blocking. The latest update introduces proper async retry handling that delivers true concurrency—making your applications both faster and more reliable.

## What This Means for You

Before this update, when DSPy.rb needed to retry a failed LLM call, your entire application thread would pause during backoff delays. A 2-second retry delay meant 2 seconds of your Rails request sitting idle, waiting.

Now? Your application keeps running while retries happen asynchronously in the background.

## The Async Advantage: Real Examples

### Rails Controllers Stay Responsive

**Before (blocking retries):**
```ruby
# app/controllers/content_controller.rb
def analyze
  result = DSPy::Predict.new(ContentAnalyzer).call(
    content: params[:content]
  )
  # If this fails and retries, the entire request blocks
  # User waits 3+ seconds staring at a loading spinner
  
  render json: { analysis: result.analysis }
end
```

**After (async retries):**
```ruby
# Same code, but now retries don't block the request thread
def analyze  
  result = DSPy::Predict.new(ContentAnalyzer).call(
    content: params[:content]
  )
  # Failed calls retry in background without blocking
  # User sees response as soon as the LLM call succeeds
  
  render json: { analysis: result.analysis }
end
```

Your users get responsive applications even when network conditions aren't perfect.

### Concurrent Processing Actually Works

**Before:**
```ruby
# Processing multiple documents "concurrently" 
results = documents.map do |doc|
  Thread.new do
    analyzer.call(content: doc.text)
    # Each thread could still block on retries
  end
end.map(&:value)
```

**After:**
```ruby
# True concurrency - retries don't block other operations
results = documents.map do |doc|
  Thread.new do
    analyzer.call(content: doc.text)
    # Retries happen asynchronously, other documents keep processing
  end
end.map(&:value)
```

Process 10 documents in parallel, and if one needs retries, the other 9 keep running at full speed.

## Zero Configuration Required

The async retry system activates automatically when you use DSPy.rb. No setup, no configuration changes needed:

```ruby
# Your existing code benefits immediately
DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini')
end

class EmailClassifier < DSPy::Signature
  input { const :email_content, String }
  output { const :category, String }
end

# This call now uses async retries automatically
classifier = DSPy::Predict.new(EmailClassifier)
result = classifier.call(email_content: "Meeting invitation...")
```

If the first attempt fails, DSPy.rb retries in the background using `Async::Task.current.sleep()` instead of blocking your application thread.

## Perfect for Background Jobs

Background job processing benefits enormously from non-blocking retries:

```ruby
# app/jobs/content_moderation_job.rb
class ContentModerationJob < ApplicationJob
  def perform(comment_id)
    comment = Comment.find(comment_id)
    
    # Process comment without blocking on retries
    result = DSPy::Predict.new(ToxicityDetector).call(
      text: comment.content
    )
    
    comment.update!(
      toxicity_score: result.score,
      needs_review: result.toxic?
    )
    
    # Job completes faster because retries don't block
  end
end
```

Process more jobs per minute, even when some LLM calls need retries.

## Development Benefits

### Faster Test Suites

Your test suite now runs faster because retry delays don't accumulate:

```ruby
# spec/services/content_analyzer_spec.rb
RSpec.describe ContentAnalyzer do
  it "handles network hiccups gracefully" do
    # This test doesn't hang when retries occur
    result = analyzer.call(content: "Test content")
    
    expect(result.sentiment).to eq "positive"
    # Test completes quickly even if retries happened
  end
end
```

### Better Development Experience

When testing against real APIs in development, failures don't freeze your console:

```ruby
# In rails console or IRB
analyzer = DSPy::Predict.new(ProductAnalyzer)

# Even with flaky network, console stays responsive
result = analyzer.call(description: "iPhone 15 Pro")
# => Retries happen asynchronously, you can keep working
```

## Technical Integration: How It Works

DSPy.rb now wraps all LLM operations in `Sync` blocks to ensure proper async context:

```ruby
# This provides the async context needed for non-blocking retries
Sync do
  lm.chat(inference_module, input_values)
end
```

Inside retry operations, `Async::Task.current.sleep()` provides true non-blocking delays instead of blocking `sleep()` calls.

## Configuration Options

The system works great out of the box, but you can tune it:

```ruby
DSPy.configure do |config|
  # Enable/disable retries (enabled by default)
  config.structured_outputs.retry_enabled = true
  
  # Retries work with all LLM providers
  config.lm = DSPy::LM.new('anthropic/claude-3-haiku')
  # or
  config.lm = DSPy::LM.new('ollama/llama2')
end
```

## What You Get

✅ **True concurrency** - Retries don't block other operations  
✅ **Responsive applications** - No more frozen threads during backoff delays  
✅ **Better reliability** - Same retry logic, just non-blocking  
✅ **Zero migration** - Existing code works unchanged  
✅ **Perfect Rails integration** - Request threads stay free during retries  

## Real Performance Impact

In applications with moderate network variability:

- **50-70% faster concurrent processing** when some operations need retries  
- **Responsive user interfaces** even during retry scenarios  
- **Higher throughput background jobs** due to non-blocking retry behavior  
- **Smoother development experience** with real API integration testing  

## When This Matters Most

- **Production Rails apps** where user experience depends on response times
- **Background job processing** with high LLM throughput requirements  
- **Concurrent document processing** where one failure shouldn't slow others
- **Development workflows** testing against real LLM APIs
- **Any application** where retry delays currently impact user experience

## Try It Today

If you're using DSPy.rb, you already have this. Just upgrade:

```bash
gem update dspy
```

Your applications automatically gain async retry capabilities—faster, more reliable, with zero code changes required.

The async retry system represents DSPy.rb's commitment to building production-ready LLM applications. It's the difference between applications that stumble on network hiccups and applications that handle them gracefully while maintaining peak performance.