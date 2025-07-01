# Registry & Versions

The DSPy.rb registry system provides centralized management of signatures, predictors, and their versions. It enables controlled deployment, rollback capabilities, and collaboration across teams working with DSPy programs.

## Overview

The registry system provides:
- **Signature Management**: Register and version signature definitions
- **Program Registry**: Manage optimized predictors and their deployments
- **Version Control**: Track versions with semantic versioning
- **Deployment Tracking**: Monitor which versions are deployed where
- **Automated Rollback**: Automatically revert to previous versions on performance degradation
- **Collaboration**: Share optimized programs across teams

## Basic Usage

### Registering Signatures

```ruby
class ClassifyText < DSPy::Signature
  description "Classify text sentiment with confidence scoring"
  
  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

# Register the signature
registry = DSPy::Registry::SignatureRegistry.new
registry.register(
  name: 'text_classifier',
  signature: ClassifyText,
  version: '1.0.0',
  metadata: {
    description: 'Production sentiment classifier',
    team: 'ml_platform',
    domain: 'customer_feedback'
  }
)
```

### Registering Optimized Programs

```ruby
# After optimization
optimizer = DSPy::MIPROv2.new(signature: ClassifyText)
result = optimizer.optimize(examples: training_examples)

# Register the optimized program
program_registry = DSPy::Registry::ProgramRegistry.new
program_registry.register(
  name: 'sentiment_classifier_v2',
  program: result.best_predictor,
  signature_name: 'text_classifier',
  version: '2.1.0',
  metadata: {
    optimization_method: :miprov2,
    training_examples: training_examples.size,
    performance: {
      accuracy: result.best_score,
      validation_score: 0.91,
      test_score: 0.89
    },
    deployment_target: 'production'
  }
)
```

### Loading Programs from Registry

```ruby
# Load latest version
classifier = DSPy::Registry.load_program('sentiment_classifier_v2')
result = classifier.call(text: "This product is amazing!")

# Load specific version
classifier_v1 = DSPy::Registry.load_program('sentiment_classifier_v2', version: '1.5.0')

# Load by environment
production_classifier = DSPy::Registry.load_program(
  'sentiment_classifier_v2',
  environment: 'production'
)
```

## Version Management

### Semantic Versioning

```ruby
class VersionManager
  def initialize(registry)
    @registry = registry
  end
  
  def create_version(program_name, program, change_type: :patch)
    current_version = @registry.get_latest_version(program_name)
    new_version = increment_version(current_version, change_type)
    
    @registry.register(
      name: program_name,
      program: program,
      version: new_version,
      metadata: {
        previous_version: current_version,
        change_type: change_type,
        created_at: Time.current
      }
    )
    
    new_version
  end
  
  def promote_version(program_name, version, target_environment)
    program = @registry.load_program(program_name, version: version)
    
    # Validate before promotion
    validation_result = validate_for_environment(program, target_environment)
    raise "Validation failed: #{validation_result.errors}" unless validation_result.valid?
    
    # Update deployment tracking
    @registry.update_deployment(
      program_name: program_name,
      version: version,
      environment: target_environment,
      deployed_at: Time.current
    )
    
    # Create deployment record
    create_deployment_record(program_name, version, target_environment)
  end
  
  private
  
  def increment_version(current_version, change_type)
    major, minor, patch = current_version.split('.').map(&:to_i)
    
    case change_type
    when :major
      "#{major + 1}.0.0"
    when :minor
      "#{major}.#{minor + 1}.0"
    when :patch
      "#{major}.#{minor}.#{patch + 1}"
    end
  end
  
  def validate_for_environment(program, environment)
    case environment
    when 'production'
      ProductionValidator.new(program).validate
    when 'staging'
      StagingValidator.new(program).validate
    else
      BasicValidator.new(program).validate
    end
  end
end
```

### Version Comparison

```ruby
class VersionComparator
  def initialize(registry)
    @registry = registry
  end
  
  def compare_versions(program_name, version1, version2)
    program1 = @registry.load_program(program_name, version: version1)
    program2 = @registry.load_program(program_name, version: version2)
    
    {
      performance_diff: compare_performance(program1, program2),
      configuration_diff: compare_configurations(program1, program2),
      compatibility: check_compatibility(program1, program2),
      recommendation: generate_recommendation(program1, program2)
    }
  end
  
  def generate_upgrade_path(program_name, from_version, to_version)
    versions = @registry.list_versions(program_name)
                      .select { |v| version_between?(v, from_version, to_version) }
                      .sort
    
    upgrade_steps = []
    
    versions.each_cons(2) do |current, next_version|
      compatibility = check_version_compatibility(current, next_version)
      
      upgrade_steps << {
        from: current,
        to: next_version,
        compatibility: compatibility,
        breaking_changes: identify_breaking_changes(current, next_version),
        recommended_tests: generate_test_recommendations(current, next_version)
      }
    end
    
    upgrade_steps
  end
  
  private
  
  def compare_performance(program1, program2)
    metrics1 = program1.metadata[:performance] || {}
    metrics2 = program2.metadata[:performance] || {}
    
    common_metrics = metrics1.keys & metrics2.keys
    
    common_metrics.map do |metric|
      {
        metric: metric,
        version1: metrics1[metric],
        version2: metrics2[metric],
        change: metrics2[metric] - metrics1[metric],
        change_percent: ((metrics2[metric] - metrics1[metric]) / metrics1[metric] * 100).round(2)
      }
    end
  end
end
```

## Deployment Management

### Deployment Tracking

```ruby
class DeploymentTracker
  def initialize(registry)
    @registry = registry
    @deployments = {}
  end
  
  def deploy(program_name, version, environment, options = {})
    # Pre-deployment validation
    validate_deployment(program_name, version, environment)
    
    # Create deployment record
    deployment_id = create_deployment(
      program_name: program_name,
      version: version,
      environment: environment,
      strategy: options[:strategy] || :replace,
      rollback_enabled: options[:rollback_enabled] != false
    )
    
    # Execute deployment
    case options[:strategy]
    when :blue_green
      execute_blue_green_deployment(deployment_id)
    when :canary
      execute_canary_deployment(deployment_id, options[:canary_percent] || 10)
    else
      execute_standard_deployment(deployment_id)
    end
    
    # Start monitoring
    start_deployment_monitoring(deployment_id) if options[:monitor] != false
    
    deployment_id
  end
  
  def rollback(deployment_id, reason: nil)
    deployment = get_deployment(deployment_id)
    previous_version = get_previous_deployed_version(
      deployment[:program_name],
      deployment[:environment]
    )
    
    raise "No previous version to rollback to" unless previous_version
    
    # Execute rollback
    rollback_deployment_id = deploy(
      deployment[:program_name],
      previous_version,
      deployment[:environment],
      strategy: :immediate,
      reason: reason,
      rollback_from: deployment_id
    )
    
    # Update deployment status
    update_deployment_status(deployment_id, :rolled_back, reason: reason)
    
    rollback_deployment_id
  end
  
  def get_deployment_status(program_name, environment)
    current_deployment = @deployments.values
                                   .select { |d| d[:program_name] == program_name && d[:environment] == environment }
                                   .max_by { |d| d[:deployed_at] }
    
    return nil unless current_deployment
    
    {
      deployment_id: current_deployment[:id],
      version: current_deployment[:version],
      status: current_deployment[:status],
      deployed_at: current_deployment[:deployed_at],
      health: assess_deployment_health(current_deployment[:id]),
      performance: get_deployment_performance(current_deployment[:id])
    }
  end
  
  private
  
  def execute_blue_green_deployment(deployment_id)
    deployment = get_deployment(deployment_id)
    
    # Deploy to green environment
    deploy_to_green_environment(deployment)
    
    # Validate green environment
    validation_result = validate_green_environment(deployment)
    
    if validation_result.success?
      # Switch traffic to green
      switch_traffic_to_green(deployment)
      update_deployment_status(deployment_id, :completed)
    else
      # Rollback green deployment
      cleanup_green_environment(deployment)
      update_deployment_status(deployment_id, :failed, reason: validation_result.error)
    end
  end
  
  def execute_canary_deployment(deployment_id, canary_percent)
    deployment = get_deployment(deployment_id)
    
    # Start with small traffic percentage
    route_traffic_percentage(deployment, canary_percent)
    
    # Monitor canary for success metrics
    monitor_canary_deployment(deployment_id, canary_percent)
  end
end
```

### Automated Rollback

```ruby
class AutoRollbackManager
  def initialize(registry, deployment_tracker)
    @registry = registry
    @deployment_tracker = deployment_tracker
    @monitoring = {}
  end
  
  def enable_auto_rollback(deployment_id, thresholds = {})
    default_thresholds = {
      error_rate: 0.05,           # 5% error rate
      latency_p95: 2000,          # 2 second 95th percentile
      accuracy_drop: 0.10,        # 10% accuracy drop
      monitoring_window: 300      # 5 minutes
    }
    
    thresholds = default_thresholds.merge(thresholds)
    
    @monitoring[deployment_id] = {
      thresholds: thresholds,
      start_time: Time.current,
      baseline_metrics: capture_baseline_metrics(deployment_id)
    }
    
    # Start monitoring thread
    start_monitoring_thread(deployment_id)
  end
  
  def check_rollback_conditions(deployment_id)
    monitoring_config = @monitoring[deployment_id]
    return false unless monitoring_config
    
    current_metrics = capture_current_metrics(deployment_id)
    baseline_metrics = monitoring_config[:baseline_metrics]
    thresholds = monitoring_config[:thresholds]
    
    # Check each threshold
    violations = []
    
    # Error rate check
    if current_metrics[:error_rate] > thresholds[:error_rate]
      violations << "Error rate #{current_metrics[:error_rate]} exceeds threshold #{thresholds[:error_rate]}"
    end
    
    # Latency check
    if current_metrics[:latency_p95] > thresholds[:latency_p95]
      violations << "P95 latency #{current_metrics[:latency_p95]}ms exceeds threshold #{thresholds[:latency_p95]}ms"
    end
    
    # Accuracy check
    if baseline_metrics[:accuracy] && current_metrics[:accuracy]
      accuracy_drop = baseline_metrics[:accuracy] - current_metrics[:accuracy]
      if accuracy_drop > thresholds[:accuracy_drop]
        violations << "Accuracy dropped by #{accuracy_drop} (threshold: #{thresholds[:accuracy_drop]})"
      end
    end
    
    if violations.any?
      execute_auto_rollback(deployment_id, violations)
      true
    else
      false
    end
  end
  
  private
  
  def execute_auto_rollback(deployment_id, violations)
    DSPy.logger.warn "Auto-rollback triggered for deployment #{deployment_id}: #{violations.join(', ')}"
    
    # Execute rollback
    @deployment_tracker.rollback(
      deployment_id,
      reason: "Auto-rollback: #{violations.join('; ')}"
    )
    
    # Notify stakeholders
    notify_auto_rollback(deployment_id, violations)
    
    # Disable monitoring for this deployment
    @monitoring.delete(deployment_id)
  end
  
  def notify_auto_rollback(deployment_id, violations)
    deployment = @deployment_tracker.get_deployment(deployment_id)
    
    notification = {
      type: :auto_rollback,
      deployment_id: deployment_id,
      program_name: deployment[:program_name],
      environment: deployment[:environment],
      version: deployment[:version],
      violations: violations,
      timestamp: Time.current
    }
    
    DSPy::Notifications.send(notification)
  end
end
```

## Registry Configuration

### Multi-Environment Setup

```ruby
DSPy.configure do |config|
  # Registry backend
  config.registry.backend = :database
  config.registry.connection = ActiveRecord::Base.connection
  
  # Environment-specific settings
  config.registry.environments = {
    development: {
      auto_deploy: true,
      validation_required: false,
      rollback_enabled: true
    },
    staging: {
      auto_deploy: false,
      validation_required: true,
      approval_required: false,
      rollback_enabled: true
    },
    production: {
      auto_deploy: false,
      validation_required: true,
      approval_required: true,
      rollback_enabled: true,
      monitoring_required: true
    }
  }
  
  # Versioning settings
  config.registry.versioning.strategy = :semantic
  config.registry.versioning.auto_increment = :patch
  config.registry.versioning.require_changelog = true
  
  # Deployment settings
  config.registry.deployment.default_strategy = :blue_green
  config.registry.deployment.auto_rollback = true
  config.registry.deployment.monitoring_window = 10.minutes
end
```

### Access Control

```ruby
class RegistryAccessControl
  def initialize(registry)
    @registry = registry
    @permissions = {}
  end
  
  def grant_permission(user, program_name, permissions)
    @permissions[user] ||= {}
    @permissions[user][program_name] = permissions
  end
  
  def check_permission(user, program_name, action)
    user_permissions = @permissions[user] || {}
    program_permissions = user_permissions[program_name] || []
    
    case action
    when :read
      program_permissions.include?(:read) || program_permissions.include?(:admin)
    when :register
      program_permissions.include?(:register) || program_permissions.include?(:admin)
    when :deploy
      program_permissions.include?(:deploy) || program_permissions.include?(:admin)
    when :rollback
      program_permissions.include?(:rollback) || program_permissions.include?(:admin)
    when :admin
      program_permissions.include?(:admin)
    else
      false
    end
  end
  
  def authorize!(user, program_name, action)
    unless check_permission(user, program_name, action)
      raise DSPy::AccessDeniedError, "User #{user} not authorized for #{action} on #{program_name}"
    end
  end
end

# Usage with registry operations
registry = DSPy::Registry::ProgramRegistry.new
access_control = RegistryAccessControl.new(registry)

# Grant permissions
access_control.grant_permission('alice', 'sentiment_classifier', [:read, :register])
access_control.grant_permission('bob', 'sentiment_classifier', [:read, :deploy, :rollback])
access_control.grant_permission('admin', 'sentiment_classifier', [:admin])

# Check permissions before operations
def deploy_program(user, program_name, version, environment)
  access_control.authorize!(user, program_name, :deploy)
  
  deployment_tracker.deploy(program_name, version, environment)
end
```

## Registry API

### REST API Integration

```ruby
class RegistryAPI
  def initialize(registry)
    @registry = registry
  end
  
  # GET /api/registry/programs
  def list_programs(params = {})
    programs = @registry.list_programs(
      environment: params[:environment],
      team: params[:team],
      limit: params[:limit] || 50,
      offset: params[:offset] || 0
    )
    
    {
      programs: programs.map { |p| format_program_summary(p) },
      total: @registry.count_programs(params),
      page: (params[:offset] || 0) / (params[:limit] || 50) + 1
    }
  end
  
  # GET /api/registry/programs/:name
  def get_program(name, version: nil)
    program = @registry.load_program(name, version: version)
    
    {
      name: name,
      version: program.metadata[:version],
      signature: program.metadata[:signature],
      performance: program.metadata[:performance],
      deployments: get_program_deployments(name),
      versions: list_program_versions(name)
    }
  end
  
  # POST /api/registry/programs/:name/deploy
  def deploy_program(name, params)
    deployment_id = @deployment_tracker.deploy(
      name,
      params[:version],
      params[:environment],
      strategy: params[:strategy],
      canary_percent: params[:canary_percent]
    )
    
    {
      deployment_id: deployment_id,
      status: 'initiated',
      monitor_url: "/api/registry/deployments/#{deployment_id}/status"
    }
  end
  
  # POST /api/registry/deployments/:id/rollback
  def rollback_deployment(deployment_id, reason: nil)
    rollback_id = @deployment_tracker.rollback(deployment_id, reason: reason)
    
    {
      rollback_deployment_id: rollback_id,
      status: 'initiated',
      reason: reason
    }
  end
end
```

## Best Practices

### 1. Consistent Naming and Versioning

```ruby
# Use descriptive, consistent names
good_names = [
  'customer_sentiment_classifier',
  'product_recommendation_engine',
  'content_moderation_filter'
]

# Use semantic versioning
version_scheme = {
  major: 'Breaking changes to signature or API',
  minor: 'New features, improved performance, backward compatible',
  patch: 'Bug fixes, small improvements, fully backward compatible'
}
```

### 2. Comprehensive Metadata

```ruby
metadata = {
  # Core information
  signature: signature_name,
  version: semantic_version,
  created_at: Time.current,
  
  # Performance data
  performance: {
    accuracy: 0.92,
    precision: 0.89,
    recall: 0.94,
    f1_score: 0.91,
    latency_p95: 150,  # milliseconds
    cost_per_prediction: 0.001  # dollars
  },
  
  # Training information
  training: {
    optimization_method: :miprov2,
    examples_count: 5000,
    training_time: 45.minutes,
    validation_score: 0.89
  },
  
  # Deployment information
  deployment: {
    requirements: ['ruby >= 3.0', 'memory >= 1GB'],
    environments: ['staging', 'production'],
    max_concurrency: 100
  },
  
  # Organizational
  team: 'ml_platform',
  project: 'customer_experience',
  contact: 'ml-team@company.com',
  
  # Documentation
  changelog: 'Improved accuracy by 3% with better few-shot examples',
  documentation_url: 'https://docs.company.com/ml/sentiment-classifier'
}
```

### 3. Automated Testing and Validation

```ruby
class ProgramValidator
  def validate_for_registration(program, metadata)
    validations = [
      validate_signature_compatibility(program),
      validate_performance_requirements(metadata[:performance]),
      validate_security_requirements(program),
      validate_resource_requirements(metadata[:deployment])
    ]
    
    errors = validations.compact
    
    ValidationResult.new(
      valid: errors.empty?,
      errors: errors
    )
  end
  
  def validate_for_deployment(program, environment)
    case environment
    when 'production'
      [
        validate_performance_thresholds(program, min_accuracy: 0.85),
        validate_load_testing(program),
        validate_security_scan(program),
        validate_monitoring_setup(program)
      ].compact
    when 'staging'
      [
        validate_basic_functionality(program),
        validate_integration_tests(program)
      ].compact
    else
      []
    end
  end
end
```

The registry system provides the foundation for professional DSPy deployment and management, enabling teams to collaborate effectively while maintaining quality and reliability standards.