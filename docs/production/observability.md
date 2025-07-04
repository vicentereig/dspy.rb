# Observability

DSPy.rb provides comprehensive observability capabilities for production environments, including distributed tracing, metrics collection, logging, and integration with popular monitoring platforms.

## Overview

The observability system offers:
- **Distributed Tracing**: Track requests across DSPy modules and external services
- **Metrics Collection**: Performance, accuracy, and business metrics
- **Structured Logging**: Detailed operation logs with context
- **Multi-Platform Integration**: OpenTelemetry, New Relic, Langfuse support
- **Custom Instrumentation**: Add domain-specific observability
- **Real-time Monitoring**: Live dashboards and alerting

## Basic Configuration

### Enable Instrumentation

```ruby
DSPy.configure do |config|
  # Enable instrumentation
  config.instrumentation.enabled = true
  
  # Configure subscribers
  config.instrumentation.subscribers = [
    :logger,      # Structured logging
    :otel,        # OpenTelemetry tracing
    :newrelic,    # New Relic APM
    :langfuse     # LLM-specific observability
  ]
  
  # Sampling configuration
  config.instrumentation.sampling_rate = 1.0  # 100% in development
  config.instrumentation.trace_level = :detailed
  
  # Timestamp format for OpenTelemetry compliance
  config.instrumentation.timestamp_format = DSPy::TimestampFormat::ISO8601
end
```

### Production Configuration

```ruby
DSPy.configure do |config|
  config.instrumentation.enabled = true
  
  # Production subscribers
  config.instrumentation.subscribers = [:otel, :newrelic, :custom_metrics]
  
  # Sampling for performance
  config.instrumentation.sampling_rate = 0.1  # 10% sampling in production
  config.instrumentation.trace_level = :standard
  
  # Performance settings
  config.instrumentation.async_processing = true
  config.instrumentation.buffer_size = 1000
  config.instrumentation.flush_interval = 30.seconds
  
  # Error handling
  config.instrumentation.error_reporting = true
  config.instrumentation.error_service = :sentry
  
  # Timestamp format for production monitoring
  config.instrumentation.timestamp_format = DSPy::TimestampFormat::UNIX_NANO
end
```

## Event Consolidation

DSPy.rb provides configurable event consolidation to reduce instrumentation noise while maintaining observability. Three trace levels are available:

### Trace Levels

#### `:minimal` - Minimal Event Emission
Only emits top-level events for high-level operations like ChainOfThought and ReAct. Ideal for production environments where noise reduction is critical.

```ruby
DSPy.configure do |config|
  config.instrumentation.trace_level = :minimal
end

# For a ChainOfThought operation, only emits:
# - dspy.chain_of_thought
```

#### `:standard` - Consolidated Events (Default)
Emits consolidated events by skipping nested instrumentation when higher-level events are already being emitted. Provides good balance between observability and noise reduction.

```ruby
DSPy.configure do |config|
  config.instrumentation.trace_level = :standard  # Default
end

# For a ChainOfThought operation, emits:
# - dspy.chain_of_thought (includes LM details in payload)
# 
# For a direct Predict call, emits:
# - dspy.predict
# - dspy.lm.request
# - dspy.lm.tokens
```

#### `:detailed` - Full Event Emission
Emits all instrumentation events including nested ones. Useful for debugging and development.

```ruby
DSPy.configure do |config|
  config.instrumentation.trace_level = :detailed
end

# For a ChainOfThought operation, emits all events:
# - dspy.chain_of_thought
# - dspy.predict
# - dspy.lm.request
# - dspy.lm.tokens
# - dspy.lm.response.parsed
```

### Token Reporting Standardization

All providers now report tokens using standardized field names for consistency:

```ruby
# Standardized token event payload
{
  "event": "dspy.lm.tokens",
  "input_tokens": 123,
  "output_tokens": 456,
  "total_tokens": 579,
  "provider": "openai",
  "model": "gpt-4o-mini"
}
```

### Timestamp Formats

Configure timestamp formats for different monitoring platforms:

```ruby
# ISO8601 format (default)
config.instrumentation.timestamp_format = DSPy::TimestampFormat::ISO8601
# Output: "2025-07-04T15:22:33Z"

# RFC3339 with nanosecond precision
config.instrumentation.timestamp_format = DSPy::TimestampFormat::RFC3339_NANO
# Output: "2025-07-04T15:22:33.123456789+0000"

# Unix nanoseconds for high-precision monitoring
config.instrumentation.timestamp_format = DSPy::TimestampFormat::UNIX_NANO
# Output: timestamp_ns: 1720104153123456789
```

## Distributed Tracing

### Automatic Instrumentation

DSPy automatically instruments all core operations:

```ruby
# This code is automatically instrumented
classifier = DSPy::Predict.new(ClassifyText)
result = classifier.call(text: "Sample text")

# Generated trace includes:
# - dspy.predict.call
#   - dspy.lm.request
#   - dspy.validation.check
#   - dspy.result.format
```

### Manual Instrumentation

```ruby
class CustomProcessor < DSPy::Module
  def call(input)
    DSPy.tracer.in_span('custom_processor.call') do |span|
      # Add custom attributes
      span.set_attribute('input.length', input.length)
      span.set_attribute('processor.version', '2.1.0')
      
      # Process with nested spans
      validated_input = DSPy.tracer.in_span('validation') do
        validate_input(input)
      end
      
      result = DSPy.tracer.in_span('core_processing') do |core_span|
        core_span.set_attribute('complexity', assess_complexity(validated_input))
        process_core_logic(validated_input)
      end
      
      # Record custom metrics
      span.add_event('processing_completed', {
        'result.confidence' => result.confidence,
        'processing.duration' => Time.current - span.start_time
      })
      
      result
    end
  end
end
```

### Correlation IDs

```ruby
# Automatic correlation ID generation
DSPy.configure do |config|
  config.instrumentation.correlation_id.enabled = true
  config.instrumentation.correlation_id.header = 'X-Correlation-ID'
  config.instrumentation.correlation_id.generator = -> { SecureRandom.uuid }
end

# Manual correlation ID
DSPy.with_correlation_id('user-request-12345') do
  result = classifier.call(text: "User feedback text")
  # All nested operations will include this correlation ID
end
```

## Metrics Collection

### Built-in Metrics

DSPy automatically collects performance and accuracy metrics:

```ruby
# Performance metrics
- dspy.prediction.duration
- dspy.prediction.token_usage
- dspy.prediction.cost
- dspy.lm.request.duration
- dspy.lm.request.input_tokens
- dspy.lm.request.output_tokens
- dspy.lm.request.total_tokens

# Accuracy metrics (when ground truth available)
- dspy.prediction.accuracy
- dspy.prediction.confidence_accuracy_correlation
- dspy.signature.field_accuracy

# Error metrics
- dspy.prediction.errors_total
- dspy.lm.errors_total
- dspy.validation.errors_total
```

### Custom Metrics

```ruby
class BusinessMetricsCollector
  include DSPy::Instrumentation::Metrics
  
  def initialize
    # Define custom metrics
    @user_satisfaction = histogram(
      'dspy.business.user_satisfaction',
      description: 'User satisfaction scores',
      buckets: [1, 2, 3, 4, 5]
    )
    
    @prediction_confidence = histogram(
      'dspy.prediction.confidence_distribution',
      description: 'Distribution of prediction confidence scores',
      buckets: [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    )
    
    @business_impact = counter(
      'dspy.business.decisions_automated',
      description: 'Number of business decisions automated by DSPy'
    )
  end
  
  def record_prediction_result(result, context = {})
    # Record confidence distribution
    @prediction_confidence.record(result.confidence)
    
    # Record business impact
    if context[:automated_decision]
      @business_impact.increment(
        tags: {
          decision_type: context[:decision_type],
          confidence_level: confidence_bucket(result.confidence)
        }
      )
    end
    
    # Record user satisfaction if available
    if context[:user_feedback]
      @user_satisfaction.record(
        context[:user_feedback][:satisfaction_score],
        tags: {
          prediction_category: result.category,
          confidence_level: confidence_bucket(result.confidence)
        }
      )
    end
  end
  
  private
  
  def confidence_bucket(confidence)
    case confidence
    when 0.0...0.3 then 'low'
    when 0.3...0.7 then 'medium'
    else 'high'
    end
  end
end

# Usage
metrics_collector = BusinessMetricsCollector.new

# In your application
result = classifier.call(text: "Customer feedback")
metrics_collector.record_prediction_result(
  result,
  context: {
    automated_decision: true,
    decision_type: 'customer_routing',
    user_feedback: { satisfaction_score: 4 }
  }
)
```

## Platform Integrations

### OpenTelemetry

```ruby
# OpenTelemetry configuration
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'dspy-application'
  c.service_version = '1.0.0'
  
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
      )
    )
  )
end

# DSPy will automatically use the configured tracer
DSPy.configure do |config|
  config.instrumentation.subscribers = [:otel]
  config.instrumentation.otel.tracer_name = 'dspy-ruby'
end
```

### New Relic

```ruby
# New Relic configuration
DSPy.configure do |config|
  config.instrumentation.subscribers = [:newrelic]
  
  config.instrumentation.newrelic.app_name = 'DSPy Application'
  config.instrumentation.newrelic.license_key = ENV['NEW_RELIC_LICENSE_KEY']
  
  # Custom attributes
  config.instrumentation.newrelic.custom_attributes = {
    'dspy.version' => DSPy::VERSION,
    'deployment.environment' => Rails.env
  }
end

# Custom New Relic events
class NewRelicDSPySubscriber < DSPy::Subscribers::NewRelicSubscriber
  def prediction_completed(event)
    super
    
    # Record custom New Relic event
    NewRelic::Agent.record_custom_event('DSPyPrediction', {
      signature: event.payload[:signature],
      confidence: event.payload[:result][:confidence],
      processing_time: event.payload[:duration],
      success: event.payload[:success]
    })
    
    # Add custom attributes to transaction
    NewRelic::Agent.add_custom_attributes({
      'dspy.prediction.confidence' => event.payload[:result][:confidence],
      'dspy.signature.name' => event.payload[:signature]
    })
  end
end
```

### Langfuse (LLM Observability)

```ruby
# Langfuse configuration for LLM-specific observability
DSPy.configure do |config|
  config.instrumentation.subscribers = [:langfuse]
  
  config.instrumentation.langfuse.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.instrumentation.langfuse.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.instrumentation.langfuse.host = ENV['LANGFUSE_HOST']
  
  # LLM-specific tracking
  config.instrumentation.langfuse.track_tokens = true
  config.instrumentation.langfuse.track_costs = true
  config.instrumentation.langfuse.track_prompts = true
end

# Custom Langfuse traces
class LangfuseDSPySubscriber < DSPy::Subscribers::LangfuseSubscriber
  def lm_request_started(event)
    super
    
    # Create Langfuse generation
    @current_generation = @langfuse.generation(
      name: "dspy_#{event.payload[:signature]}_prediction",
      input: event.payload[:prompt],
      model: event.payload[:model],
      start_time: event.payload[:start_time]
    )
  end
  
  def lm_request_completed(event)
    super
    
    # Update Langfuse generation
    @current_generation.end(
      output: event.payload[:response],
      end_time: event.payload[:end_time],
      usage: {
        input_tokens: event.payload[:input_tokens],
        output_tokens: event.payload[:output_tokens],
        total_tokens: event.payload[:total_tokens]
      },
      level: event.payload[:success] ? 'INFO' : 'ERROR'
    )
  end
end
```

## Logging

### Structured Logging

```ruby
# Configure structured logging
DSPy.configure do |config|
  config.logger = ActiveSupport::Logger.new(STDOUT)
  config.logger.formatter = DSPy::Logging::StructuredFormatter.new
  
  config.instrumentation.logger.level = :info
  config.instrumentation.logger.include_payloads = true
  config.instrumentation.logger.correlation_id = true
end

# Example log output
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "level": "INFO",
  "event": "dspy.prediction.completed",
  "correlation_id": "req-12345",
  "signature": "ClassifyText",
  "duration_ms": 245,
  "success": true,
  "result": {
    "confidence": 0.92,
    "category": "positive"
  },
  "metadata": {
    "model": "gpt-4o-mini",
    "tokens_used": 45,
    "cost": 0.001
  }
}
```

### Log Sampling

```ruby
# Configure log sampling for high-volume applications
DSPy.configure do |config|
  config.instrumentation.logger.sampling = {
    prediction_events: 0.1,     # Sample 10% of predictions
    lm_request_events: 0.05,    # Sample 5% of LM requests
    error_events: 1.0,          # Log all errors
    slow_requests: 1.0          # Log all slow requests (>2s)
  }
  
  # Conditional sampling
  config.instrumentation.logger.sampling_conditions = {
    low_confidence: ->(event) { 
      event.payload.dig(:result, :confidence) < 0.7 
    },
    high_value_users: ->(event) {
      event.payload.dig(:context, :user_tier) == 'premium'
    }
  }
end
```

## Real-time Monitoring

### Dashboards

```ruby
class DSPyDashboard
  def initialize(metrics_store)
    @metrics = metrics_store
  end
  
  def generate_dashboard_data(time_range: 1.hour)
    {
      overview: {
        total_predictions: @metrics.count('dspy.prediction.total', time_range),
        average_accuracy: @metrics.average('dspy.prediction.accuracy', time_range),
        average_latency: @metrics.average('dspy.prediction.duration', time_range),
        error_rate: @metrics.rate('dspy.prediction.errors', time_range)
      },
      
      performance_trends: {
        accuracy_trend: @metrics.trend('dspy.prediction.accuracy', time_range, interval: 5.minutes),
        latency_trend: @metrics.trend('dspy.prediction.duration', time_range, interval: 5.minutes),
        throughput_trend: @metrics.trend('dspy.prediction.rate', time_range, interval: 5.minutes)
      },
      
      signature_breakdown: @metrics.group_by('dspy.prediction.accuracy', 'signature', time_range),
      
      model_usage: @metrics.group_by('dspy.lm.request.total', 'model', time_range),
      
      cost_analysis: {
        total_cost: @metrics.sum('dspy.prediction.cost', time_range),
        cost_by_model: @metrics.group_by('dspy.prediction.cost', 'model', time_range),
        cost_trend: @metrics.trend('dspy.prediction.cost', time_range, interval: 1.hour)
      }
    }
  end
end
```

### Alerting

```ruby
class DSPyAlerting
  def initialize(metrics_store, notification_service)
    @metrics = metrics_store
    @notifications = notification_service
    @alert_rules = []
  end
  
  def add_alert_rule(name, condition, notification_config)
    @alert_rules << {
      name: name,
      condition: condition,
      notification: notification_config,
      last_triggered: nil,
      cooldown: notification_config[:cooldown] || 10.minutes
    }
  end
  
  def check_alerts
    @alert_rules.each do |rule|
      next if in_cooldown?(rule)
      
      if rule[:condition].call(@metrics)
        trigger_alert(rule)
        rule[:last_triggered] = Time.current
      end
    end
  end
  
  def setup_default_alerts
    # High error rate alert
    add_alert_rule(
      'high_error_rate',
      ->(metrics) { 
        metrics.rate('dspy.prediction.errors', 5.minutes) > 0.05 
      },
      {
        channels: [:slack, :pagerduty],
        severity: :high,
        cooldown: 15.minutes
      }
    )
    
    # Low accuracy alert
    add_alert_rule(
      'accuracy_degradation',
      ->(metrics) {
        current = metrics.average('dspy.prediction.accuracy', 10.minutes)
        baseline = metrics.average('dspy.prediction.accuracy', 24.hours)
        current < baseline * 0.9  # 10% degradation
      },
      {
        channels: [:slack, :email],
        severity: :medium,
        cooldown: 30.minutes
      }
    )
    
    # High latency alert
    add_alert_rule(
      'high_latency',
      ->(metrics) {
        metrics.percentile('dspy.prediction.duration', 95, 5.minutes) > 2000  # 2 seconds
      },
      {
        channels: [:slack],
        severity: :medium,
        cooldown: 10.minutes
      }
    )
  end
  
  private
  
  def trigger_alert(rule)
    alert_data = {
      rule_name: rule[:name],
      severity: rule[:notification][:severity],
      triggered_at: Time.current,
      metrics_snapshot: capture_metrics_snapshot
    }
    
    rule[:notification][:channels].each do |channel|
      @notifications.send_alert(channel, alert_data)
    end
  end
end
```

## Performance Monitoring

### Custom Performance Tracking

```ruby
class PerformanceTracker
  def initialize
    @performance_data = {}
    @benchmarks = {}
  end
  
  def track_operation(operation_name, &block)
    start_time = Time.current
    start_memory = memory_usage
    
    result = yield
    
    end_time = Time.current
    end_memory = memory_usage
    
    record_performance(operation_name, {
      duration: end_time - start_time,
      memory_delta: end_memory - start_memory,
      timestamp: start_time,
      success: !result.nil?
    })
    
    result
  rescue StandardError => e
    record_performance(operation_name, {
      duration: Time.current - start_time,
      memory_delta: memory_usage - start_memory,
      timestamp: start_time,
      success: false,
      error: e.class.name
    })
    
    raise
  end
  
  def benchmark_against_baseline(operation_name, baseline_percentile: 95)
    recent_performance = @performance_data[operation_name]&.last(100) || []
    return nil if recent_performance.empty?
    
    baseline = @benchmarks[operation_name]
    return nil unless baseline
    
    current_p95 = percentile(recent_performance.map { |p| p[:duration] }, baseline_percentile)
    baseline_p95 = baseline[:p95_duration]
    
    {
      current_p95: current_p95,
      baseline_p95: baseline_p95,
      performance_ratio: current_p95 / baseline_p95,
      regression: current_p95 > baseline_p95 * 1.2  # 20% regression threshold
    }
  end
  
  def establish_baseline(operation_name, sample_size: 100)
    recent_data = @performance_data[operation_name]&.last(sample_size) || []
    return false if recent_data.size < sample_size
    
    durations = recent_data.map { |p| p[:duration] }
    
    @benchmarks[operation_name] = {
      established_at: Time.current,
      sample_size: sample_size,
      mean_duration: durations.sum / durations.size,
      p50_duration: percentile(durations, 50),
      p95_duration: percentile(durations, 95),
      p99_duration: percentile(durations, 99)
    }
    
    true
  end
end
```

## Configuration Management

### Environment-Specific Observability

```ruby
# Development configuration
if Rails.env.development?
  DSPy.configure do |config|
    config.instrumentation.enabled = true
    config.instrumentation.subscribers = [:logger]
    config.instrumentation.logger.level = :debug
    config.instrumentation.trace_level = :detailed
    config.instrumentation.sampling_rate = 1.0
  end
end

# Staging configuration
if Rails.env.staging?
  DSPy.configure do |config|
    config.instrumentation.enabled = true
    config.instrumentation.subscribers = [:logger, :otel]
    config.instrumentation.logger.level = :info
    config.instrumentation.trace_level = :standard
    config.instrumentation.sampling_rate = 0.5
  end
end

# Production configuration
if Rails.env.production?
  DSPy.configure do |config|
    config.instrumentation.enabled = true
    config.instrumentation.subscribers = [:otel, :newrelic, :langfuse]
    config.instrumentation.logger.level = :warn
    config.instrumentation.trace_level = :standard
    config.instrumentation.sampling_rate = 0.1
    config.instrumentation.async_processing = true
    config.instrumentation.error_reporting = true
  end
end
```

## Best Practices

### 1. Sampling Strategy

```ruby
# Use intelligent sampling
DSPy.configure do |config|
  config.instrumentation.sampling_strategy = :intelligent
  config.instrumentation.sampling_rules = {
    # Always sample errors
    error_events: 1.0,
    
    # Always sample slow requests
    slow_requests: { threshold: 2.seconds, rate: 1.0 },
    
    # Sample based on confidence
    low_confidence: { 
      condition: ->(event) { event.payload.dig(:result, :confidence) < 0.7 },
      rate: 0.5
    },
    
    # Sample high-value operations more
    important_signatures: {
      condition: ->(event) { ['CriticalClassifier', 'SecurityCheck'].include?(event.payload[:signature]) },
      rate: 0.3
    },
    
    # Default sampling
    default: 0.1
  }
end
```

### 2. Context Preservation

```ruby
# Preserve context across async operations
class AsyncProcessor
  def process_batch(items)
    current_context = DSPy.current_trace_context
    
    items.map do |item|
      Async do
        DSPy.with_trace_context(current_context) do
          process_item(item)
        end
      end
    end.map(&:wait)
  end
end
```

### 3. Custom Metrics for Business Value

```ruby
# Track business outcomes, not just technical metrics
class BusinessOutcomeTracker
  def track_automation_success(prediction, actual_outcome)
    # Track prediction accuracy
    accuracy = prediction.matches?(actual_outcome) ? 1.0 : 0.0
    
    DSPy.metrics.histogram('business.automation.accuracy').record(accuracy)
    
    # Track business impact
    if prediction.automated_decision?
      DSPy.metrics.counter('business.decisions.automated').increment
      
      if accuracy == 1.0
        DSPy.metrics.counter('business.decisions.successful').increment
      end
    end
    
    # Track cost savings
    if prediction.replaced_human_decision?
      estimated_savings = calculate_cost_savings(prediction)
      DSPy.metrics.histogram('business.cost_savings').record(estimated_savings)
    end
  end
end
```

### 4. Proactive Monitoring

```ruby
# Set up proactive health checks
class DSPyHealthChecker
  def run_health_checks
    checks = [
      check_model_availability,
      check_prediction_accuracy,
      check_response_times,
      check_error_rates
    ]
    
    overall_health = checks.all? { |check| check[:healthy] }
    
    DSPy.metrics.gauge('dspy.health.overall').set(overall_health ? 1 : 0)
    
    checks.each do |check|
      DSPy.metrics.gauge("dspy.health.#{check[:name]}").set(check[:healthy] ? 1 : 0)
    end
    
    overall_health
  end
end
```

Comprehensive observability is essential for production DSPy applications. Use these tools and patterns to maintain visibility into your system's performance, accuracy, and business impact.