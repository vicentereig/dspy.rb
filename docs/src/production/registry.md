---
layout: docs
name: Registry & Versions
description: Version management for signature configurations and deployment tracking
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-09 00:00:00 +0000
---
# Registry & Versions

The registry records versioned signature configurations and which version an environment has deployed. It can register optimization results, compare recorded scores, promote a version, and roll back the deployment pointer.

## Define What the Registry Records

The registry records:
- **Signature Version Management**: Track different versions of signature configurations
- **Deployment Tracking**: Know which version is currently deployed
- **Performance History**: Track performance scores across versions
- **Optimization Integration**: Register optimization results through `RegistryManager`
- **Rollback**: Move an environment's deployment pointer to an earlier version

## Register a Version

### Create the Registry

```ruby
registry = DSPy::Registry::SignatureRegistry.new

config = DSPy::Registry::SignatureRegistry::RegistryConfig.new
config.registry_path = "./my_dspy_registry"
config.auto_version = true
config.max_versions_per_signature = 10

registry = DSPy::Registry::SignatureRegistry.new(config: config)
```

### Registering Versions

```ruby
program = DSPy::Predict.new(ClassifyText)
metric = proc { |example, prediction| prediction.sentiment == example.expected_sentiment }
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
result = optimizer.compile(program, trainset: training_examples)

configuration = {
  instruction: result.optimized_program.prompt.instruction,
  few_shot_examples_count: result.optimized_program.few_shot_examples.size
}

version = registry.register_version(
  'text_classifier',
  configuration,
  metadata: {
    optimizer: 'MIPROv2',
    training_examples: training_examples.size,
    accuracy: result.best_score_value
  },
  program_id: 'abc123'  # From storage system if saved
)

puts "Registered version: #{version.version}"
```

### Registering an Optimization Result with RegistryManager

```ruby
manager = DSPy::Registry::RegistryManager.new

manager.integration_config.auto_register_optimizations = true
manager.integration_config.auto_deploy_best_versions = true
manager.integration_config.auto_deploy_threshold = 0.1  # 10% improvement

version = manager.register_optimization_result(
  result,
  signature_name: 'text_classifier',
  metadata: { environment: 'production' }
)
```

## Version Management

### Listing Versions

```ruby
versions = registry.list_versions('text_classifier')

versions.each do |v|
  puts "Version: #{v.version}"
  puts "Created: #{v.created_at}"
  puts "Score: #{v.performance_score}"
  puts "Deployed: #{v.is_deployed}"
  puts "---"
end

signatures = registry.list_signatures
puts "Registered signatures: #{signatures.join(', ')}"
```

### Updating Performance Scores

```ruby
registry.update_performance_score(
  'text_classifier',
  'v20240115_143022',
  0.92  # New accuracy score
)

history = registry.get_performance_history('text_classifier')
puts "Best score: #{history[:trends][:best_score]}"
puts "Improvement trend: #{history[:trends][:improvement_trend]}%"
```

### Comparing Versions

```ruby
comparison = registry.compare_versions(
  'text_classifier',
  'v20240115_143022',
  'v20240114_090511'
)

puts "Performance difference: #{comparison[:comparison][:performance_difference]}"
puts "Configuration changes:"
comparison[:comparison][:configuration_changes].each do |change|
  puts "  - #{change}"
end
```

## Move the Deployment Pointer

### Record a Deployed Version

```ruby
deployed = registry.deploy_version('text_classifier', 'v20240115_143022')

if deployed
  puts "Deployed version #{deployed.version}"
else
  puts "Deployment failed"
end

current = registry.get_deployed_version('text_classifier')
puts "Currently deployed: #{current.version}" if current
```

### Rollback

```ruby
rolled_back = registry.rollback('text_classifier')

if rolled_back
  puts "Rolled back to version #{rolled_back.version}"
else
  puts "No previous version to rollback to"
end
```

### Deployment Strategies with RegistryManager

```ruby
# Deploy using different strategies
manager = DSPy::Registry::RegistryManager.new

# Conservative: Only deploy if 10% improvement
manager.deploy_with_strategy('text_classifier', strategy: 'conservative')

# Aggressive: Deploy best performing version
manager.deploy_with_strategy('text_classifier', strategy: 'aggressive')

# Best score: Same as aggressive, deploys highest scoring version
manager.deploy_with_strategy('text_classifier', strategy: 'best_score')
```

## Optimization Integration

### Manual Registration

```ruby
# Enable registration on this manager
config = DSPy::Registry::RegistryManager::RegistryIntegrationConfig.new
config.auto_register_optimizations = true

manager = DSPy::Registry::RegistryManager.new(integration_config: config)

program = DSPy::Predict.new(ClassifyText)
metric = proc { |example, prediction| prediction.sentiment == example.expected_sentiment }
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
result = optimizer.compile(program, trainset: examples)

# register_optimization_result performs the registration when enabled
version = manager.register_optimization_result(result)
```

This example calls the manager explicitly. For optimizer-triggered registration, configure `DSPy::Registry::RegistryManager.instance` and set the optimizer's `save_intermediate_results` option. Optimizers use that singleton after a compile; a separately constructed manager does not receive those calls.

### Performance Monitoring and Rollback

```ruby
# Monitor performance and rollback if it drops
manager.integration_config.rollback_on_performance_drop = true
manager.integration_config.rollback_threshold = 0.05  # 5% drop triggers rollback

current_accuracy = evaluate_deployed_model()
rolled_back = manager.monitor_and_rollback('text_classifier', current_accuracy)

if rolled_back
  puts "Performance drop detected - automatically rolled back"
end
```

## Inspect and Maintain Registry State

### Configure File Storage

The registry uses file-based storage with YAML files:

```text
dspy_registry/
├── registry.yml          # Registry configuration
├── signatures/
│   ├── text_classifier.yml
│   └── entity_extractor.yml
└── backups/              # Deployment backups
    └── text_classifier/
        └── v20240115_143022_20240116_092000.yml
```

### Deployment Status

```ruby
status = manager.get_deployment_status('text_classifier')

puts "Deployed: #{status[:deployed_version][:version]}" if status[:deployed_version]
puts "Total versions: #{status[:total_versions]}"
puts "Recommendations:"
status[:recommendations].each do |rec|
  puts "  - #{rec}"
end
```

### Deployment Planning

```ruby
plan = manager.create_deployment_plan('text_classifier', 'v20240115_143022')

puts "Safe to deploy: #{plan[:deployment_safe]}"
puts "Performance change: #{plan[:performance_change]}"
puts "Checks:"
plan[:checks].each { |check| puts "  - #{check}" }
puts "Recommendations:"
plan[:recommendations].each { |rec| puts "  - #{rec}" }
```

### Cleanup

```ruby
cleanup_results = manager.cleanup_old_versions

puts "Cleaned #{cleanup_results[:cleaned_versions]} versions"
puts "From #{cleanup_results[:cleaned_signatures]} signatures"
```

## Import/Export

### Export Registry

```ruby
# Export entire registry state
registry.export_registry('./registry_backup.yml')

# The export includes all versions and metadata
```

### Import Registry

```ruby
# Import from backup
registry.import_registry('./registry_backup.yml')

# This restores all versions and configurations
```

## Events and Monitoring

The registry emits structured log events for monitoring:

- `dspy.registry.register_start` - Version registration begins
- `dspy.registry.register_complete` - Version registered successfully
- `dspy.registry.register_error` - Registration failed
- `dspy.registry.deploy_start` - Deployment begins
- `dspy.registry.deploy_complete` - Deployment successful
- `dspy.registry.deploy_error` - Deployment failed
- `dspy.registry.rollback_start` - Rollback initiated
- `dspy.registry.rollback_complete` - Rollback successful
- `dspy.registry.rollback_error` - Rollback failed
- `dspy.registry.performance_update` - Performance score updated
- `dspy.registry.auto_deployment` - Automatic deployment triggered
- `dspy.registry.automatic_rollback` - Automatic rollback triggered
- `dspy.registry.export` - Registry exported
- `dspy.registry.import` - Registry imported

## Preserve Selection Evidence

### 1. Version Naming

By default, the registry uses timestamp-based versions:
```ruby
config.version_format = "v%Y%m%d_%H%M%S"  # v20240115_143022
```

You can also provide custom version names:
```ruby
registry.register_version(
  'text_classifier',
  configuration,
  version: '2.1.0'  # Semantic versioning
)
```

### 2. Metadata Standards

Record enough metadata to reproduce the selection decision:

```ruby
metadata = {
  # Performance metrics
  accuracy: 0.92,
  precision: 0.89,
  recall: 0.94,
  
  # Training information
  optimizer: 'MIPROv2',
  training_examples: 5000,
  training_time_minutes: 45,
  
  # Environment
  environment: 'production',
  tested_in: ['staging', 'qa'],
  
  # Team information
  team: 'ml_platform',
  approved_by: 'alice@example.com'
}
```

### 3. Performance Tracking

Always update performance scores after evaluation:

```ruby
production_accuracy = evaluate_in_production()
registry.update_performance_score(
  'text_classifier',
  deployed_version.version,
  production_accuracy
)
```

### 4. Require a Promotion Threshold

Set a measured promotion threshold and keep rollback policy in the application deployment process:

```ruby
# Only deploy if significantly better
manager.integration_config.auto_deploy_threshold = 0.15  # 15% improvement
manager.integration_config.deployment_strategy = 'conservative'
```
