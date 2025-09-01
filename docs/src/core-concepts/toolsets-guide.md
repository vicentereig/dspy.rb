---
layout: docs
name: Toolsets Guide
description: Comprehensive guide to building and using toolsets for agent workflows
date: 2025-07-11 00:00:00 +0000
last_modified_at: 2025-08-13 00:00:00 +0000
---
# Toolsets

DSPy.rb's Toolset pattern lets you group related tools in a single class. Instead of creating separate tool classes for each operation, you can expose multiple methods from one class as individual tools.

## When to Use Toolsets

Use toolsets when you have related operations that share state or logic:

- **Memory operations** - store, retrieve, search, delete
- **File operations** - read, write, list, delete
- **API clients** - get, post, put, delete
- **Database operations** - query, insert, update, delete

## Basic Usage

```ruby
class MyToolset < DSPy::Tools::Toolset
  toolset_name "my_tools"
  
  tool :operation_one, description: "Does something"
  tool :operation_two, description: "Does something else"
  
  def operation_one(input:)
    # Implementation
  end
  
  def operation_two(value:, optional: nil)
    # Implementation
  end
end

# Use with ReAct agent
toolset = MyToolset.new
agent = DSPy::ReAct.new(
  signature: MySignature,
  tools: toolset.class.to_tools
)
```

## Memory Toolset Example

The included `MemoryToolset` shows how to implement a working toolset:

```ruby
memory = DSPy::Tools::MemoryToolset.new

# The LLM sees these individual tools:
# - memory_store
# - memory_retrieve
# - memory_search
# - memory_list
# - memory_update
# - memory_delete
# - memory_clear
# - memory_count
# - memory_get_metadata

agent = DSPy::ReAct.new(
  signature: QASignature,
  tools: memory.class.to_tools
)
```

## How It Works

1. **Toolset class** defines methods and exposes them as tools
2. **ToolProxy** wraps each method to act like a standard tool
3. **Schema generation** uses Sorbet signatures to create JSON schemas
4. **ReAct integration** works with existing agents

## DSL Methods

### `toolset_name(name)`

Sets the prefix for generated tool names:

```ruby
class DatabaseToolset < DSPy::Tools::Toolset
  toolset_name "db"
  
  tool :query  # Creates tool named "db_query"
end
```

### `tool(method_name, options)`

Exposes a method as a tool:

```ruby
tool :search, 
  tool_name: "custom_search",  # Override default name
  description: "Search for items"
```

## Type Safety

Methods use Sorbet signatures for automatic schema generation:

```ruby
sig { params(key: String, value: String, tags: T.nilable(T::Array[String])).returns(String) }
def store(key:, value:, tags: nil)
  # Implementation
end
```

This generates:
```json
{
  "parameters": {
    "properties": {
      "key": { "type": "string" },
      "value": { "type": "string" },
      "tags": { "type": "array", "items": { "type": "string" } }
    },
    "required": ["key", "value"]
  }
}
```

## Memory Operations

The `MemoryToolset` provides these operations:

- `store(key:, value:, tags: nil)` - Store key-value pairs with optional tags
- `retrieve(key:)` - Get value by key
- `search(pattern:, in_keys: true, in_values: true)` - Pattern-based search
- `list_keys()` - List all keys
- `update(key:, value:)` - Update existing memory
- `delete(key:)` - Delete by key
- `clear()` - Remove all memories
- `count()` - Count stored items
- `get_metadata(key:)` - Get metadata (timestamps, access count)

## LLM Usage

The LLM interacts with each method as a separate tool:

```json
{
  "thought": "I need to store this information",
  "action": "memory_store",
  "action_input": {
    "key": "user_preference",
    "value": "dark mode",
    "tags": ["ui", "preferences"]
  }
}
```

## Testing

Test toolsets like regular Ruby classes:

```ruby
RSpec.describe MyToolset do
  let(:toolset) { described_class.new }
  
  it "performs operations" do
    result = toolset.operation_one(input: "test")
    expect(result).to eq("expected")
  end
  
  it "generates correct tools" do
    tools = described_class.to_tools
    expect(tools.map(&:name)).to include("my_tools_operation_one")
  end
end
```

## Limitations

- Methods must use keyword arguments for schema generation
- Each method becomes a separate tool (no method chaining)
- Shared state is isolated per toolset instance

## Next Steps

The toolset pattern is designed to support the planned memory system in issue #21. Future enhancements will include:

- Instrumentation events for tool usage
- Persistence backends for memory
- Context engineering features
- Auto-compaction for memory optimization

But those features don't exist yet. For now, you get in-memory storage with the operations listed above.

## Design Decisions

**Explicit Tool Exposure**: The `tool` DSL requires explicit method declaration rather than auto-exposing all public methods. This ensures:
- Clear documentation for each tool via the `description` parameter
- Intentional tool interface design
- Proper schema descriptions for LLM consumption
- Type safety through Sorbet signatures