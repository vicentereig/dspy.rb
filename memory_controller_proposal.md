# Multi-Method Tool System Proposal for DSPy.rb

## Overview

This proposal extends DSPy.rb's tool system to support "Toolsets" (or "Tool Controllers") - classes where multiple methods can be exposed as individual tools to LLMs, similar to how Rails controllers expose multiple actions.

## Design Goals

1. **Multiple tools from one class** - Each public method becomes an individually callable tool
2. **Preserve Sorbet integration** - Automatic schema generation from type signatures
3. **Backward compatible** - Existing single-method tools continue to work
4. **LLM-friendly** - Each method appears as a separate tool with clear naming
5. **Flexible naming** - Support custom tool naming conventions

## Proposed Implementation

### 1. Base Toolset Class

```ruby
module DSPy
  module Tools
    class Toolset
      extend T::Sig
      extend T::Helpers
      
      class << self
        extend T::Sig
        
        # DSL to expose methods as tools
        sig { params(method_name: Symbol, tool_name: T.nilable(String), description: T.nilable(String)).void }
        def expose_tool(method_name, tool_name: nil, description: nil)
          @exposed_tools ||= {}
          @exposed_tools[method_name] = {
            tool_name: tool_name || "#{toolset_name}_#{method_name}",
            description: description || "#{method_name} operation"
          }
        end
        
        # DSL to set the toolset name prefix
        sig { params(name: String).void }
        def toolset_name(name = nil)
          @toolset_name = name if name
          @toolset_name || self.name.split('::').last.gsub(/Toolset$/, '').downcase
        end
        
        # Get all exposed tools as individual tool instances
        sig { returns(T::Array[ToolProxy]) }
        def to_tools
          instance = new
          exposed_tools.map do |method_name, config|
            ToolProxy.new(instance, method_name, config[:tool_name], config[:description])
          end
        end
        
        sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
        def exposed_tools
          @exposed_tools || {}
        end
        
        # Generate schema for a specific method
        sig { params(method_name: Symbol).returns(T::Hash[Symbol, T.untyped]) }
        def schema_for_method(method_name)
          method_obj = instance_method(method_name)
          sig_info = T::Utils.signature_for_method(method_obj)
          
          # Reuse the schema generation logic from Base
          Base.call_schema_from_sig(sig_info)
        end
      end
      
      # Inner class that wraps a method as a tool
      class ToolProxy < Base
        sig { params(instance: Toolset, method_name: Symbol, tool_name: String, description: String).void }
        def initialize(instance, method_name, tool_name, description)
          @instance = instance
          @method_name = method_name
          @tool_name_override = tool_name
          @description_override = description
        end
        
        sig { override.returns(String) }
        def name
          @tool_name_override
        end
        
        sig { override.returns(String) }
        def description
          @description_override
        end
        
        sig { override.returns(String) }
        def schema
          schema_obj = @instance.class.schema_for_method(@method_name)
          tool_info = {
            name: name,
            description: description,
            parameters: schema_obj
          }
          JSON.generate(tool_info)
        end
        
        sig { override.params(args_json: T.untyped).returns(T.untyped) }
        def dynamic_call(args_json)
          # Parse and validate arguments using existing logic
          schema = @instance.class.schema_for_method(@method_name)
          
          if schema[:properties].empty?
            @instance.send(@method_name)
          else
            # ... (reuse argument parsing logic from Base)
            kwargs = parse_and_convert_args(args_json, schema)
            @instance.send(@method_name, **kwargs)
          end
        rescue => e
          "Error: #{e.message}"
        end
      end
    end
  end
end
```

### 2. Example Usage: Memory Toolset

```ruby
module DSPy
  module Tools
    class MemoryToolset < Toolset
      extend T::Sig
      
      toolset_name "memory"
      
      # Expose methods as tools with optional custom names
      expose_tool :store, description: "Store a key-value pair in memory"
      expose_tool :retrieve, description: "Retrieve a value by key from memory"
      expose_tool :list_keys, tool_name: "memory_list", description: "List all stored keys"
      expose_tool :clear, description: "Clear all stored memories"
      expose_tool :search, description: "Search memories by pattern"
      
      sig { void }
      def initialize
        @memory = {}
      end
      
      sig { params(key: String, value: String, tags: T.nilable(T::Array[String])).returns(String) }
      def store(key:, value:, tags: nil)
        @memory[key] = { value: value, tags: tags || [], timestamp: Time.now }
        "Stored '#{key}' successfully"
      end
      
      sig { params(key: String).returns(T.nilable(String)) }
      def retrieve(key:)
        entry = @memory[key]
        entry ? entry[:value] : nil
      end
      
      sig { returns(T::Array[String]) }
      def list_keys
        @memory.keys
      end
      
      sig { returns(String) }
      def clear
        count = @memory.size
        @memory.clear
        "Cleared #{count} memories"
      end
      
      sig { params(pattern: String, in_keys: T::Boolean, in_values: T::Boolean).returns(T::Array[T::Hash[Symbol, String]]) }
      def search(pattern:, in_keys: true, in_values: true)
        results = []
        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        
        @memory.each do |key, entry|
          match = (in_keys && key.match?(regex)) || (in_values && entry[:value].match?(regex))
          results << { key: key, value: entry[:value] } if match
        end
        
        results
      end
    end
  end
end
```

### 3. Integration with ReAct Agent

```ruby
# Create a memory toolset
memory = DSPy::Tools::MemoryToolset.new

# Convert to individual tools
memory_tools = memory.class.to_tools

# Pass to ReAct agent
agent = DSPy::ReAct.new(
  signature: MySignature,
  tools: [
    existing_calculator_tool,
    *memory_tools  # Spreads all memory methods as individual tools
  ]
)

# The LLM will see these tools:
# - calculator
# - memory_store
# - memory_retrieve  
# - memory_list
# - memory_clear
# - memory_search
```

### 4. JSON Schema Output Example

When the LLM requests tool schemas, each method appears as a separate tool:

```json
[
  {
    "name": "memory_store",
    "description": "Store a key-value pair in memory",
    "parameters": {
      "type": "object",
      "properties": {
        "key": { "type": "string", "description": "Parameter key" },
        "value": { "type": "string", "description": "Parameter value" },
        "tags": { "type": "array", "items": { "type": "string" }, "description": "Parameter tags (optional)" }
      },
      "required": ["key", "value"]
    }
  },
  {
    "name": "memory_retrieve",
    "description": "Retrieve a value by key from memory",
    "parameters": {
      "type": "object",
      "properties": {
        "key": { "type": "string", "description": "Parameter key" }
      },
      "required": ["key"]
    }
  }
]
```

### 5. LLM Usage Example

The LLM would use these tools like:

```json
{
  "thought": "I need to store the user's preference",
  "action": "memory_store",
  "action_input": {
    "key": "user_preference_theme",
    "value": "dark",
    "tags": ["preferences", "ui"]
  }
}
```

```json
{
  "thought": "Let me retrieve the stored preference",
  "action": "memory_retrieve", 
  "action_input": {
    "key": "user_preference_theme"
  }
}
```

### 6. Alternative: Automatic Exposure Pattern

For simpler cases, we could auto-expose all public methods:

```ruby
class AutoMemoryToolset < Toolset
  toolset_name "auto_memory"
  
  # Auto-expose all public methods except inherited ones
  def self.inherited(subclass)
    super
    subclass.instance_methods(false).each do |method_name|
      next if method_name.to_s.start_with?('_')
      subclass.expose_tool(method_name)
    end
  end
end
```

### 7. Benefits of This Design

1. **Familiar Pattern** - Similar to Rails controllers with actions
2. **Organized** - Group related tools in one class
3. **Type Safe** - Leverages existing Sorbet integration
4. **Flexible** - Can expose some or all methods
5. **Testable** - Each toolset is a regular Ruby class
6. **Instrumentation Ready** - Each tool call can be instrumented separately

### 8. Implementation Steps

1. Create the `Toolset` base class with `expose_tool` DSL
2. Implement the `ToolProxy` wrapper class
3. Update `ReAct` agent to handle arrays of tools from `to_tools`
4. Add tests for multi-method toolsets
5. Create example toolsets (Memory, FileSystem, Database, etc.)
6. Update documentation

This design maintains backward compatibility while enabling powerful multi-method tool patterns for LLM interactions.