---
layout: docs
name: Toolsets
description: Group related tools in a single class for agent integration
breadcrumb:
- name: Core Concepts
  url: "/core-concepts/"
- name: Toolsets
  url: "/core-concepts/toolsets/"
nav:
  prev:
    name: Memory
    url: "/core-concepts/memory/"
  next:
    name: Predictors
    url: "/core-concepts/predictors/"
date: 2025-07-11 00:00:00 +0000
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
  extend T::Sig

  toolset_name "my_tools"

  tool :operation_one, description: "Does something"
  tool :operation_two, description: "Does something else"

  sig { params(input: String).returns(String) }
  def operation_one(input:)
    # Implementation
  end

  sig { params(value: String, optional: T.nilable(String)).returns(String) }
  def operation_two(value:, optional: nil)
    # Implementation
  end
end

# Use with ReAct agent
toolset = MyToolset.new
agent = DSPy::ReAct.new(
  MySignature,
  tools: toolset.class.to_tools
)
```

**Why Sorbet Signatures Matter**: Type signatures (`sig { ... }`) enable [DSPy.rb](https://github.com/vicentereig/dspy.rb) to generate accurate JSON schemas that describe your tools to the LLM. This dramatically improves the LLM's ability to use tools correctly by:
- Providing precise parameter types and descriptions
- Indicating which parameters are required vs optional
- Supporting rich types (enums, structs, arrays, unions)
- Preventing runtime errors from type mismatches

## Memory Toolset Example

The included `MemoryToolset` shows how to implement a working toolset:

```ruby
# Define a signature for question-answering
class QuestionAnswerSignature < DSPy::Signature
  description "Answer questions using available memory tools"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

# Create memory toolset instance
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

# Create ReAct agent with signature as positional argument
agent = DSPy::ReAct.new(
  QuestionAnswerSignature,
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

DSPy.rb supports a comprehensive range of Sorbet types for tools and toolsets with automatic JSON schema generation and type coercion:

### Basic Types

```ruby
sig { params(
  text: String,
  count: Integer,
  score: Float,
  enabled: T::Boolean,
  threshold: Numeric
).returns(String) }
def analyze(text:, count:, score:, enabled:, threshold:)
  # All basic types are fully supported
end
```

### Enums

Define and use enums directly in tool signatures:

```ruby
class Priority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
    Critical = new('critical')
  end
end

class Status < T::Enum
  enums do
    Pending = new('pending')
    InProgress = new('in-progress')
    Completed = new('completed')
  end
end

sig { params(priority: Priority, status: Status).returns(String) }
def update_task(priority:, status:)
  "Updated to #{priority.serialize} priority with #{status.serialize} status"
end
```

LLM calls get converted automatically:
```json
{
  "action": "update_task",
  "action_input": {
    "priority": "critical",
    "status": "in-progress"
  }
}
```

### Structs

Use T::Struct for complex data structures:

```ruby
class TaskMetadata < T::Struct
  prop :id, String
  prop :priority, Priority
  prop :tags, T::Array[String]
  prop :estimated_hours, T.nilable(Float), default: nil
end

class TaskRequest < T::Struct
  prop :title, String
  prop :description, String
  prop :status, Status
  prop :metadata, TaskMetadata
  prop :assignees, T::Array[String]
end

sig { params(task: TaskRequest).returns(String) }
def create_task(task:)
  "Created: #{task.title} (#{task.status.serialize})"
end
```

### Collections

Arrays and hashes with typed elements:

```ruby
sig { params(
  tags: T::Array[String],
  priorities: T::Array[Priority],
  config: T::Hash[String, T.any(String, Integer, Float)],
  mappings: T::Hash[String, Priority]
).returns(String) }
def configure(tags:, priorities:, config:, mappings:)
  # Typed collections with automatic validation
end
```

### Nilable Types

Optional parameters with `T.nilable()`:

```ruby
sig { params(
  required_field: String,
  optional_field: T.nilable(String),
  optional_enum: T.nilable(Priority),
  optional_array: T.nilable(T::Array[String])
).returns(String) }
def process(required_field:, optional_field: nil, optional_enum: nil, optional_array: nil)
  # Only required_field is mandatory in the JSON schema
end
```

### Union Types

Multiple type options with `T.any()`:

```ruby
sig { params(
  value: T.any(String, Integer, Float),
  action: T.any(Priority, Status)
).returns(String) }
def handle_flexible(value:, action:)
  # Accepts multiple types with automatic coercion
end
```

## Supported Sorbet Types Reference

| Sorbet Type | JSON Schema | Auto Conversion | Notes |
|-------------|-------------|-----------------|-------|
| `String` | `{"type": "string"}` | ✅ | Basic string values |
| `Integer` | `{"type": "integer"}` | ✅ | Whole numbers |
| `Float` | `{"type": "number"}` | ✅ | Decimal numbers |
| `Numeric` | `{"type": "number"}` | ✅ | Integer or Float |
| `T::Boolean` | `{"type": "boolean"}` | ✅ | true/false values |
| `T::Enum` | `{"type": "string", "enum": [...]}` | ✅ | Automatic deserialization |
| `T::Struct` | `{"type": "object", "properties": {...}}` | ✅ | Nested object conversion |
| `T::Array[Type]` | `{"type": "array", "items": {...}}` | ✅ | Typed array elements |
| `T::Hash[K,V]` | `{"type": "object", "additionalProperties": {...}}` | ✅ | Key-value constraints |
| `T.nilable(Type)` | `{"type": [original, "null"]}` | ✅ | Optional parameters |
| `T.any(T1, T2)` | `{"oneOf": [{...}, {...}]}` | ✅ | Union type handling |
| `T.class_of(Class)` | `{"type": "string"}` | ✅ | Class name strings |

## Schema Generation Examples

Basic enum tool generates:
```json
{
  "type": "function", 
  "function": {
    "name": "update_task",
    "parameters": {
      "type": "object",
      "properties": {
        "priority": {
          "type": "string",
          "enum": ["low", "medium", "high", "critical"],
          "description": "Parameter priority"
        },
        "status": {
          "type": "string", 
          "enum": ["pending", "in-progress", "completed"],
          "description": "Parameter status"
        }
      },
      "required": ["priority", "status"]
    }
  }
}
```

Complex struct tool generates:
```json
{
  "type": "function",
  "function": {
    "name": "create_task", 
    "parameters": {
      "type": "object",
      "properties": {
        "task": {
          "type": "object",
          "properties": {
            "_type": {"type": "string", "const": "TaskRequest"},
            "title": {"type": "string"},
            "description": {"type": "string"},
            "status": {
              "type": "string",
              "enum": ["pending", "in-progress", "completed"]
            },
            "metadata": {
              "type": "object",
              "properties": {
                "_type": {"type": "string", "const": "TaskMetadata"},
                "id": {"type": "string"},
                "priority": {
                  "type": "string", 
                  "enum": ["low", "medium", "high", "critical"]
                },
                "tags": {"type": "array", "items": {"type": "string"}},
                "estimated_hours": {"type": ["number", "null"]}
              }
            }
          }
        }
      },
      "required": ["task"]
    }
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

The toolset pattern works with the implemented memory system. The `MemoryToolset` provides basic in-memory storage with operations like store, retrieve, search, and metadata tracking. 

For production use, consider implementing custom toolsets that integrate with your preferred storage backend (database, Redis, etc.) by extending the `Toolset` base class.

## Design Decisions

**Explicit Tool Exposure**: The `tool` DSL requires explicit method declaration rather than auto-exposing all public methods. This ensures:
- Clear documentation for each tool via the `description` parameter
- Intentional tool interface design
- Proper schema descriptions for LLM consumption
- Type safety through Sorbet signatures