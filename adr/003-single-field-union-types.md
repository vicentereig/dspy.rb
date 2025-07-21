# ADR-003: Single-Field Union Types with Embedded Type Information

**Status**: Proposed  
**Date**: 2025-07-21  
**Author**: Vicente Reig

## Context

DSPy.rb currently requires developers to use two fields for union types - a discriminator field (usually an enum) and the actual union field. This pattern, while functional, creates unnecessary complexity:

```ruby
# Current pattern - requires two fields
output do
  const :action_type, ActionType      # Discriminator
  const :action_details, T.any(...)   # Union
end
```

Developers have expressed the desire for a simpler API where they can use a single `T.any(...)` field that handles both serialization (for inputs) and deserialization (for outputs) automatically.

## Decision

We will implement a single-field union type pattern using embedded type information within each struct. This approach eliminates the need for external discriminator fields while maintaining type safety and LLM compatibility.

## Solution Design

### 1. Automatic Type Information

DSPy automatically adds type information during serialization using the struct's class name. No explicit type fields needed!

```ruby
# Clean struct definitions - no type field required
class SpawnTask < T::Struct
  const :description, String
  const :priority, String
end

class CompleteTask < T::Struct
  const :task_id, String
  const :result, String
end

class Continue < T::Struct
  const :reason, String
end

# During serialization, DSPy automatically adds:
# {
#   "_type": "SpawnTask",
#   "description": "...",
#   "priority": "..."
# }
```

For namespaced classes, the full class name is used:
```ruby
module AgentActions
  class SpawnTask < T::Struct
    const :description, String
    const :priority, String
  end
end

# Serializes to:
# {
#   "_type": "AgentActions::SpawnTask",
#   "description": "...",
#   "priority": "..."
# }
```

### 2. Clean Single-Field Usage

Developers can now use a single union field:

```ruby
class AgentDecisionSignature < DSPy::Signature
  description "Agent decision making"
  
  output do
    const :action, T.any(SpawnTask, CompleteTask, Continue)
    const :confidence, Float
  end
end
```

### 3. JSON Schema Generation

The system generates JSON schemas with const constraints for the automatically added `_type` field:

```json
{
  "action": {
    "oneOf": [
      {
        "type": "object",
        "properties": {
          "_type": { "const": "SpawnTask" },
          "description": { "type": "string" },
          "priority": { "type": "string" }
        },
        "required": ["_type", "description", "priority"],
        "additionalProperties": false
      },
      {
        "type": "object",
        "properties": {
          "_type": { "const": "CompleteTask" },
          "task_id": { "type": "string" },
          "result": { "type": "string" }
        },
        "required": ["_type", "task_id", "result"],
        "additionalProperties": false
      },
      {
        "type": "object",
        "properties": {
          "_type": { "const": "Continue" },
          "reason": { "type": "string" }
        },
        "required": ["_type", "reason"],
        "additionalProperties": false
      }
    ]
  }
}
```

### 4. Automatic Serialization/Deserialization

#### For Outputs (LLM → Ruby)
When deserializing JSON from an LLM:
1. Extract the `_type` field from the JSON
2. Find the matching class from the union types
3. Instantiate the struct with the remaining fields
4. Fall back to structure-based matching if no `_type` field exists

```ruby
def deserialize_union(json, union_types)
  type_name = json["_type"]
  
  # Find matching class (handles namespaced names)
  struct_class = union_types.find do |type|
    type.name == type_name || type.name.end_with?("::#{type_name}")
  end
  
  # Create instance without _type field
  struct_class.new(json.except("_type"))
end
```

#### For Inputs (Ruby → LLM)
When serializing Ruby objects for an LLM:
1. Add `_type` field with the class name
2. Include all struct fields
3. The JSON schema guides the LLM to include `_type` in responses

### 5. Type Naming Conventions

The `_type` field uses the full class name to ensure uniqueness:

1. **Simple Classes**: Use the class name directly
   - `SpawnTask` → `"SpawnTask"`
   - `CompleteTask` → `"CompleteTask"`

2. **Namespaced Classes**: Use the full qualified name
   - `AgentActions::SpawnTask` → `"AgentActions::SpawnTask"`
   - `Events::UserCreated` → `"Events::UserCreated"`

3. **Matching Strategy**: When deserializing, DSPy matches flexibly:
   ```ruby
   # Given _type: "SpawnTask", matches:
   - SpawnTask (exact match)
   - AgentActions::SpawnTask (ends with ::SpawnTask)
   - Tasks::SpawnTask (ends with ::SpawnTask)
   ```

### 6. Union Type Validation

Since type information is automatic, validation focuses on ensuring clean serialization:

```ruby
class DSPy::Signature
  def self.validate_union_types!
    output_fields.each do |name, type|
      next unless is_union_type?(type)
      
      type.types.each do |struct_type|
        next unless struct_type < T::Struct
        
        # Ensure no user-defined _type field conflicts
        if struct_type.props.key?(:_type)
          raise DSPy::ValidationError, <<~ERROR
            Union type validation failed for field '#{name}'.
            
            The struct #{struct_type} has a '_type' field which conflicts with DSPy's automatic type handling.
            
            Please rename the field to something else (e.g., 'kind', 'category', 'type_name').
          ERROR
        end
        
        # Warn if struct name might cause issues
        if struct_type.name.nil? || struct_type.name.empty?
          raise DSPy::ValidationError, <<~ERROR
            Union type validation failed for field '#{name}'.
            
            Anonymous struct detected in union. All structs must be named classes.
          ERROR
        end
      end
    end
  end
end
```

This validation ensures:
- No conflicts with the automatic `_type` field
- All structs are properly named for serialization
- Clear error messages during development

### 7. Fallback Strategies

When type field is missing or ambiguous during deserialization:

1. **Unique Field Detection**: Match based on unique required fields
2. **Score-Based Matching**: Score each type by matching fields
3. **First Valid Match**: Try instantiating each type until success
4. **Clear Error Messages**: Provide helpful debugging information

## Implementation Plan

### Phase 1: Core Implementation
1. Update `DSPy::Signature` to generate const constraints for type fields
2. Enhance `DSPy::Prediction` to use embedded type for deserialization
3. Add validation to ensure union structs have type fields
4. Implement union type validation with helpful error messages

### Phase 2: Strategy Updates
1. **OpenAI**: Leverage const constraints in structured output mode
2. **Anthropic**: Add examples with type fields in prompts
3. **Enhanced Prompting**: Include explicit type field instructions

### Phase 3: Developer Experience
1. Add helpful error messages for missing type fields
2. Create migration guide from two-field to single-field pattern
3. Update documentation with best practices

## Example: Complete Agent System

```ruby
# Define action structs - no type fields needed!
module AgentActions
  class Search < T::Struct
    const :query, String
    const :max_results, Integer, default: 10
  end
  
  class Analyze < T::Struct
    const :data, T::Array[String]
    const :method, String
  end
  
  class Report < T::Struct
    const :findings, String
    const :confidence, Float
  end
end

# Use single union field
class ResearchAgentSignature < DSPy::Signature
  description "Research agent that can search, analyze, and report"
  
  input do
    const :task, String
    const :context, T::Hash[String, T.untyped]
  end
  
  output do
    const :action, T.any(
      AgentActions::Search,
      AgentActions::Analyze,
      AgentActions::Report
    )
    const :reasoning, String
  end
end

# Clean usage
agent = DSPy::Predict.new(ResearchAgentSignature)
result = agent.call(
  task: "Find information about climate change",
  context: { priority: "high" }
)

# Automatic deserialization to correct type
case result.action
when AgentActions::Search
  puts "Searching for: #{result.action.query}"
when AgentActions::Analyze
  puts "Analyzing #{result.action.data.length} items"
when AgentActions::Report
  puts "Report: #{result.action.findings}"
end
```

## Benefits

1. **Zero Boilerplate**: No type fields to define or maintain
2. **Automatic**: Type information added transparently during serialization
3. **Clean Structs**: Focus on domain data, not framework requirements
4. **Type Safe**: Full Sorbet type checking support
5. **LLM Compatible**: Works with all providers through JSON Schema
6. **DRY**: Class name is the single source of truth for type information
7. **Intuitive**: Just define your structs and use them in unions

## Trade-offs

1. **Reserved Field**: `_type` becomes a reserved field name in serialized JSON
2. **Class Naming**: Struct class names become part of the API contract
3. **Migration Effort**: Existing code using two-field pattern needs updates

## Alternatives Considered

1. **External Discriminator** (current): Works but requires two fields
2. **Explicit Type Fields**: Requiring developers to add type fields - too much boilerplate
3. **Type Inference Only**: Too fragile, ambiguous with similar structs
4. **Custom Discriminator Names**: Allowing `type`, `kind`, etc. - too much configuration

## References

- TypeScript Discriminated Unions: https://www.typescriptlang.org/docs/handbook/2/narrowing.html#discriminated-unions
- JSON Schema oneOf with const: https://json-schema.org/understanding-json-schema/reference/combining.html
- GraphQL Union Types: https://graphql.org/learn/schema/#union-types

## Decision Outcome

We will implement single-field union types with embedded type information as the primary pattern in DSPy.rb, making it the recommended approach for all new code.