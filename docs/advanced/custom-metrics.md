# Custom Metrics

DSPy.rb provides a flexible metrics system that allows you to define domain-specific evaluation criteria, business metrics, and custom optimization targets.

## Basic Custom Metrics

### Simple Accuracy Metric

```ruby
class CustomAccuracy < DSPy::Metrics::Base
  def initialize(field_name = :prediction)
    @field_name = field_name
  end
  
  def evaluate(predictions, ground_truth)
    correct = 0
    
    predictions.zip(ground_truth).each do |pred, truth|
      correct += 1 if pred.send(@field_name) == truth[@field_name]
    end
    
    {
      accuracy: correct.to_f / predictions.size,
      correct_count: correct,
      total_count: predictions.size
    }
  end
  
  def name
    "accuracy_#{@field_name}"
  end
end

# Usage
accuracy_metric = CustomAccuracy.new(:sentiment)
result = accuracy_metric.evaluate(predictions, ground_truth)
puts "Accuracy: #{result[:accuracy]}"
```

### Weighted Metrics

```ruby
class WeightedAccuracy < DSPy::Metrics::Base
  def initialize(class_weights = {})
    @class_weights = class_weights
  end
  
  def evaluate(predictions, ground_truth)
    weighted_correct = 0.0
    total_weight = 0.0
    
    predictions.zip(ground_truth).each do |pred, truth|
      true_class = truth[:label]
      weight = @class_weights[true_class] || 1.0
      
      total_weight += weight
      
      if pred.label == true_class
        weighted_correct += weight
      end
    end
    
    {
      weighted_accuracy: weighted_correct / total_weight,
      total_weight: total_weight,
      class_weights: @class_weights
    }
  end
end

# Usage with class imbalance
weighted_metric = WeightedAccuracy.new({
  'positive' => 1.0,
  'negative' => 1.0,
  'neutral' => 2.0  # Weight neutral class higher due to rarity
})
```

## Business Metrics

### ROI-based Metric

```ruby
class BusinessROIMetric < DSPy::Metrics::Base
  def initialize(cost_per_prediction: 0.01, value_per_correct: 10.0, cost_per_error: 50.0)
    @cost_per_prediction = cost_per_prediction
    @value_per_correct = value_per_correct
    @cost_per_error = cost_per_error
  end
  
  def evaluate(predictions, ground_truth)
    total_predictions = predictions.size
    correct_predictions = 0
    errors = 0
    
    predictions.zip(ground_truth).each do |pred, truth|
      if pred.matches?(truth)
        correct_predictions += 1
      else
        errors += 1
      end
    end
    
    # Calculate costs and benefits
    prediction_costs = total_predictions * @cost_per_prediction
    error_costs = errors * @cost_per_error
    total_costs = prediction_costs + error_costs
    
    benefits = correct_predictions * @value_per_correct
    roi = (benefits - total_costs) / total_costs
    
    {
      roi: roi,
      total_benefits: benefits,
      total_costs: total_costs,
      net_value: benefits - total_costs,
      accuracy: correct_predictions.to_f / total_predictions,
      cost_breakdown: {
        prediction_costs: prediction_costs,
        error_costs: error_costs
      }
    }
  end
end
```

### Customer Satisfaction Metric

```ruby
class CustomerSatisfactionMetric < DSPy::Metrics::Base
  def initialize
    @satisfaction_predictor = DSPy::Predict.new(PredictSatisfaction)
  end
  
  def evaluate(predictions, ground_truth)
    satisfaction_scores = []
    resolution_times = []
    
    predictions.zip(ground_truth).each do |pred, truth|
      # Predict customer satisfaction based on response quality
      satisfaction = @satisfaction_predictor.call(
        customer_query: truth[:original_query],
        system_response: pred.response,
        expected_response: truth[:expected_response]
      )
      
      satisfaction_scores << satisfaction.score
      resolution_times << pred.processing_time
    end
    
    avg_satisfaction = satisfaction_scores.sum / satisfaction_scores.size
    avg_resolution_time = resolution_times.sum / resolution_times.size
    
    # Combine satisfaction and efficiency
    efficiency_score = [1.0, 30.0 / avg_resolution_time].min  # 30s target
    combined_score = (avg_satisfaction * 0.7) + (efficiency_score * 0.3)
    
    {
      customer_satisfaction: avg_satisfaction,
      average_resolution_time: avg_resolution_time,
      efficiency_score: efficiency_score,
      combined_score: combined_score,
      satisfaction_distribution: calculate_distribution(satisfaction_scores)
    }
  end
end

class PredictSatisfaction < DSPy::Signature
  description "Predict customer satisfaction based on query and response quality"
  
  input do
    const :customer_query, String
    const :system_response, String
    const :expected_response, String
  end
  
  output do
    const :score, Float  # 0.0 to 1.0
    const :reasoning, String
  end
end
```

## Domain-Specific Metrics

### Medical Accuracy Metric

```ruby
class MedicalDiagnosisMetric < DSPy::Metrics::Base
  def initialize
    @severity_weights = {
      'critical' => 10.0,
      'high' => 5.0,
      'medium' => 2.0,
      'low' => 1.0
    }
  end
  
  def evaluate(predictions, ground_truth)
    clinical_accuracy = 0.0
    safety_score = 0.0
    total_weight = 0.0
    
    predictions.zip(ground_truth).each do |pred, truth|
      severity = truth[:severity]
      weight = @severity_weights[severity]
      total_weight += weight
      
      # Clinical accuracy (exact match)
      if pred.diagnosis == truth[:diagnosis]
        clinical_accuracy += weight
      end
      
      # Safety score (considers severity of misdiagnosis)
      safety_penalty = calculate_safety_penalty(pred.diagnosis, truth[:diagnosis], severity)
      safety_score += weight * (1.0 - safety_penalty)
    end
    
    {
      clinical_accuracy: clinical_accuracy / total_weight,
      safety_score: safety_score / total_weight,
      total_cases: predictions.size,
      severity_breakdown: calculate_severity_breakdown(ground_truth)
    }
  end
  
  private
  
  def calculate_safety_penalty(predicted, actual, severity)
    # Higher penalty for missing critical conditions
    return 0.0 if predicted == actual
    
    case severity
    when 'critical'
      0.9  # Very high penalty
    when 'high'
      0.6
    when 'medium'
      0.3
    when 'low'
      0.1
    else
      0.2
    end
  end
end
```

### Financial Risk Metric

```ruby
class FinancialRiskMetric < DSPy::Metrics::Base
  def initialize(risk_tolerance: 0.05)
    @risk_tolerance = risk_tolerance
  end
  
  def evaluate(predictions, ground_truth)
    risk_scores = []
    financial_impact = 0.0
    false_positives = 0
    false_negatives = 0
    
    predictions.zip(ground_truth).each do |pred, truth|
      predicted_risk = pred.risk_level
      actual_risk = truth[:risk_level]
      transaction_value = truth[:transaction_value]
      
      # Calculate financial impact of prediction
      if predicted_risk == actual_risk
        # Correct prediction
        risk_scores << 1.0
      elsif predicted_risk > actual_risk
        # False positive (unnecessary blocking)
        false_positives += 1
        risk_scores << 0.8  # Minor penalty
        financial_impact -= transaction_value * 0.01  # Lost opportunity cost
      else
        # False negative (missed fraud)
        false_negatives += 1
        risk_scores << 0.0  # Major penalty
        financial_impact -= transaction_value * 0.1  # Higher fraud cost
      end
    end
    
    accuracy = risk_scores.sum / risk_scores.size
    total_transactions = predictions.size
    
    {
      risk_accuracy: accuracy,
      financial_impact: financial_impact,
      false_positive_rate: false_positives.to_f / total_transactions,
      false_negative_rate: false_negatives.to_f / total_transactions,
      risk_adjusted_score: calculate_risk_adjusted_score(accuracy, financial_impact),
      meets_risk_tolerance: accuracy >= (1.0 - @risk_tolerance)
    }
  end
end
```

## Multi-objective Metrics

### Composite Metric

```ruby
class CompositeMetric < DSPy::Metrics::Base
  def initialize(metrics_config)
    @metrics = metrics_config[:metrics]
    @weights = metrics_config[:weights]
    @aggregation_method = metrics_config[:aggregation] || :weighted_average
  end
  
  def evaluate(predictions, ground_truth)
    metric_results = {}
    
    # Evaluate each component metric
    @metrics.each do |name, metric|
      metric_results[name] = metric.evaluate(predictions, ground_truth)
    end
    
    # Aggregate results
    aggregated_score = aggregate_scores(metric_results)
    
    {
      composite_score: aggregated_score,
      component_scores: metric_results,
      weights: @weights,
      aggregation_method: @aggregation_method
    }
  end
  
  private
  
  def aggregate_scores(metric_results)
    case @aggregation_method
    when :weighted_average
      weighted_average(metric_results)
    when :harmonic_mean
      harmonic_mean(metric_results)
    when :geometric_mean
      geometric_mean(metric_results)
    when :min_score
      min_score(metric_results)
    else
      weighted_average(metric_results)
    end
  end
  
  def weighted_average(metric_results)
    total_score = 0.0
    total_weight = 0.0
    
    @metrics.each do |name, _|
      score = extract_primary_score(metric_results[name])
      weight = @weights[name] || 1.0
      
      total_score += score * weight
      total_weight += weight
    end
    
    total_score / total_weight
  end
end

# Usage
composite = CompositeMetric.new({
  metrics: {
    accuracy: CustomAccuracy.new,
    business_roi: BusinessROIMetric.new,
    response_time: ResponseTimeMetric.new
  },
  weights: {
    accuracy: 0.5,
    business_roi: 0.3,
    response_time: 0.2
  },
  aggregation: :weighted_average
})
```

### Pareto Optimization Metric

```ruby
class ParetoMetric < DSPy::Metrics::Base
  def initialize(objectives)
    @objectives = objectives  # Array of metrics to optimize
  end
  
  def evaluate(predictions, ground_truth)
    objective_scores = {}
    
    # Evaluate each objective
    @objectives.each do |objective|
      objective_scores[objective.name] = objective.evaluate(predictions, ground_truth)
    end
    
    # Calculate Pareto efficiency
    pareto_rank = calculate_pareto_rank(objective_scores)
    
    {
      pareto_rank: pareto_rank,
      objective_scores: objective_scores,
      is_pareto_optimal: pareto_rank == 1,
      dominated_solutions: count_dominated_solutions(objective_scores)
    }
  end
  
  private
  
  def calculate_pareto_rank(scores)
    # Implementation of Pareto ranking algorithm
    # Returns 1 for Pareto optimal solutions, higher numbers for dominated solutions
    
    reference_points = generate_reference_points
    
    dominance_count = 0
    reference_points.each do |ref_point|
      if dominates?(ref_point, scores)
        dominance_count += 1
      end
    end
    
    dominance_count + 1
  end
end
```

## Real-time Metrics

### Streaming Metric

```ruby
class StreamingMetric < DSPy::Metrics::Base
  def initialize(window_size: 100)
    @window_size = window_size
    @prediction_buffer = []
    @ground_truth_buffer = []
    @current_metrics = {}
  end
  
  def update(prediction, ground_truth)
    # Add to buffers
    @prediction_buffer << prediction
    @ground_truth_buffer << ground_truth
    
    # Maintain window size
    if @prediction_buffer.size > @window_size
      @prediction_buffer.shift
      @ground_truth_buffer.shift
    end
    
    # Update metrics
    if @prediction_buffer.size >= 10  # Minimum samples
      @current_metrics = evaluate(@prediction_buffer, @ground_truth_buffer)
    end
    
    @current_metrics
  end
  
  def current_score
    @current_metrics[:primary_score] || 0.0
  end
  
  def reset
    @prediction_buffer.clear
    @ground_truth_buffer.clear
    @current_metrics.clear
  end
end

# Usage in real-time system
streaming_metric = StreamingMetric.new(window_size: 50)

# In your prediction loop
result = predictor.call(input)
actual_outcome = get_ground_truth(input)  # When available

current_performance = streaming_metric.update(result, actual_outcome)
puts "Current accuracy: #{current_performance[:accuracy]}"
```

### Adaptive Threshold Metric

```ruby
class AdaptiveThresholdMetric < DSPy::Metrics::Base
  def initialize(target_precision: 0.95, adaptation_rate: 0.1)
    @target_precision = target_precision
    @adaptation_rate = adaptation_rate
    @current_threshold = 0.5
    @performance_history = []
  end
  
  def evaluate(predictions, ground_truth)
    # Evaluate at current threshold
    results = evaluate_at_threshold(predictions, ground_truth, @current_threshold)
    
    # Track performance
    @performance_history << {
      threshold: @current_threshold,
      precision: results[:precision],
      recall: results[:recall],
      timestamp: Time.current
    }
    
    # Adapt threshold based on precision target
    adapt_threshold(results[:precision])
    
    results.merge({
      current_threshold: @current_threshold,
      threshold_history: @performance_history.last(10),
      target_precision: @target_precision
    })
  end
  
  private
  
  def adapt_threshold(current_precision)
    if current_precision < @target_precision
      # Increase threshold to improve precision
      @current_threshold += @adaptation_rate * (@target_precision - current_precision)
    elsif current_precision > @target_precision + 0.05
      # Decrease threshold to improve recall
      @current_threshold -= @adaptation_rate * (current_precision - @target_precision)
    end
    
    # Keep threshold in valid range
    @current_threshold = [@current_threshold, 0.0].max
    @current_threshold = [@current_threshold, 1.0].min
  end
end
```

## Integration with Optimization

### Optimization-Aware Metrics

```ruby
class OptimizationAwareMetric < DSPy::Metrics::Base
  def initialize(base_metric, optimization_context: {})
    @base_metric = base_metric
    @optimization_context = optimization_context
    @evaluation_history = []
  end
  
  def evaluate(predictions, ground_truth)
    # Standard evaluation
    base_results = @base_metric.evaluate(predictions, ground_truth)
    
    # Add optimization-specific insights
    optimization_insights = analyze_for_optimization(predictions, ground_truth)
    
    # Track evaluation history for trends
    @evaluation_history << {
      results: base_results,
      insights: optimization_insights,
      timestamp: Time.current
    }
    
    # Calculate optimization guidance
    guidance = generate_optimization_guidance
    
    base_results.merge({
      optimization_insights: optimization_insights,
      optimization_guidance: guidance,
      trend_analysis: analyze_trends
    })
  end
  
  private
  
  def analyze_for_optimization(predictions, ground_truth)
    {
      error_patterns: identify_error_patterns(predictions, ground_truth),
      confidence_calibration: analyze_confidence_calibration(predictions, ground_truth),
      difficulty_analysis: analyze_prediction_difficulty(predictions, ground_truth),
      improvement_opportunities: identify_improvement_opportunities(predictions, ground_truth)
    }
  end
  
  def generate_optimization_guidance
    return {} if @evaluation_history.size < 3
    
    recent_performance = @evaluation_history.last(3)
    
    {
      performance_trend: calculate_trend(recent_performance),
      suggested_adjustments: suggest_parameter_adjustments(recent_performance),
      optimization_priority: determine_optimization_priority(recent_performance)
    }
  end
end
```

## Testing Custom Metrics

### Metric Validation Tests

```ruby
RSpec.describe CustomAccuracy do
  let(:metric) { described_class.new(:label) }
  
  describe "#evaluate" do
    it "calculates accuracy correctly" do
      predictions = [
        OpenStruct.new(label: 'positive'),
        OpenStruct.new(label: 'negative'),
        OpenStruct.new(label: 'neutral'),
        OpenStruct.new(label: 'positive')
      ]
      
      ground_truth = [
        { label: 'positive' },
        { label: 'negative' },
        { label: 'positive' },  # Incorrect
        { label: 'positive' }
      ]
      
      result = metric.evaluate(predictions, ground_truth)
      
      expect(result[:accuracy]).to eq(0.75)  # 3 out of 4 correct
      expect(result[:correct_count]).to eq(3)
      expect(result[:total_count]).to eq(4)
    end
    
    it "handles edge cases" do
      # Empty predictions
      result = metric.evaluate([], [])
      expect(result[:accuracy]).to be_nan
      
      # Perfect accuracy
      perfect_predictions = [OpenStruct.new(label: 'positive')]
      perfect_ground_truth = [{ label: 'positive' }]
      result = metric.evaluate(perfect_predictions, perfect_ground_truth)
      expect(result[:accuracy]).to eq(1.0)
    end
  end
end
```

### Performance Testing

```ruby
RSpec.describe "Metric Performance" do
  let(:metric) { BusinessROIMetric.new }
  
  it "handles large datasets efficiently" do
    large_predictions = Array.new(10000) { generate_prediction }
    large_ground_truth = Array.new(10000) { generate_ground_truth }
    
    execution_time = Benchmark.realtime do
      metric.evaluate(large_predictions, large_ground_truth)
    end
    
    expect(execution_time).to be < 1.0  # Should complete within 1 second
  end
end
```

Custom metrics enable you to align DSPy optimization with your specific business objectives and domain requirements. Use these patterns to create metrics that truly measure what matters for your application's success.