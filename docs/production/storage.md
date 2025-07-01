# Storage System

DSPy.rb provides a comprehensive storage system for persisting optimization results, program states, and performance data. This enables reproducible optimization, rollback capabilities, and long-term performance tracking.

## Overview

The storage system supports:
- **Program Storage**: Persist optimized predictors and their configurations
- **Optimization History**: Track optimization runs and their results
- **Performance Metrics**: Store evaluation data and performance trends
- **Version Management**: Maintain multiple versions with rollback capabilities
- **Search and Filtering**: Query stored data efficiently

## Basic Usage

### Storing Optimization Results

```ruby
# Run optimization
optimizer = DSPy::MIPROv2.new(signature: ClassifyText)
result = optimizer.optimize(examples: examples)

# Store the result
storage = DSPy::Storage::ProgramStorage.new
storage_id = storage.store(
  program: result.best_predictor,
  metadata: {
    optimization_method: :miprov2,
    signature: 'ClassifyText',
    version: '1.0.0',
    performance: result.best_score,
    examples_count: examples.size,
    optimization_time: result.total_time
  }
)

puts "Stored program with ID: #{storage_id}"
```

### Loading Programs

```ruby
# Load by ID
stored_program = storage.load(storage_id)
predictor = stored_program.program

# Use the loaded predictor
result = predictor.call(text: "Sample text to classify")

# Access metadata
puts "Version: #{stored_program.metadata[:version]}"
puts "Performance: #{stored_program.metadata[:performance]}"
```

## Storage Backends

### File-based Storage

```ruby
# Configure file storage
DSPy.configure do |config|
  config.storage.backend = :file
  config.storage.base_path = Rails.root.join('dspy_storage')
  config.storage.compression = true  # Compress stored data
  config.storage.encryption = true   # Encrypt sensitive data
end

# File storage organizes data hierarchically
# dspy_storage/
# ├── programs/
# │   ├── 2024/01/15/program_abc123.json
# │   └── 2024/01/16/program_def456.json
# ├── optimizations/
# │   └── miprov2/
# └── metrics/
```

### Database Storage

```ruby
# Configure database storage
DSPy.configure do |config|
  config.storage.backend = :database
  config.storage.connection = ActiveRecord::Base.connection
  config.storage.table_prefix = 'dspy_'
end

# Database schema
# dspy_programs:
#   - id (uuid)
#   - signature_name
#   - program_data (jsonb)
#   - metadata (jsonb)
#   - created_at
#   - updated_at
#   - version
#   - performance_score

# dspy_optimization_runs:
#   - id (uuid)
#   - program_id (foreign key)
#   - method
#   - parameters (jsonb)
#   - results (jsonb)
#   - created_at
```

### Cloud Storage

```ruby
# Configure S3 storage
DSPy.configure do |config|
  config.storage.backend = :s3
  config.storage.bucket = 'my-dspy-storage'
  config.storage.region = 'us-west-2'
  config.storage.access_key_id = ENV['AWS_ACCESS_KEY_ID']
  config.storage.secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
end

# Cloud storage with automatic backups and versioning
cloud_storage = DSPy::Storage::CloudStorage.new
cloud_storage.store(
  program: optimized_predictor,
  metadata: metadata,
  backup_policy: :daily,
  retention_period: 90.days
)
```

## Advanced Storage Features

### Versioned Storage

```ruby
class VersionedProgramStorage
  def initialize(base_storage)
    @storage = base_storage
    @version_registry = {}
  end
  
  def store_version(program, version:, metadata: {})
    # Validate version format
    raise ArgumentError, "Invalid version format" unless valid_version?(version)
    
    # Store with version metadata
    storage_id = @storage.store(
      program: program,
      metadata: metadata.merge(
        version: version,
        created_at: Time.current,
        previous_version: get_latest_version(metadata[:signature])
      )
    )
    
    # Update version registry
    signature = metadata[:signature]
    @version_registry[signature] ||= {}
    @version_registry[signature][version] = storage_id
    
    storage_id
  end
  
  def load_version(signature, version: :latest)
    if version == :latest
      version = get_latest_version(signature)
    end
    
    storage_id = @version_registry.dig(signature, version)
    raise "Version #{version} not found for #{signature}" unless storage_id
    
    @storage.load(storage_id)
  end
  
  def list_versions(signature)
    versions = @version_registry[signature] || {}
    
    versions.map do |version, storage_id|
      stored_program = @storage.load(storage_id)
      {
        version: version,
        storage_id: storage_id,
        created_at: stored_program.metadata[:created_at],
        performance: stored_program.metadata[:performance],
        size: stored_program.size
      }
    end.sort_by { |v| v[:created_at] }
  end
  
  def rollback_to_version(signature, target_version)
    # Load target version
    target_program = load_version(signature, version: target_version)
    
    # Create new version based on target
    new_version = generate_rollback_version(target_version)
    
    store_version(
      target_program.program,
      version: new_version,
      metadata: target_program.metadata.merge(
        rollback_from: get_latest_version(signature),
        rollback_to: target_version,
        rollback_timestamp: Time.current
      )
    )
  end
end
```

### Performance Tracking Storage

```ruby
class PerformanceStorage
  def initialize(storage_backend)
    @storage = storage_backend
  end
  
  def record_performance(program_id, metrics)
    performance_record = {
      program_id: program_id,
      timestamp: Time.current,
      metrics: metrics,
      environment: capture_environment_info
    }
    
    @storage.store(
      collection: :performance_metrics,
      data: performance_record
    )
  end
  
  def get_performance_history(program_id, time_range: 30.days)
    @storage.query(
      collection: :performance_metrics,
      filters: {
        program_id: program_id,
        timestamp: { gte: Time.current - time_range }
      },
      sort: { timestamp: :asc }
    )
  end
  
  def analyze_performance_trends(program_id)
    history = get_performance_history(program_id, time_range: 90.days)
    
    metrics_over_time = history.group_by { |record| record[:timestamp].to_date }
    
    trends = {}
    [:accuracy, :latency, :cost].each do |metric|
      metric_values = metrics_over_time.map do |date, records|
        avg_value = records.map { |r| r[:metrics][metric] }.compact.sum / records.size
        [date, avg_value]
      end.to_h
      
      trends[metric] = {
        current: metric_values.values.last,
        trend: calculate_trend(metric_values.values),
        change_30d: calculate_change(metric_values.values, days: 30)
      }
    end
    
    trends
  end
  
  private
  
  def capture_environment_info
    {
      ruby_version: RUBY_VERSION,
      dspy_version: DSPy::VERSION,
      timestamp: Time.current,
      hostname: Socket.gethostname,
      git_commit: `git rev-parse HEAD`.strip rescue nil
    }
  end
end
```

## Search and Querying

### Program Search

```ruby
class ProgramSearch
  def initialize(storage)
    @storage = storage
    @index = build_search_index
  end
  
  def search(query)
    # Support multiple search criteria
    criteria = parse_search_query(query)
    
    results = @storage.query(
      filters: build_filters(criteria),
      sort: criteria[:sort] || { performance: :desc },
      limit: criteria[:limit] || 20
    )
    
    # Enhance results with relevance scoring
    results.map do |result|
      result.merge(
        relevance_score: calculate_relevance(result, criteria),
        summary: generate_result_summary(result)
      )
    end.sort_by { |r| -r[:relevance_score] }
  end
  
  def find_similar_programs(program_id, similarity_threshold: 0.8)
    target_program = @storage.load(program_id)
    
    # Find programs with similar characteristics
    candidates = @storage.query(
      filters: {
        signature: target_program.metadata[:signature],
        version: { ne: target_program.metadata[:version] }
      }
    )
    
    similar_programs = candidates.select do |candidate|
      similarity = calculate_program_similarity(target_program, candidate)
      similarity >= similarity_threshold
    end
    
    similar_programs.sort_by { |p| -calculate_program_similarity(target_program, p) }
  end
  
  private
  
  def parse_search_query(query)
    # Support natural language and structured queries
    # Examples:
    # "ClassifyText performance > 0.9"
    # "version:1.* method:miprov2 created:last_week"
    # "high performing sentiment classifiers"
    
    if query.include?(':')
      parse_structured_query(query)
    else
      parse_natural_language_query(query)
    end
  end
  
  def calculate_program_similarity(program1, program2)
    # Compare based on:
    # - Signature compatibility
    # - Performance characteristics
    # - Optimization parameters
    # - Examples used
    
    signature_similarity = program1.metadata[:signature] == program2.metadata[:signature] ? 1.0 : 0.0
    performance_similarity = 1.0 - (program1.metadata[:performance] - program2.metadata[:performance]).abs
    
    # Weighted combination
    (0.5 * signature_similarity + 0.3 * performance_similarity + 0.2 * parameter_similarity(program1, program2))
  end
end
```

### Advanced Querying

```ruby
# Complex queries with multiple criteria
search_results = storage.search({
  signature: 'ClassifyText',
  performance: { gte: 0.85 },
  created_at: { gte: 1.week.ago },
  optimization_method: ['miprov2', 'simple_optimizer'],
  metadata: {
    examples_count: { gte: 100 }
  },
  sort: [
    { performance: :desc },
    { created_at: :desc }
  ],
  limit: 10
})

# Aggregation queries
performance_stats = storage.aggregate({
  signature: 'ClassifyText',
  group_by: :optimization_method,
  metrics: {
    avg_performance: { avg: :performance },
    max_performance: { max: :performance },
    count: { count: :id }
  }
})

# Time-series queries
performance_over_time = storage.time_series({
  signature: 'ClassifyText',
  metric: :performance,
  interval: :day,
  time_range: 30.days
})
```

## Storage Management

### Cleanup and Archival

```ruby
class StorageManager
  def initialize(storage)
    @storage = storage
  end
  
  def cleanup_old_versions(retention_policy: {})
    default_policy = {
      keep_latest: 5,                    # Keep 5 most recent versions
      keep_high_performing: true,        # Keep versions with > 95th percentile performance
      keep_production: true,             # Keep versions marked as production
      archive_threshold: 90.days,        # Archive versions older than 90 days
      delete_threshold: 1.year           # Delete versions older than 1 year
    }
    
    policy = default_policy.merge(retention_policy)
    
    signatures = @storage.list_signatures
    
    signatures.each do |signature|
      cleanup_signature_versions(signature, policy)
    end
  end
  
  def archive_to_cold_storage(program_ids)
    program_ids.each do |program_id|
      program = @storage.load(program_id)
      
      # Compress and store in cold storage
      archived_data = compress_program(program)
      cold_storage_id = store_in_cold_storage(archived_data)
      
      # Update original record with archive reference
      @storage.update(program_id, {
        archived: true,
        cold_storage_id: cold_storage_id,
        archived_at: Time.current
      })
      
      # Remove original data
      @storage.delete_data(program_id)
    end
  end
  
  def restore_from_archive(program_id)
    program_metadata = @storage.load_metadata(program_id)
    
    unless program_metadata[:archived]
      raise "Program #{program_id} is not archived"
    end
    
    # Restore from cold storage
    archived_data = load_from_cold_storage(program_metadata[:cold_storage_id])
    program = decompress_program(archived_data)
    
    # Restore to active storage
    @storage.store_data(program_id, program)
    @storage.update(program_id, {
      archived: false,
      restored_at: Time.current
    })
  end
  
  private
  
  def cleanup_signature_versions(signature, policy)
    versions = @storage.list_versions(signature)
                      .sort_by { |v| v[:created_at] }
                      .reverse
    
    # Keep latest versions
    to_keep = versions.first(policy[:keep_latest])
    
    # Keep high-performing versions
    if policy[:keep_high_performing]
      performance_threshold = calculate_performance_threshold(versions, percentile: 95)
      high_performers = versions.select { |v| v[:performance] >= performance_threshold }
      to_keep += high_performers
    end
    
    # Keep production versions
    if policy[:keep_production]
      production_versions = versions.select { |v| v[:metadata][:environment] == 'production' }
      to_keep += production_versions
    end
    
    to_keep = to_keep.uniq { |v| v[:storage_id] }
    
    # Determine versions to archive or delete
    versions_to_process = versions - to_keep
    
    archive_candidates = versions_to_process.select do |v|
      v[:created_at] < Time.current - policy[:archive_threshold] &&
      v[:created_at] > Time.current - policy[:delete_threshold]
    end
    
    delete_candidates = versions_to_process.select do |v|
      v[:created_at] < Time.current - policy[:delete_threshold]
    end
    
    # Archive old versions
    archive_to_cold_storage(archive_candidates.map { |v| v[:storage_id] })
    
    # Delete very old versions
    delete_candidates.each { |v| @storage.delete(v[:storage_id]) }
  end
end
```

### Backup and Recovery

```ruby
class BackupManager
  def initialize(storage, backup_storage)
    @storage = storage
    @backup_storage = backup_storage
  end
  
  def create_backup(backup_name = nil)
    backup_name ||= "backup_#{Time.current.strftime('%Y%m%d_%H%M%S')}"
    
    # Create consistent snapshot
    snapshot = @storage.create_snapshot
    
    # Backup all data
    backup_data = {
      timestamp: Time.current,
      version: DSPy::VERSION,
      snapshot_id: snapshot.id,
      programs: export_all_programs,
      metrics: export_all_metrics,
      metadata: export_metadata
    }
    
    # Store backup
    backup_id = @backup_storage.store(backup_name, backup_data)
    
    # Cleanup snapshot
    @storage.cleanup_snapshot(snapshot.id)
    
    {
      backup_id: backup_id,
      backup_name: backup_name,
      size: calculate_backup_size(backup_data),
      programs_count: backup_data[:programs].size
    }
  end
  
  def restore_backup(backup_name, options = {})
    backup_data = @backup_storage.load(backup_name)
    
    if options[:verify_compatibility]
      verify_version_compatibility(backup_data[:version])
    end
    
    # Restore programs
    backup_data[:programs].each do |program_data|
      @storage.restore_program(program_data)
    end
    
    # Restore metrics
    backup_data[:metrics].each do |metric_data|
      @storage.restore_metrics(metric_data)
    end
    
    # Restore metadata
    @storage.restore_metadata(backup_data[:metadata])
    
    {
      restored_programs: backup_data[:programs].size,
      restored_metrics: backup_data[:metrics].size,
      restore_time: Time.current
    }
  end
end
```

## Configuration

### Storage Configuration

```ruby
DSPy.configure do |config|
  # Storage backend
  config.storage.backend = :database  # :file, :database, :s3, :redis
  
  # Connection settings
  config.storage.connection_string = ENV['DATABASE_URL']
  config.storage.pool_size = 5
  config.storage.timeout = 30.seconds
  
  # Performance settings
  config.storage.cache_enabled = true
  config.storage.cache_ttl = 1.hour
  config.storage.compression = :gzip  # :gzip, :lz4, :none
  config.storage.batch_size = 100
  
  # Security settings
  config.storage.encryption_key = ENV['DSPY_ENCRYPTION_KEY']
  config.storage.access_control = true
  
  # Retention policies
  config.storage.retention.keep_versions = 10
  config.storage.retention.archive_after = 90.days
  config.storage.retention.delete_after = 1.year
  
  # Backup settings
  config.storage.backup.enabled = true
  config.storage.backup.frequency = :daily
  config.storage.backup.retain_count = 30
end
```

## Best Practices

### 1. Organized Storage Structure

```ruby
# Use consistent metadata for organization
metadata = {
  signature: signature.name,
  version: semantic_version,
  environment: Rails.env,
  project: 'customer_service_bot',
  team: 'ml_engineering',
  performance: { accuracy: 0.92, latency: 1.2 },
  tags: ['production', 'a_b_tested', 'validated']
}
```

### 2. Regular Cleanup

```ruby
# Schedule regular cleanup
class StorageCleanupJob < ApplicationJob
  def perform
    storage_manager = DSPy::Storage::Manager.new
    
    # Cleanup old versions
    storage_manager.cleanup_old_versions
    
    # Archive low-performing versions
    storage_manager.archive_low_performers(threshold: 0.7)
    
    # Create backup
    backup_manager = DSPy::Storage::BackupManager.new
    backup_manager.create_backup
  end
end

# Schedule daily cleanup
StorageCleanupJob.set(cron: '0 2 * * *').perform_later
```

### 3. Monitor Storage Usage

```ruby
class StorageMonitor
  def generate_report
    storage = DSPy::Storage.current
    
    {
      total_programs: storage.count_programs,
      storage_size: storage.total_size,
      recent_activity: storage.recent_activity(7.days),
      top_signatures: storage.top_signatures_by_usage,
      performance_trends: storage.performance_trends,
      storage_health: assess_storage_health
    }
  end
end
```

The storage system provides a robust foundation for managing DSPy programs in production environments, with comprehensive versioning, backup, and cleanup capabilities.