# DSPy Ruby Observability Guide

This guide covers the comprehensive observability features built into DSPy Ruby, including monitoring, tracing, metrics, and storage capabilities.

## Overview

DSPy Ruby provides multi-layered observability through several integrated systems:

- **Instrumentation System**: Core event emission with dry-monitor
- **Logger Subscriber**: Structured logging for debugging and monitoring
- **OpenTelemetry Integration**: Distributed tracing and metrics
- **New Relic Integration**: Application performance monitoring
- **Langfuse Integration**: LLM-specific observability and prompt tracking
- **Storage System**: Persistent optimization result storage
- **Registry System**: Version control and deployment tracking

## Quick Start

### Basic Logging

DSPy Ruby automatically logs all operations using structured logging:

```ruby
require 'dspy'

# Configure logging level
DSPy.configure do |config|
  config.logger.level = Logger::INFO
end

# All DSPy operations are automatically logged
predictor = DSPy::Predict.new(YourSignature)
result = predictor.call(input: "test")
# Logs: event=prediction signature=YourSignature status=success duration_ms=150.5
```

### OpenTelemetry Setup

Enable distributed tracing with OpenTelemetry:

```bash
# Set environment variables
export OTEL_SERVICE_NAME=my-dspy-app
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_EXPORTER_OTLP_HEADERS="api-key=your-key"
```

```ruby
# Install OpenTelemetry gem
gem 'opentelemetry-api'
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'

# DSPy will automatically initialize OpenTelemetry subscriber
# No additional configuration needed
```

### New Relic Setup

Monitor performance with New Relic:

```ruby
# Install New Relic gem
gem 'newrelic_rpm'

# Configure in config/newrelic.yml
# DSPy will automatically send custom metrics and events
```

### Langfuse Setup

Track LLM operations with Langfuse:

```bash
# Set environment variables
export LANGFUSE_PUBLIC_KEY=pk_your_key
export LANGFUSE_SECRET_KEY=sk_your_key
export LANGFUSE_HOST=https://cloud.langfuse.com
```

```ruby
# Install Langfuse gem
gem 'langfuse'

# DSPy will automatically create traces for optimizations and LM calls
```

## Optimization Observability

### Automatic Optimization Tracking

All optimization operations are automatically tracked:

```ruby
optimizer = DSPy::MIPROv2.new(
  metric: accuracy_metric,
  config: DSPy::Teleprompt::Teleprompter::Config.new.tap do |c|
    c.save_intermediate_results = true  # Enable storage
  end
)

result = optimizer.compile(program, trainset: train, valset: val)

# Automatically creates:
# - Optimization traces in Langfuse
# - Performance metrics in New Relic  
# - Distributed traces in OpenTelemetry
# - Stored results in storage system
# - Version registry entries
```

### Manual Instrumentation

Add custom instrumentation to your code:

```ruby
# Manual instrumentation
DSPy::Instrumentation.instrument('custom.operation', { custom: 'data' }) do
  # Your code here
end

# Manual events
DSPy::Instrumentation.emit('custom.event', {
  user_id: 123,
  action: 'prediction',
  timestamp: Time.now.iso8601
})
```

## Storage and Registry

### Storage System

Persist optimization results automatically:

```ruby
# Configure storage
config = DSPy::Storage::StorageManager::StorageConfig.new
config.auto_save = true
config.storage_path = './optimization_results'

storage = DSPy::Storage::StorageManager.new(config: config)

# Results are automatically saved during optimization
stored_program = storage.load_program('program_id')
```

### Registry System

Version control for optimized signatures:

```ruby
# Configure registry
registry_config = DSPy::Registry::SignatureRegistry::RegistryConfig.new
registry_config.auto_version = true
registry_config.max_versions_per_signature = 10

# Versions are automatically registered during optimization
registry = DSPy::Registry::SignatureRegistry.new(config: registry_config)

# Deploy specific version
deployed = registry.deploy_version('YourSignature', 'v20240101_120000')

# Automatic rollback on performance degradation
registry.monitor_and_rollback('YourSignature', current_performance_score)
```

## Event Types and Payloads

### Optimization Events

```ruby
# dspy.optimization.start
{
  optimization_id: 'uuid',
  optimizer: 'MIPROv2',
  trainset_size: 100,
  valset_size: 20,
  config: { ... }
}

# dspy.optimization.complete  
{
  optimization_id: 'uuid',
  duration_ms: 30000.0,
  best_score: 0.85,
  trials_count: 50,
  final_instruction: 'Optimized instruction'
}

# dspy.optimization.trial_complete
{
  optimization_id: 'uuid',
  trial_number: 15,
  score: 0.78,
  duration_ms: 1200.0,
  instruction: 'Trial instruction'
}
```

### LM Events

```ruby
# dspy.lm.request
{
  provider: 'openai',
  model: 'gpt-4',
  status: 'success',
  duration_ms: 850.0,
  tokens_total: 150,
  tokens_input: 100,
  tokens_output: 50,
  cost: 0.0075
}

# dspy.predict
{
  signature_class: 'QuestionAnswering',
  status: 'success', 
  duration_ms: 200.0,
  input_size: 45
}
```

### Storage Events

```ruby
# dspy.storage.save_complete
{
  program_id: 'uuid',
  size_bytes: 2048,
  duration_ms: 15.0,
  tags: ['miprov2', 'optimized']
}

# dspy.registry.deploy_complete
{
  signature_name: 'QuestionAnswering',
  version: 'v20240101_120000',
  performance_score: 0.85
}
```

## Metrics and Dashboards

### OpenTelemetry Metrics

- `dspy.optimization.started` - Counter of optimizations started
- `dspy.optimization.duration` - Histogram of optimization duration
- `dspy.optimization.score` - Histogram of optimization scores
- `dspy.lm.request.duration` - Histogram of LM request duration
- `dspy.lm.tokens.total` - Histogram of token usage
- `dspy.lm.cost` - Histogram of LM request costs

### New Relic Metrics

- `Custom/DSPy/Optimization/Duration` - Optimization duration
- `Custom/DSPy/Optimization/BestScore` - Best scores achieved
- `Custom/DSPy/LM/Requests` - LM request count
- `Custom/DSPy/LM/Tokens/Total` - Token usage
- `Custom/DSPy/LM/Cost` - LM costs
- `Custom/DSPy/Trial/Score` - Individual trial scores

### Langfuse Traces

- **Optimization Traces**: Complete optimization runs with trials
- **LM Generation Traces**: Individual LM requests with prompts/completions
- **Evaluation Traces**: Evaluation runs with scores
- **Deployment Events**: Version deployments and rollbacks

## Configuration

### Environment Variables

```bash
# OpenTelemetry
OTEL_SERVICE_NAME=my-dspy-app
OTEL_SERVICE_VERSION=1.0.0
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_HEADERS=api-key=your-key
OTEL_TRACE_SAMPLE_RATE=1.0

# Langfuse
LANGFUSE_PUBLIC_KEY=pk_your_key
LANGFUSE_SECRET_KEY=sk_your_key
LANGFUSE_HOST=https://cloud.langfuse.com

# New Relic (via newrelic.yml)
# Standard New Relic configuration
```

### Programmatic Configuration

```ruby
# Configure subscribers programmatically
otel_config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
otel_config.enabled = true
otel_config.trace_optimization_events = true
otel_config.export_metrics = true

newrelic_config = DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig.new  
newrelic_config.record_custom_metrics = true
newrelic_config.metric_prefix = 'Custom/MyApp/DSPy'

langfuse_config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
langfuse_config.log_prompts = true
langfuse_config.log_completions = true
langfuse_config.calculate_costs = true
```

## Best Practices

### Performance Monitoring

1. **Set up dashboards** for key metrics:
   - Optimization success rates
   - Average optimization time  
   - LM request latency and costs
   - Token usage trends

2. **Configure alerts** for:
   - Optimization failures
   - High LM costs
   - Performance regressions
   - Long-running optimizations

3. **Track business metrics**:
   - Model accuracy improvements
   - Cost per optimization
   - Time to deploy new versions

### Security and Privacy

1. **Control prompt logging**:
   ```ruby
   langfuse_config.log_prompts = false  # Disable for sensitive data
   ```

2. **Filter sensitive data** in custom events:
   ```ruby
   DSPy::Instrumentation.emit('custom.event', {
     user_id: user.id,  # OK
     # password: user.password  # Never log sensitive data
   })
   ```

3. **Use sampling** for high-volume applications:
   ```bash
   export OTEL_TRACE_SAMPLE_RATE=0.1  # Sample 10% of traces
   ```

### Cost Optimization

1. **Monitor token usage** and implement limits
2. **Use sampling** to reduce observability costs
3. **Set up cost alerts** for LM usage
4. **Archive old optimization results** to save storage

## Troubleshooting

### Common Issues

1. **Missing traces**: Check if dependencies are installed and environment variables are set
2. **High costs**: Reduce sampling rate or disable prompt logging
3. **Performance impact**: Disable non-essential subscribers in production
4. **Storage issues**: Configure cleanup policies for old results

### Debug Mode

Enable verbose logging to troubleshoot:

```ruby
DSPy.configure do |config|
  config.logger.level = Logger::DEBUG
end

# Force subscriber initialization for debugging
DSPy::Instrumentation.setup_subscribers
```

## Integration Examples

### Complete Monitoring Setup

```ruby
# Gemfile
gem 'opentelemetry-api'
gem 'opentelemetry-sdk' 
gem 'opentelemetry-exporter-otlp'
gem 'newrelic_rpm'
gem 'langfuse'

# config/application.rb
DSPy.configure do |config|
  config.logger.level = Logger::INFO
end

# Initialize all subscribers
DSPy::Instrumentation.setup_subscribers

# Your optimization code
optimizer = DSPy::MIPROv2.new(
  metric: your_metric,
  config: DSPy::Teleprompt::Teleprompter::Config.new.tap do |c|
    c.save_intermediate_results = true
  end
)

result = optimizer.compile(program, trainset: train, valset: val)

# All events automatically tracked across all systems:
# - Structured logs for debugging
# - OpenTelemetry spans for distributed tracing  
# - New Relic metrics for APM
# - Langfuse traces for LLM observability
# - Storage for result persistence
# - Registry for version management
```

This comprehensive observability setup provides complete visibility into your DSPy applications with minimal configuration required.