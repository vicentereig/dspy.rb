---
layout: docs
name: Memory Compaction
description: Intelligent memory optimization system that automatically manages agent
  memory without background jobs
date: 2025-07-11 00:00:00 +0000
last_modified_at: 2025-08-13 00:00:00 +0000
---
# Memory Compaction System

DSPy.rb includes an intelligent memory compaction system that automatically optimizes agent memory usage without requiring background job processing. The system uses inline triggers to maintain optimal memory performance while preserving important memories.

## Overview

The memory compaction system addresses four key challenges:

1. **Size Management** - Prevents memory stores from growing indefinitely
2. **Age Management** - Removes outdated memories that may no longer be relevant
3. **Deduplication** - Eliminates near-duplicate memories using semantic similarity
4. **Relevance Pruning** - Removes memories with low access patterns

## Architecture

```
DSPy::Memory::MemoryCompactor
├── Trigger Detection (inline checks)
├── Size Compaction (oldest-first removal)
├── Age Compaction (time-based cleanup)
├── Deduplication (semantic similarity)
└── Relevance Pruning (access-based scoring)
```

## Configuration

### Default Settings

```ruby
compactor = DSPy::Memory::MemoryCompactor.new(
  max_memories: 1000,        # Maximum memories before size compaction
  max_age_days: 90,          # Maximum age before removal
  similarity_threshold: 0.95, # Cosine similarity for duplicates
  low_access_threshold: 0.1   # Relative access threshold for pruning
)
```

### Custom Configuration

```ruby
# Conservative settings for important data
conservative_compactor = DSPy::Memory::MemoryCompactor.new(
  max_memories: 5000,
  max_age_days: 365,
  similarity_threshold: 0.98,
  low_access_threshold: 0.05
)

# Aggressive settings for temporary data
aggressive_compactor = DSPy::Memory::MemoryCompactor.new(
  max_memories: 500,
  max_age_days: 30,
  similarity_threshold: 0.85,
  low_access_threshold: 0.2
)
```

## Usage

### Automatic Compaction

Compaction happens automatically during memory operations:

```ruby
manager = DSPy::Memory::MemoryManager.new

# Compaction triggers automatically when thresholds are exceeded
1000.times do |i|
  manager.store_memory("Content #{i}", user_id: "user123")
end

# Memory count will be maintained around 80% of max_memories limit
puts manager.count_memories(user_id: "user123")  # ~800 memories
```

### Manual Compaction

Force compaction regardless of thresholds:

```ruby
# Check if compaction is needed
results = manager.compact_if_needed!("user123")
puts results[:total_compacted]  # Number of memories removed

# Force all compaction strategies
results = manager.force_compact!("user123")
puts results[:size_compaction][:removed_count]
puts results[:deduplication][:removed_count]
```

## Compaction Strategies

### 1. Size Compaction

**Trigger**: Memory count exceeds `max_memories` threshold
**Action**: Remove oldest memories to reach 80% of limit
**Preservation**: Keeps most recently created and accessed memories

```ruby
# Example: 1000 memory limit, 1200 memories stored
# Result: ~800 memories (oldest 400 removed)
```

### 2. Age Compaction

**Trigger**: Any memory exceeds `max_age_days` threshold
**Action**: Remove all memories older than the age limit
**Preservation**: Only memories within the age window

```ruby
# Example: 90-day limit, memories from 6 months ago
# Result: Only memories from last 90 days remain
```

### 3. Deduplication

**Trigger**: High similarity detected in sample of recent memories
**Action**: Remove near-duplicates based on embedding similarity
**Preservation**: Keeps memory with higher access count or newer timestamp

```ruby
# Example: Two memories with 0.96 similarity (threshold 0.95)
# Result: Keep the one with more access or newer creation date
```

### 4. Relevance Pruning

**Trigger**: Many memories have low relative access patterns
**Action**: Remove bottom 20% by relevance score
**Preservation**: Keeps frequently accessed and recently created memories

```ruby
# Relevance score = (access_frequency * 0.7) + (recency_score * 0.3)
# Example: 100 memories, 30 with low relevance
# Result: Remove 20 memories with lowest relevance scores
```

## User Isolation

All compaction operations respect user boundaries:

```ruby
# Only compacts memories for specific user
manager.compact_if_needed!("user123")  # Affects only user123's memories

# Global compaction (affects all users)
manager.compact_if_needed!(nil)  # Use nil for global compaction
```

## Instrumentation and Monitoring

The compaction system emits detailed log events:

```ruby
# Process compaction logs
File.foreach("log/dspy.log") do |line|
  event = JSON.parse(line)
  
  case event["event"]
  when "dspy.memory.compaction_check"
    puts "Compaction check for user: #{event["user_id"]}"
    puts "Duration: #{event["duration_ms"]}ms"
  when "dspy.memory.size_compaction"
    puts "Size compaction removed #{event["removed_count"]} memories"
    puts "Before: #{event["before_count"]}, After: #{event["after_count"]}"
  end
end
```

### Available Events

- `dspy.memory.compaction_check` - Overall compaction evaluation
- `dspy.memory.size_compaction` - Size-based memory removal
- `dspy.memory.age_compaction` - Age-based memory removal
- `dspy.memory.deduplication` - Duplicate memory removal
- `dspy.memory.relevance_pruning` - Low-relevance memory removal
- `dspy.memory.compaction_complete` - Forced compaction completion

## Performance Characteristics

### Inline Processing

- **No background jobs** - All compaction happens synchronously
- **Predictable timing** - Compaction occurs during store operations
- **Simple deployment** - No additional infrastructure required

### Efficiency Optimizations

- **Sampling** - Uses representative samples for trigger detection
- **Batch operations** - Processes multiple removals efficiently
- **Early termination** - Stops when thresholds are no longer exceeded

### Memory Impact

```ruby
# Typical compaction removes 20-30% of memories
before_count = 1000
after_count = 750   # 25% reduction

# Compaction targets (80% of limit)
max_memories = 1000
target_after_compaction = 800  # 80% of 1000
```

## Integration Examples

### With MemoryToolset

```ruby
# Memory toolset automatically benefits from compaction
memory_tools = DSPy::Tools::MemoryToolset.to_tools

agent = DSPy::ReAct.new(
  MySignature,
  tools: memory_tools,
  max_iterations: 5
)

# As agent stores memories, compaction maintains optimal size
response = agent.call(question: "Remember that I prefer dark mode")
```

### With Custom Memory Backends

```ruby
# Compaction works with any MemoryStore implementation
redis_store = RedisMemoryStore.new(redis_client)
file_store = FileMemoryStore.new('/tmp/memories')

manager_redis = DSPy::Memory::MemoryManager.new(store: redis_store)
manager_file = DSPy::Memory::MemoryManager.new(store: file_store)

# Both benefit from the same compaction logic
manager_redis.store_memory("Content", user_id: "user1")
manager_file.store_memory("Content", user_id: "user2")
```

## Testing Compaction

### Unit Testing

```ruby
RSpec.describe DSPy::Memory::MemoryCompactor do
  it 'triggers size compaction when needed' do
    compactor = described_class.new(max_memories: 10)
    
    # Add memories beyond limit
    15.times { |i| store_memory("Content #{i}") }
    
    results = compactor.compact_if_needed!(store, embedding_engine)
    expect(results[:size_compaction][:removed_count]).to be > 0
  end
end
```

### Integration Testing

```ruby
RSpec.describe 'Memory Compaction Integration' do
  it 'maintains memory limits during normal operation' do
    25.times { |i| manager.store_memory("Content #{i}") }
    
    final_count = manager.count_memories
    expect(final_count).to be <= 20  # Within configured limit
  end
end
```

## Best Practices

### Configuration Guidelines

1. **Size Limits**: Set based on available memory and expected usage patterns
2. **Age Limits**: Consider data retention requirements and user expectations
3. **Similarity Thresholds**: Higher values (0.95+) for precise deduplication
4. **Access Thresholds**: Lower values (0.05-0.1) for aggressive pruning

### Monitoring Recommendations

1. **Track compaction frequency** - Monitor how often compaction triggers
2. **Monitor removal counts** - Ensure compaction isn't too aggressive
3. **Watch user impact** - Verify important memories aren't being removed
4. **Performance metrics** - Track compaction timing and memory usage

### Production Considerations

1. **User notification** - Consider informing users about automatic cleanup
2. **Backup strategies** - Implement memory export before major compactions
3. **Rollback capabilities** - Plan for memory restoration if needed
4. **Gradual rollout** - Test compaction settings with subset of users first

## Future Enhancements

The compaction system is designed for future extensibility:

- **Custom scoring algorithms** for relevance calculation
- **Machine learning** based duplicate detection
- **Hierarchical compaction** with different rules per memory type
- **Background processing** option for high-volume environments
- **Cross-user memory** sharing and deduplication

## Migration from Background Processing

If you're migrating from a background job-based system:

```ruby
# Old approach (background job)
CompactionJob.perform_later(user_id)

# New approach (inline)
manager.compact_if_needed!(user_id)

# No infrastructure changes needed:
# - No job queue required
# - No background workers
# - No job scheduling
# - No job failure handling
```

The inline compaction system provides the same benefits with simpler deployment and more predictable behavior.