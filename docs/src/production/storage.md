---
layout: docs
name: Storage System
description: Persist and manage optimized programs
breadcrumb:
- name: Production
  url: "/production/"
- name: Storage System
  url: "/production/storage/"
prev:
  name: Production
  url: "/production/"
next:
  name: Observability
  url: "/production/observability/"
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-08-09 00:00:00 +0000
---
# Storage System

DSPy.rb provides a storage system for persisting optimization results and program states. This enables saving and reloading optimized predictors, tracking optimization history, and managing multiple versions of your programs.

## Overview

The storage system supports:
- **Program Storage**: Persist optimized predictors and their configurations
- **Optimization History**: Track optimization runs and their results
- **Program Discovery**: Find programs by various criteria
- **Checkpoint Management**: Save and restore optimization checkpoints
- **Import/Export**: Share programs between environments

## Basic Usage

### Storing Optimization Results

```ruby
# Run optimization
optimizer = DSPy::MIPROv2.new(signature: ClassifyText)
result = optimizer.optimize(examples: examples)

# Store the result using ProgramStorage directly
storage = DSPy::Storage::ProgramStorage.new(storage_path: "./dspy_storage")
saved_program = storage.save_program(
  result.optimized_program,
  result,
  metadata: {
    signature_class: 'ClassifyText',
    optimizer: 'MIPROv2',
    examples_count: examples.size
  }
)

puts "Stored program with ID: #{saved_program.program_id}"
```

### Using StorageManager (Recommended)

```ruby
# Configure storage manager
storage_manager = DSPy::Storage::StorageManager.new

# Save optimization result automatically
saved_program = storage_manager.save_optimization_result(
  result,
  tags: ['production', 'sentiment-analysis'],
  description: 'Optimized sentiment classifier v2'
)

# Or use the global instance
DSPy::Storage::StorageManager.save(result, metadata: { version: '2.0' })
```

### Loading Programs

```ruby
# Load by ID
storage = DSPy::Storage::ProgramStorage.new
saved_program = storage.load_program(program_id)

if saved_program
  predictor = saved_program.program
  puts "Loaded program from #{saved_program.saved_at}"
  puts "Best score: #{saved_program.optimization_result[:best_score_value]}"
end

# Or using StorageManager
loaded = DSPy::Storage::StorageManager.load(program_id)
```

## Storage Organization

The storage system uses a file-based approach with JSON serialization:

```
dspy_storage/
├── programs/
│   ├── abc123def456.json    # Individual program files
│   ├── 789xyz012345.json
│   └── ...
└── history.json              # Program history and metadata
```

## Finding Programs

### Search by Criteria

```ruby
storage_manager = DSPy::Storage::StorageManager.new

# Find all programs for a specific optimizer
mipro_programs = storage_manager.find_programs(
  optimizer: 'MIPROv2',
  min_score: 0.85
)

# Find recent programs
recent_programs = storage_manager.find_programs(
  max_age_days: 7,
  signature_class: 'ClassifyText'
)

# Find by tags
production_programs = storage_manager.find_programs(
  tags: ['production']
)
```

### Get Best Program

```ruby
# Get the best performing program for a signature
best_program = storage_manager.get_best_program('ClassifyText')

if best_program
  predictor = best_program.program
  score = best_program.optimization_result[:best_score_value]
  puts "Best classifier score: #{score}"
end

# Using global instance
best = DSPy::Storage::StorageManager.best('ClassifyText')
```

## Checkpoints

Create and restore checkpoints during long-running optimizations:

```ruby
# Create a checkpoint
checkpoint = storage_manager.create_checkpoint(
  current_result,
  'iteration_50',
  metadata: { iteration: 50, current_score: 0.87 }
)

# Restore from checkpoint
restored = storage_manager.restore_checkpoint('iteration_50')
if restored
  program = restored.program
  # Continue optimization from checkpoint...
end
```

## Import/Export

Share programs between environments or backup your optimizations:

```ruby
storage = DSPy::Storage::ProgramStorage.new

# Export multiple programs
program_ids = ['abc123', 'def456', 'ghi789']
storage.export_programs(program_ids, './export_backup.json')

# Import programs
imported_programs = storage.import_programs('./export_backup.json')
puts "Imported #{imported_programs.size} programs"
```

## History and Analytics

Track optimization trends and performance over time:

```ruby
# Get optimization history with trends
history = storage_manager.get_optimization_history

puts "Total programs: #{history[:summary][:total_programs]}"
puts "Average score: #{history[:summary][:avg_score]}"

# View optimizer statistics
history[:optimizer_stats].each do |optimizer, stats|
  puts "#{optimizer}: #{stats[:count]} programs, best score: #{stats[:best_score]}"
end

# Check improvement trends
trends = history[:trends]
puts "Performance improvement: #{trends[:improvement_percentage]}%"
```

## Program Comparison

Compare two saved programs:

```ruby
comparison = storage_manager.compare_programs(program_id_1, program_id_2)

puts "Score difference: #{comparison[:comparison][:score_difference]}"
puts "Better program: #{comparison[:comparison][:better_program]}"
puts "Age difference: #{comparison[:comparison][:age_difference_hours]} hours"
```

## Storage Management

### Configuration

```ruby
# Create custom storage configuration
config = DSPy::Storage::StorageManager::StorageConfig.new
config.storage_path = Rails.root.join('dspy_storage')
config.auto_save = true
config.save_intermediate_results = false
config.max_stored_programs = 100

# Initialize with custom config
storage_manager = DSPy::Storage::StorageManager.new(config: config)
```

### Cleanup Old Programs

Manage storage space by removing old programs:

```ruby
# Clean up programs beyond the configured maximum
deleted_count = storage_manager.cleanup_old_programs
puts "Deleted #{deleted_count} old programs"

# The cleanup keeps the best performing and most recent programs
# based on a weighted score (70% performance, 30% recency)
```

### List All Programs

```ruby
storage = DSPy::Storage::ProgramStorage.new

# Get all stored programs
programs = storage.list_programs
programs.each do |program|
  puts "ID: #{program[:program_id]}"
  puts "Score: #{program[:best_score]}"
  puts "Saved: #{program[:saved_at]}"
  puts "---"
end

# Get full history with metadata
history = storage.get_history
```

## Events and Monitoring

The storage system emits structured log events for monitoring:

- `dspy.storage.save_start` - When save begins
- `dspy.storage.save_complete` - Successful save with file size
- `dspy.storage.save_error` - Save failures
- `dspy.storage.load_start` - When load begins
- `dspy.storage.load_complete` - Successful load with age
- `dspy.storage.load_error` - Load failures
- `dspy.storage.delete` - Program deletion
- `dspy.storage.export` - Export operations
- `dspy.storage.import` - Import operations
- `dspy.storage.cleanup` - Cleanup operations

## Best Practices

### 1. Consistent Metadata

Always include descriptive metadata for easier program discovery:

```ruby
metadata = {
  signature_class: signature.class.name,
  version: '1.0.0',
  environment: Rails.env,
  purpose: 'customer_sentiment_analysis',
  dataset: 'customer_reviews_2024',
  performance_metrics: {
    accuracy: 0.92,
    f1_score: 0.89
  }
}
```

### 2. Use Tags Effectively

Tags help organize and find programs:

```ruby
tags = [
  Rails.env,           # 'production', 'staging', 'development'
  'validated',         # Passed validation tests
  'a_b_tested',        # Used in A/B tests
  'v2_architecture'    # Architecture version
]
```

### 3. Regular Cleanup

Schedule periodic cleanup to manage storage:

```ruby
# In a rake task or background job
task :cleanup_dspy_storage do
  manager = DSPy::Storage::StorageManager.instance
  deleted = manager.cleanup_old_programs
  puts "Cleaned up #{deleted} old programs"
end
```

### 4. Checkpoint Long Optimizations

For optimizations that take hours or days:

```ruby
# Save checkpoints every N iterations
if iteration % 10 == 0
  storage_manager.create_checkpoint(
    current_result,
    "auto_checkpoint_#{iteration}"
  )
end
```

