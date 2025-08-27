---
layout: blog
name: "Program Persistence and Serialization: Save Your Optimized DSPy Programs"
description: "DSPy.rb v0.20.0 introduces comprehensive program serialization and storage capabilities, allowing you to save, load, and share optimized DSPy programs with full state preservation."
date: 2025-08-26
author: "Vicente Reig"
category: "Features"
reading_time: "4 min read"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/program-persistence-and-serialization/"
---

DSPy.rb v0.20.0 introduces a powerful new capability: complete program persistence and serialization. Thanks to Stefan Froelich's excellent work, you can now save optimized DSPy programs to disk, reload them later, and share them across environments with full state preservation.

## The Problem: Optimization Investment

DSPy optimization can take significant time and computational resources:
- **MIPROv2 optimization** might run for hours on complex tasks
- **Few-shot examples** are carefully curated and valuable
- **Custom instructions** represent domain expertise
- **Performance metrics** provide valuable insights

Previously, these optimization results existed only in memory. If your process crashed or you needed to deploy to production, you'd lose all that valuable work.

## Introducing Program Storage

DSPy.rb now provides a comprehensive storage system that preserves:
- **Optimized program state** - Instructions, examples, and configuration
- **Performance metrics** - Scores, optimization history, and metadata  
- **Version information** - DSPy version, Ruby version, and timestamps
- **Search history** - Complete audit trail of optimization runs

## Basic Program Serialization

Every DSPy module now supports serialization through the `from_h` method:

```ruby
require 'dspy'

# Define a signature
class ProductReview < DSPy::Signature
  description "Analyze product reviews for sentiment and key insights"
  
  input do
    const :review_text, String
    const :product_category, String
  end
  
  output do
    const :sentiment, String
    const :key_points, T::Array[String]
    const :recommendation, String
    const :confidence, Float
  end
end

# Create and optimize a program
original_program = DSPy::Predict.new(ProductReview)
  .with_instruction("Focus on specific product features and user experience")
  .with_examples([
    DSPy::FewShotExample.new(
      input: {
        review_text: "This laptop is incredibly fast and the battery lasts all day!",
        product_category: "Electronics"
      },
      output: {
        sentiment: "positive",
        key_points: ["fast performance", "excellent battery life"],
        recommendation: "recommended",
        confidence: 0.95
      }
    )
  ])

# Serialize the program
program_data = {
  class_name: original_program.class.name,
  state: {
    signature_class: ProductReview.name,
    instruction: original_program.prompt.instruction,
    few_shot_examples: original_program.few_shot_examples
  }
}

# Save to JSON file
File.write('product_review_program.json', JSON.pretty_generate(program_data))

# Later, deserialize the program
loaded_data = JSON.parse(File.read('product_review_program.json'), symbolize_names: true)
restored_program = DSPy::Predict.from_h(loaded_data)

# The restored program has identical behavior
puts restored_program.prompt.instruction
# => "Focus on specific product features and user experience"

puts restored_program.few_shot_examples.size
# => 1
```

## Advanced Storage with ProgramStorage

For production use, DSPy.rb provides a comprehensive storage system:

```ruby
require 'dspy/storage/program_storage'

# Initialize storage (creates directory structure)
storage = DSPy::Storage::ProgramStorage.new(
  storage_path: "./my_optimized_programs"
)

# Create and optimize a program
program = DSPy::ChainOfThought.new(ProductReview)
  .with_instruction("Analyze reviews with step-by-step reasoning")

# Simulate optimization results (normally from MIPROv2, etc.)
optimization_result = {
  best_score_value: 0.92,
  best_score_name: 'f1_score',
  scores: { f1_score: 0.92, precision: 0.89, recall: 0.95 },
  history: { total_trials: 25, best_trial: 18 },
  metadata: { optimizer: 'MIPROv2', duration_seconds: 1800 }
}

# Save the optimized program
saved_program = storage.save_program(
  program,
  optimization_result,
  metadata: {
    task: "product_review_analysis",
    dataset: "electronics_reviews_2024",
    author: "data_team"
  }
)

puts "Saved program: #{saved_program.program_id}"
puts "Best score: #{saved_program.optimization_result[:best_score_value]}"
```

## Loading and Using Saved Programs

Load programs by ID for immediate use:

```ruby
# Load a previously saved program
loaded_program = storage.load_program(saved_program.program_id)

if loaded_program
  # Access the restored program
  restored = loaded_program.program
  
  # Use immediately
  result = restored.forward(
    review_text: "The delivery was fast but the product quality is poor",
    product_category: "Electronics"
  )
  
  puts "Sentiment: #{result.sentiment}"
  puts "Key points: #{result.key_points}"
  puts "Reasoning: #{result.reasoning}"  # Available with ChainOfThought
  
  # Check optimization metrics
  puts "This program achieved #{loaded_program.optimization_result[:best_score_value]} F1 score"
  puts "Optimized with #{loaded_program.optimization_result[:metadata][:optimizer]}"
else
  puts "Program not found"
end
```

## Program Management and History

Track and manage all your optimized programs:

```ruby
# List all saved programs
programs = storage.list_programs
programs.each do |program_info|
  puts "ID: #{program_info[:program_id]}"
  puts "Score: #{program_info[:best_score]} (#{program_info[:score_name]})"
  puts "Signature: #{program_info[:signature_class]}"
  puts "Saved: #{program_info[:saved_at]}"
  puts "---"
end

# Get comprehensive history with statistics
history = storage.get_history
puts "Total programs: #{history[:summary][:total_programs]}"
puts "Average score: #{history[:summary][:avg_score].round(3)}"
puts "Latest save: #{history[:summary][:latest_save]}"

# Programs sorted by performance
best_programs = history[:programs]
  .sort_by { |p| -p[:best_score] }
  .first(5)

puts "Top 5 performing programs:"
best_programs.each do |program|
  puts "#{program[:signature_class]}: #{program[:best_score]}"
end
```

## Import/Export for Collaboration

Share optimized programs across environments:

```ruby
# Export programs for sharing
program_ids = ['abc123', 'def456', 'ghi789']
export_path = './shared_programs.json'

storage.export_programs(program_ids, export_path)
puts "Exported #{program_ids.size} programs to #{export_path}"

# On another system or environment
new_storage = DSPy::Storage::ProgramStorage.new(
  storage_path: "./production_programs"
)

# Import the shared programs
imported_programs = new_storage.import_programs('./shared_programs.json')
puts "Imported #{imported_programs.size} programs"

imported_programs.each do |saved_program|
  puts "Available: #{saved_program.program_id} (score: #{saved_program.optimization_result[:best_score_value]})"
end
```

## Integration with Optimization Workflows

Seamlessly integrate storage with your optimization workflows:

```ruby
class ProductAnalysisOptimizer
  def initialize(storage_path: "./optimized_programs")
    @storage = DSPy::Storage::ProgramStorage.new(storage_path: storage_path)
  end
  
  def optimize_for_task(signature_class, training_data, task_name)
    puts "Starting optimization for #{task_name}..."
    
    # Create base program
    program = DSPy::ChainOfThought.new(signature_class)
    
    # Run optimization (using MIPROv2, etc.)
    optimizer = DSPy::Optimization::MIPROv2.new(
      metric: DSPy::Evaluation::Metric::F1Score.new,
      n_trials: 20
    )
    
    result = optimizer.optimize(program, training_data)
    
    # Save the optimized program
    saved_program = @storage.save_program(
      result.program,
      {
        best_score_value: result.best_score,
        best_score_name: 'f1_score',
        scores: result.scores,
        history: result.optimization_history,
        metadata: {
          optimizer: 'MIPROv2',
          task: task_name,
          training_samples: training_data.size
        }
      },
      metadata: {
        task: task_name,
        optimization_date: Time.now.iso8601,
        environment: Rails.env
      }
    )
    
    puts "Optimization complete! Saved as #{saved_program.program_id}"
    puts "Best F1 score: #{result.best_score}"
    
    saved_program
  end
  
  def load_best_for_task(task_name)
    programs = @storage.list_programs
      .select { |p| p[:metadata][:task] == task_name }
      .sort_by { |p| -p[:best_score] }
    
    if programs.any?
      best_program = @storage.load_program(programs.first[:program_id])
      puts "Loaded best #{task_name} program (score: #{best_program.optimization_result[:best_score_value]})"
      best_program.program
    else
      puts "No optimized programs found for task: #{task_name}"
      nil
    end
  end
end

# Usage
optimizer = ProductAnalysisOptimizer.new

# Optimize for a specific task
saved_program = optimizer.optimize_for_task(
  ProductReview,
  training_data,
  "product_sentiment_analysis"
)

# Later, load the best program for production
production_program = optimizer.load_best_for_task("product_sentiment_analysis")

if production_program
  # Use in production
  result = production_program.forward(
    review_text: customer_review,
    product_category: product.category
  )
end
```

## Version Compatibility and Migration

Storage includes version tracking for compatibility:

```ruby
# Check version compatibility
programs = storage.list_programs
programs.each do |program_info|
  metadata = program_info[:metadata]
  
  if metadata[:dspy_version] != DSPy::VERSION
    puts "Warning: Program #{program_info[:program_id]} was saved with DSPy v#{metadata[:dspy_version]}"
    puts "Current version: v#{DSPy::VERSION}"
  end
  
  if metadata[:ruby_version] != RUBY_VERSION
    puts "Note: Program saved with Ruby #{metadata[:ruby_version]}, running #{RUBY_VERSION}"
  end
end

# Load with version checking
def safe_load_program(storage, program_id)
  saved_program = storage.load_program(program_id)
  return nil unless saved_program
  
  saved_version = saved_program.metadata[:dspy_version]
  current_version = DSPy::VERSION
  
  if saved_version != current_version
    puts "Version mismatch detected:"
    puts "Saved with: DSPy v#{saved_version}"
    puts "Current: DSPy v#{current_version}"
    puts "Program may need reoptimization for best performance"
  end
  
  saved_program
end
```

## File Organization and Structure

The storage system creates a clean, organized structure:

```
my_optimized_programs/
├── programs/
│   ├── abc123def456.json    # Individual program files
│   ├── def456ghi789.json
│   └── ghi789jkl012.json
└── history.json             # Program index and statistics
```

Each program file contains:
```json
{
  "program_id": "abc123def456",
  "saved_at": "2024-08-26T10:30:00Z",
  "program_data": {
    "class_name": "DSPy::Predict",
    "state": {
      "signature_class": "ProductReview",
      "instruction": "Focus on specific product features...",
      "few_shot_examples": [...]
    }
  },
  "optimization_result": {
    "best_score_value": 0.92,
    "best_score_name": "f1_score",
    "scores": {...},
    "history": {...}
  },
  "metadata": {
    "dspy_version": "0.20.0",
    "ruby_version": "3.3.0",
    "task": "product_sentiment_analysis"
  }
}
```

## Best Practices

1. **Organize by Task**: Use descriptive metadata to group related programs
2. **Version Control**: Include storage directories in your version control
3. **Regular Cleanup**: Periodically remove outdated programs
4. **Backup Important Programs**: Export critical programs to separate files
5. **Environment Separation**: Use different storage paths for dev/test/prod

```ruby
# Environment-based storage paths
storage_path = case Rails.env
               when 'development'
                 './storage/development'
               when 'test'  
                 './storage/test'
               when 'production'
                 ENV['DSPY_STORAGE_PATH'] || './storage/production'
               end

storage = DSPy::Storage::ProgramStorage.new(storage_path: storage_path)
```

## Error Handling and Observability

The storage system includes comprehensive logging:

```ruby
# Storage operations are automatically logged
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(stream: 'log/dspy_storage.log')
  end
end

# Log events include:
# - storage.save_start / storage.save_complete
# - storage.load_start / storage.load_complete  
# - storage.save_error / storage.load_error
# - storage.export / storage.import
# - storage.delete

# Monitor your storage operations
saved_program = storage.save_program(program, optimization_result)
# Logs: {"message": "storage.save_complete", "storage.program_id": "abc123", 
#        "storage.best_score": 0.92, "storage.file_size": 2048}
```

## Migration Guide

If you're currently managing optimized programs manually:

```ruby
# Before: Manual serialization
program_state = {
  instruction: program.prompt.instruction,
  examples: program.few_shot_examples.map(&:to_h)
}
File.write('program.json', JSON.generate(program_state))

# After: Comprehensive storage
storage = DSPy::Storage::ProgramStorage.new
saved_program = storage.save_program(program, optimization_result)
# Automatic metadata, versioning, history tracking, and error handling
```

## Conclusion

Program persistence in DSPy.rb v0.20.0 transforms how you work with optimized programs. Key benefits:

- **Investment Protection**: Never lose optimization work again
- **Collaboration**: Share optimized programs across teams
- **Version Management**: Track program evolution and performance
- **Production Ready**: Reliable storage with comprehensive error handling
- **Audit Trail**: Complete history of optimization experiments

Special thanks to Stefan Froelich for implementing this essential feature! Start saving your optimized DSPy programs today and build a library of high-performing AI components. 🚀