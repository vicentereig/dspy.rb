---
layout: docs
name: Memory
description: Persistent memory for stateful agents
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Memory
  url: "/core-concepts/memory/"
nav:
  prev:
    name: Modules
    url: "/core-concepts/modules/"
  next:
    name: Toolsets
    url: "/core-concepts/toolsets/"
date: 2025-07-11 00:00:00 +0000
---
# Memory

DSPy.rb provides a memory system that allows agents to store and retrieve information across interactions. The memory system includes data structures for storing memories, storage backends, and tools for agent integration.

## Basic Usage

### Memory Manager

The memory system is accessed through `DSPy::Memory.manager`:

```ruby
# Store a memory
record = DSPy::Memory.manager.store_memory(
  "Dark mode enabled",
  user_id: "user123",
  tags: ["ui", "preference"]
)

# Retrieve a memory by ID
memory = DSPy::Memory.manager.get_memory(record.id)
puts memory.content  # => "Dark mode enabled"

# Search memories
results = DSPy::Memory.manager.search_memories("preference")
puts results.first.content  # => "Dark mode enabled"
```

### Memory Records

Memory records are the basic unit of storage:

```ruby
# Create a memory record
record = DSPy::Memory::MemoryRecord.new(
  content: "User prefers email notifications",
  user_id: "user123",
  tags: ["notification", "email"],
  metadata: { source: "user_input" }
)

# Access record properties
puts record.id         # => "generated-uuid"
puts record.content    # => "User prefers email notifications"
puts record.tags       # => ["notification", "email"]
puts record.created_at # => 2025-01-01 12:00:00 UTC
```

## Memory with Agents

### Using Memory Toolset

The `MemoryToolset` provides tools that agents can use to interact with memory:

```ruby
class PersonalAssistant < DSPy::Signature
  description "Personal assistant with memory"
  
  input do
    const :query, String
  end
  
  output do
    const :response, String
  end
end

# Create agent with memory tools
memory_tools = DSPy::Tools::MemoryToolset.to_tools
agent = DSPy::ReAct.new(
  PersonalAssistant,
  tools: memory_tools
)

# Agent can now store and retrieve memories
result = agent.call(query: "Remember that I like dark mode")
# Agent will use memory_store tool to save this preference

result = agent.call(query: "What theme do I prefer?")
# Agent will use memory_search tool to find the preference
```

### Available Memory Operations

The memory toolset provides these operations to agents:

- `memory_store(key:, value:, tags: nil)` - Store a memory
- `memory_retrieve(key:)` - Retrieve by key
- `memory_search(pattern:)` - Search memories
- `memory_list()` - List all memories
- `memory_update(key:, value:)` - Update existing memory
- `memory_delete(key:)` - Delete a memory
- `memory_clear()` - Clear all memories
- `memory_count()` - Count stored memories
- `memory_get_metadata(key:)` - Get memory metadata

## Storage Backends

### In-Memory Storage (Default)

The default storage keeps memories in memory:

```ruby
# Uses in-memory storage by default
manager = DSPy::Memory::MemoryManager.new
manager.store(key: "test", value: "data")
```

### Custom Storage

You can implement custom storage backends by extending `MemoryStore`:

```ruby
class CustomMemoryStore < DSPy::Memory::MemoryStore
  def store(record)
    # Your storage implementation
  end
  
  def retrieve(id)
    # Your retrieval implementation
  end
  
  # Implement other required methods...
end

# Use custom storage
manager = DSPy::Memory::MemoryManager.new(store: CustomMemoryStore.new)
```

## Memory Compaction

The memory system includes automatic compaction to prevent unlimited growth:

```ruby
# Configure compaction thresholds
manager = DSPy::Memory::MemoryManager.new
# Compaction is configured when creating the manager
# Default settings: max 1000 memories, 90 days max age, 0.95 similarity threshold

# Compaction runs automatically during normal operations
manager.store_memory("test content", user_id: "user123")  # May trigger compaction

# You can also force compaction
manager.force_compact!
```

## Best Practices

### 1. Use Descriptive Content

```ruby
# Good: Clear, descriptive content
manager.store_memory(
  "User prefers dark theme for UI",
  user_id: "user123",
  tags: ["preference", "ui"]
)

# Avoid: Generic content
manager.store_memory("dark", user_id: "user123")
```

### 2. Use Tags for Organization

```ruby
# Tag memories for easy searching
manager.store_memory(
  "User prefers email notifications",
  user_id: "user123",
  tags: ["notification", "user_preference", "email"]
)

# Search by category
email_prefs = manager.search_by_tags(["email", "notification"])
```

### 3. Structure Memory Content

```ruby
# Store structured data as JSON
preference_data = {
  theme: "dark",
  notifications: true,
  language: "en"
}

manager.store_memory(
  preference_data.to_json,
  user_id: "user123",
  tags: ["preferences", "user_settings"]
)
```

### 4. Handle Memory Retrieval Gracefully

```ruby
def get_user_preference(memory_id)
  memory = DSPy::Memory.manager.get_memory(memory_id)
  return memory&.content || "default_value"
end

# Or with error handling
def get_user_preference(memory_id)
  memory = DSPy::Memory.manager.get_memory(memory_id)
  memory ? memory.content : "default_value"
rescue => e
  logger.warn("Failed to retrieve memory: #{e.message}")
  "default_value"
end
```

## Testing Memory

### Test Memory Operations

```ruby
RSpec.describe "Memory operations" do
  before do
    DSPy::Memory.reset!  # Clear memory for each test
  end
  
  it "stores and retrieves memories" do
    record = DSPy::Memory.manager.store_memory(
      "test_value",
      user_id: "test_user",
      tags: ["test"]
    )
    
    memory = DSPy::Memory.manager.get_memory(record.id)
    expect(memory.content).to eq("test_value")
    expect(memory.tags).to include("test")
  end
end
```

### Test Agents with Memory

```ruby
RSpec.describe "Agent with memory" do
  let(:memory_tools) { DSPy::Tools::MemoryToolset.to_tools }
  let(:agent) { DSPy::ReAct.new(TestSignature, tools: memory_tools) }
  
  before do
    DSPy::Memory.reset!
  end
  
  it "can store and recall information" do
    # Agent stores information
    agent.call(query: "Remember my name is John")
    
    # Agent recalls information
    result = agent.call(query: "What is my name?")
    expect(result.response).to include("John")
  end
end
```

## Limitations

- **Storage**: Default in-memory storage is not persistent across process restarts
- **Concurrency**: Memory operations are not thread-safe by default
- **Search**: Text search is basic pattern matching, not semantic search
- **Scaling**: Large memory stores may impact performance

For production use with persistent storage, implement a custom storage backend using your preferred database or storage system.

## Next Steps

- Learn about [Toolsets](../toolsets) to understand how memory tools work
- See [Advanced Memory Systems](../../advanced/memory-systems) for compaction and optimization
- Read about [Stateful Agents](../../advanced/stateful-agents) for production patterns
