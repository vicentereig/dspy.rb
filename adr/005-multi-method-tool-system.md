# ADR-005: Multi-Method Tool System (Toolsets)

**Status**: Proposed  
**Date**: 2025-07-21  
**Author**: Vicente Reig

## Context

Currently, DSPy.rb's tool system supports single-method tools where each tool class has one `call` method. This works well for simple operations but becomes cumbersome when you want to expose multiple related operations (e.g., memory operations: store, retrieve, list, clear, search).

The current approach requires creating separate tool classes for each operation, leading to:
- Boilerplate code duplication
- Harder to maintain related functionality
- No shared state between related tools
- Verbose tool registration

## Decision

Implement a "Toolset" pattern that allows exposing multiple methods from a single class as individual tools to LLMs. This pattern is inspired by Rails controllers where multiple actions are grouped in one controller.

### Key Design Elements:

1. **Base Toolset Class**: A new `DSPy::Tools::Toolset` base class that provides:
   - DSL for exposing methods as tools (`tool :method_name`)
   - Automatic schema generation from Sorbet signatures
   - Method-to-tool conversion via `to_tools`

2. **ToolProxy Wrapper**: Internal class that wraps each method as an individual tool:
   - Maintains reference to the toolset instance (shared state)
   - Delegates calls to the appropriate method
   - Provides tool metadata (name, description, schema)

3. **Naming Convention**: Tools are named as `{toolset_name}_{method_name}`:
   - `memory_store`, `memory_retrieve`, `memory_list`, etc.
   - Customizable via DSL options

4. **Integration**: Seamless integration with existing tool infrastructure:
   - ReAct agents accept arrays of tools from `to_tools`
   - Each method appears as a separate tool to the LLM
   - Maintains backward compatibility with single-method tools

### Implementation Example:

```ruby
class MemoryToolset < DSPy::Tools::Toolset
  toolset_name "memory"
  
  tool :store, description: "Store a key-value pair in memory"
  tool :retrieve, description: "Retrieve a value by key from memory"
  tool :list_keys, tool_name: "memory_list", description: "List all stored keys"
  
  sig { params(key: String, value: String).returns(String) }
  def store(key:, value:)
    @memory ||= {}
    @memory[key] = value
    "Stored '#{key}' successfully"
  end
  
  sig { params(key: String).returns(T.nilable(String)) }
  def retrieve(key:)
    @memory ||= {}
    @memory[key]
  end
  
  sig { returns(T::Array[String]) }
  def list_keys
    @memory ||= {}
    @memory.keys
  end
end

# Usage
memory = MemoryToolset.new
tools = memory.class.to_tools  # Returns array of ToolProxy instances

agent = DSPy::ReAct.new(
  signature: MySignature,
  tools: tools  # LLM sees: memory_store, memory_retrieve, memory_list
)
```

## Consequences

### Positive:
- **Reduced Boilerplate**: One class can expose multiple related tools
- **Shared State**: Tools can share instance variables (e.g., @memory)
- **Better Organization**: Related functionality grouped together
- **Type Safety**: Leverages existing Sorbet integration
- **Familiar Pattern**: Similar to Rails controllers
- **Backward Compatible**: Existing single-method tools continue to work
- **Flexible**: Can expose some or all methods, with custom naming

### Negative:
- **Additional Complexity**: New base class and proxy pattern to understand
- **Naming Collisions**: Need to ensure tool names are unique across toolsets
- **State Management**: Shared state between tools needs careful consideration
- **Learning Curve**: Developers need to understand when to use Tool vs Toolset

### Neutral:
- **Performance**: Minimal overhead from proxy pattern
- **Testing**: Each toolset is a regular Ruby class, testable as usual
- **Documentation**: Requires updating docs to explain both patterns

## Implementation Plan

1. Create the `Toolset` base class with `tool` DSL
2. Implement the `ToolProxy` wrapper class
3. Update `ReAct` agent to handle arrays of tools from `to_tools`
4. Add comprehensive tests for multi-method toolsets
5. Create example toolsets (Memory, FileSystem, Database)
6. Update documentation with usage examples
7. Consider auto-exposure pattern for simpler cases

## Alternatives Considered

1. **Module Inclusion**: Use modules to share functionality
   - Rejected: Doesn't solve the multiple tool registration problem
   
2. **Tool Registry**: Central registry for all tools
   - Rejected: More complex, breaks encapsulation
   
3. **Convention-based**: Auto-expose all public methods
   - Not rejected: Could be added as an option later

## References

- Current tool implementation: `lib/dspy/tools/base.rb`
- ReAct agent: `lib/dspy/agents/react.rb`
- Similar patterns in Rails ActionController