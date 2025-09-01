---
layout: docs
name: Observability
description: Monitor and trace your DSPy applications in production
breadcrumb:
- name: Production
  url: "/production/"
- name: Observability
  url: "/production/observability/"
prev:
  name: Storage System
  url: "/production/storage/"
next:
  name: Registry
  url: "/production/registry/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-09 00:00:00 +0000
---
# Observability

DSPy.rb provides a simple, lightweight observability system based on structured logging and span tracking. The system is designed to be OTEL/Langfuse compatible while maintaining minimal overhead.

## Overview

The observability system offers:
- **Span Tracking**: Trace operations with parent-child relationships
- **Structured Logging**: JSON or key=value format based on environment
- **Context Propagation**: Automatic trace correlation across operations
- **GenAI Conventions**: Following OpenTelemetry semantic conventions for LLMs
- **Zero Dependencies**: No external instrumentation libraries required
- **Thread-Safe**: Isolated context per thread

## Architecture

DSPy.rb uses a simple Context system for observability:

```ruby
# lib/dspy/context.rb - ~50 lines total
module DSPy
  class Context
    # Thread-local storage for trace context
    # Manages span stack and trace IDs
  end
end
```

## Basic Configuration

### Enable Logging

```ruby
DSPy.configure do |config|
  # Configure logger (uses Dry::Logger)
  config.logger = Dry.Logger(:dspy)
  
  # Or with custom configuration
  config.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(stream: "log/production.log")
  end
end
```

### Environment-Aware Formatting

The logger automatically detects the environment:
- **Production** (`RAILS_ENV=production` or `RACK_ENV=production`): JSON format
- **Development/Test**: Key=value format for readability

## Using the Context System

### Basic Span Tracking

```ruby
# Wrap any operation in a span
DSPy::Context.with_span(
  operation: 'my_operation',
  'my.attribute' => 'value'
) do
  # Your code here
  result = perform_work()
  
  # Log events within the span
  DSPy.log('my.event', result: result, status: 'success')
  
  result
end
```

### Nested Spans

Spans automatically track parent-child relationships:

```ruby
DSPy::Context.with_span(operation: 'parent_operation') do
  # Parent span
  
  DSPy::Context.with_span(operation: 'child_operation') do
    # Child span - automatically linked to parent
  end
end
```

### Accessing Current Context

```ruby
# Get current trace context
context = DSPy::Context.current
# => { trace_id: "uuid", span_stack: ["parent_id", "current_id"] }

# Check if in a span
if DSPy::Context.current[:span_stack].any?
  # Currently within a span
end
```

## Semantic Conventions

DSPy.rb follows GenAI semantic conventions for LLM operations:

### LLM Operations

```ruby
# Automatically added by DSPy::LM
DSPy::Context.with_span(
  operation: 'llm.generate',
  'gen_ai.system' => 'openai',
  'gen_ai.request.model' => 'gpt-4',
  'gen_ai.usage.prompt_tokens' => 150,
  'gen_ai.usage.completion_tokens' => 50
) do
  # LLM call
end
```

### Module Operations

```ruby
# Automatically added by DSPy modules
DSPy::Context.with_span(
  operation: 'dspy.predict',
  'dspy.module' => 'ChainOfThought',
  'dspy.signature' => 'QuestionAnswering'
) do
  # Module execution
end
```

## Reading Logs

### JSON Format (Production)

```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "level": "INFO",
  "event": "llm.generate",
  "trace_id": "123e4567-e89b-12d3-a456-426614174000",
  "span_id": "987fcdeb-51a2-43f1-9012-345678901234",
  "parent_span_id": "abcdef12-3456-7890-abcd-ef1234567890",
  "gen_ai.system": "openai",
  "gen_ai.request.model": "gpt-4",
  "duration_ms": 1250
}
```

### Key=Value Format (Development)

```
timestamp=2024-01-15T10:30:45.123Z level=INFO event=llm.generate trace_id=123e4567 span_id=987fcdeb parent_span_id=abcdef12 gen_ai.system=openai gen_ai.request.model=gpt-4 duration_ms=1250
```

## Integration with External Systems

### Exporting to OpenTelemetry

Since DSPy.rb logs follow OTEL conventions, you can use log forwarding:

```ruby
# Use a log forwarder to send JSON logs to OTEL collector
# Configure your infrastructure to forward logs from:
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(stream: "/var/log/dspy/traces.json")
  end
end
```

### Langfuse Integration

Langfuse can ingest the JSON logs directly:

```bash
# Forward logs to Langfuse using their log ingestion API
tail -f log/production.log | \
  jq -c 'select(.event | startswith("llm"))' | \
  curl -X POST https://api.langfuse.com/logs \
    -H "Authorization: Bearer $LANGFUSE_API_KEY" \
    -H "Content-Type: application/json" \
    -d @-
```

### Custom Processing

Process logs with your preferred tools:

```ruby
# Parse and analyze logs
File.foreach("log/production.log") do |line|
  event = JSON.parse(line)
  
  if event["event"] == "llm.generate"
    # Track LLM usage
    tokens = event["gen_ai.usage.total_tokens"]
    model = event["gen_ai.request.model"]
    # ... your analytics
  end
end
```

## Common Patterns

### Adding Custom Attributes

```ruby
class MyModule < DSPy::Module
  def forward(**inputs)
    DSPy::Context.with_span(
      operation: 'my_module.process',
      'module.version' => '1.0',
      'module.customer_id' => customer_id
    ) do
      # Your logic
      result = process(inputs)
      
      # Log custom metrics
      DSPy.log('my_module.complete', 
        items_processed: result.count,
        processing_time: elapsed_time
      )
      
      result
    end
  end
end
```

### Error Tracking

```ruby
DSPy::Context.with_span(operation: 'risky_operation') do
  begin
    perform_operation()
  rescue => e
    DSPy.log('error.occurred',
      error_class: e.class.name,
      error_message: e.message,
      error_backtrace: e.backtrace.first(5)
    )
    raise
  end
end
```

### Performance Monitoring

```ruby
start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

DSPy::Context.with_span(operation: 'batch_process') do
  results = process_batch(items)
  
  duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
  
  DSPy.log('batch.complete',
    duration_ms: (duration * 1000).round(2),
    items_count: items.size,
    success_rate: results.count(&:success?) / items.size.to_f
  )
  
  results
end
```

## Migration from Old Instrumentation

If you were using the old instrumentation system:

### Before (Old System)
```ruby
# Complex configuration
DSPy.configure do |config|
  config.instrumentation.enabled = true
  config.instrumentation.subscribers = [:logger, :otel]
  config.instrumentation.sampling_rate = 0.1
end

# Event emission
DSPy::Instrumentation.instrument('my.event', payload) do
  work()
end
```

### After (New System)
```ruby
# Simple configuration
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy)
end

# Span tracking
DSPy::Context.with_span(operation: 'my.event', **payload) do
  work()
end
```

## Best Practices

1. **Use Semantic Names**: Follow dot notation for operations (e.g., `user.signup`, `llm.generate`)

2. **Keep Attributes Flat**: Avoid deeply nested attribute structures

3. **Limit Attribute Size**: Don't log large payloads as span attributes

4. **Use Consistent Keys**: Maintain consistent attribute naming across your application

5. **Sample in Production**: For high-volume applications, implement sampling:
   ```ruby
   # Simple sampling
   if rand < 0.1  # 10% sampling
     DSPy::Context.with_span(operation: 'sampled_op') do
       # ...
     end
   else
     # Execute without span tracking
   end
   ```

## Troubleshooting

### No Logs Appearing

Check that logger is configured:
```ruby
DSPy.config.logger # Should not be nil
```

### Missing Trace Correlation

Ensure operations are wrapped in spans:
```ruby
# Correct - with span
DSPy::Context.with_span(operation: 'my_op') do
  DSPy.log('my.event', data: 'value')
end

# Incorrect - no span context
DSPy.log('my.event', data: 'value')  # Will log but no trace_id
```

### Thread Safety Issues

Context is thread-local, so each thread has isolated context:
```ruby
Thread.new do
  # This thread has its own context
  DSPy::Context.with_span(operation: 'thread_op') do
    # ...
  end
end
```

## Langfuse Integration (Zero Configuration)

DSPy.rb includes **zero-config Langfuse integration** via OpenTelemetry. Simply set your Langfuse environment variables and DSPy will automatically export spans to Langfuse alongside the normal logging.

### Setup

```bash
# Required environment variables
export LANGFUSE_PUBLIC_KEY=pk-lf-your-public-key
export LANGFUSE_SECRET_KEY=sk-lf-your-secret-key

# Optional: specify host (defaults to cloud.langfuse.com)
export LANGFUSE_HOST=https://cloud.langfuse.com  # or https://us.cloud.langfuse.com
```

### How It Works

When Langfuse environment variables are detected, DSPy automatically:

1. **Configures OpenTelemetry SDK** with OTLP exporter
2. **Creates dual output**: Both structured logs AND OpenTelemetry spans
3. **Exports to Langfuse** using proper authentication and endpoints
4. **Falls back gracefully** if OpenTelemetry gems are missing or configuration fails

### Example Output

With Langfuse configured, your DSPy applications will send traces like this:

**In your logs** (as usual):
```json
{
  "severity": "INFO",
  "time": "2025-08-08T22:02:57Z",
  "trace_id": "abc-123-def",
  "span_id": "span-456",
  "parent_span_id": "span-789",
  "operation": "ChainOfThought.forward",
  "dspy.module": "ChainOfThought",
  "event": "span.start"
}
```

**In Langfuse** (automatically):
```
Trace: abc-123-def
├─ ChainOfThought.forward [2000ms]
│  ├─ Module: ChainOfThought
│  └─ llm.generate [1000ms]
│     ├─ Model: gpt-4-0613
│     ├─ Temperature: 0.7
│     ├─ Tokens: 100 in / 50 out / 150 total
│     └─ Cost: $0.0021 (calculated by Langfuse)
```

### GenAI Semantic Conventions

DSPy automatically includes OpenTelemetry GenAI semantic conventions:

```ruby
# LLM operations automatically include:
{
  "gen_ai.system": "openai",
  "gen_ai.request.model": "gpt-4",
  "gen_ai.response.model": "gpt-4-0613",
  "gen_ai.usage.prompt_tokens": 100,
  "gen_ai.usage.completion_tokens": 50,
  "gen_ai.usage.total_tokens": 150
}
```

### Manual Configuration (Advanced)

For custom OpenTelemetry setups, you can disable auto-configuration and set up manually:

```ruby
# Disable auto-config by not setting Langfuse env vars
# Then configure OpenTelemetry yourself:

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure do |config|
  config.service_name = 'my-dspy-app'
  # Your custom configuration
end
```

### Dependencies

The Langfuse integration requires these gems (automatically included):
- `opentelemetry-sdk` (~> 1.8)
- `opentelemetry-exporter-otlp` (~> 0.30)

If these gems are not available, DSPy gracefully falls back to logging-only mode.

### Troubleshooting Langfuse Integration

**Spans not appearing in Langfuse:**
1. Verify environment variables are set correctly
2. Check Langfuse host/region (EU vs US)
3. Ensure network connectivity to Langfuse endpoints

**OpenTelemetry errors:**
1. Check that required gems are installed: `bundle install`
2. Look for observability error logs: `grep "observability.error" log/production.log`

**Authentication issues:**
1. Verify your public and secret keys are correct
2. Check that keys have proper permissions in Langfuse dashboard

## Summary

The observability system in DSPy.rb provides three modes of operation:

1. **Logging Only** (default): Structured logs with span tracking
2. **Langfuse Integration** (zero-config): Logs + automatic OpenTelemetry export
3. **Custom OTEL** (advanced): Full control over OpenTelemetry configuration

Key benefits:
- **Zero-config Langfuse**: Just set env vars and it works
- **Non-invasive**: Logging still works without Langfuse
- **Standards-compliant**: Uses OpenTelemetry GenAI semantic conventions
- **Graceful degradation**: Falls back to logging if anything fails
- **Minimal overhead**: ~100 lines of observability code total

For most applications, the zero-config Langfuse integration provides production-ready observability with minimal setup.