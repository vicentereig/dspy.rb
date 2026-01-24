# ADR-018: Unified Tool Model — Signature + Module

**Status**: Proposed
**Date**: 2025-01-14
**Author**: Vicente Reig (with Claude)
**Supersedes**: ADR-005 (Multi-Method Tool System)

## Context

DSPy.rb currently has two parallel systems for defining structured AI operations:

1. **Signatures** — Input/output schemas for LLM-generated responses
2. **Tools** — Input schemas with code handlers for external operations

Both share the same fundamental pattern: a schema-driven contract that defines inputs, outputs, and semantic meaning. They both generate JSON Schema, they both guide LLM behavior, and they both transform structured input into structured output.

The key insight from analyzing MCP (Model Context Protocol) tools: **A DSPy Signature is like an MCP Tool where the LLM IS the handler.**

```
MCP Tool:        Schema → LLM reads → LLM invokes → Handler produces output
DSPy Signature:  Schema → LLM reads → LLM generates output directly
```

The only difference is who executes: external code or the LLM itself.

### Current Problems

1. **Dual systems** — `Tools::Base` and `Tools::Toolset` exist alongside `Signature`, with parallel schema generation logic
2. **Duplicated concepts** — Both extract Sorbet types to JSON Schema
3. **Different composition** — Tools use `ToolProxy`, Signatures use `Predict`
4. **No unified execution model** — Cannot easily swap between LLM and code implementations

## Decision

Unify tools and signatures into a **three-layer architecture**:

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: Tool Orchestrator (DSPy::Module)                      │
│  - Handles tool selection loop (like ReAct)                     │
│  - Decides which tool to call based on context                  │
│  - Manages conversation/iteration state                         │
└─────────────────────────────────────────────────────────────────┘
                              │ calls
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: Tool Module (DSPy::Module with signature binding)     │
│  - Encapsulates the "doing" of one tool                         │
│  - Selectable: LM, prompting technique (Predict, CoT, etc.)     │
│  - Can be LLM-backed OR code-backed                             │
└─────────────────────────────────────────────────────────────────┘
                              │ uses
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: Signature (Schema Contract)                           │
│  - Pure input/output definition                                 │
│  - No implementation, just types                                │
│  - Exports to JSON Schema / MCP format                          │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **One module = one signature** — Keep it simple. Compose multiple tools at orchestrator level.
2. **Tool name derived from signature class** — `SearchDocuments` → `"search_documents"`. Automatic, consistent.
3. **Module gains `signature` DSL** — Binds a signature to the module, enabling schema export.
4. **`forward` method** — Returns output matching the signature's output schema.

## Implementation

### Layer 1: Signature (unchanged)

```ruby
class SearchDocuments < DSPy::Signature
  description "Search legal documents by query"

  input do
    const :query, String
    const :filters, T.nilable(SearchFilters)
  end

  output do
    const :documents, T::Array[Document]
    const :total_count, Integer
  end
end
```

### Layer 2: Module with Signature Binding (NEW)

```ruby
# LLM-backed tool
class LLMSearchTool < DSPy::Module
  signature SearchDocuments  # Binds schema, derives tool_name

  def initialize(lm: nil)
    @predictor = DSPy::ChainOfThought.new(SearchDocuments, lm: lm)
  end

  def forward(query:, filters: nil)
    @predictor.call(query: query, filters: filters)
  end
end

# Code-backed tool
class APISearchTool < DSPy::Module
  signature SearchDocuments

  def initialize(index:)
    @index = index
  end

  def forward(query:, filters: nil)
    results = @index.search(query, filters: filters&.to_h)
    SearchDocuments.output_struct_class.new(
      documents: results,
      total_count: results.size
    )
  end
end

# Hybrid: LLM augments code
class SmartSearchTool < DSPy::Module
  signature SearchDocuments

  def initialize(index:, lm: nil)
    @index = index
    @query_expander = DSPy::Predict.new(ExpandQuery, lm: lm)
  end

  def forward(query:, filters: nil)
    expanded = @query_expander.call(query: query)
    results = @index.search(expanded.expanded_query)
    SearchDocuments.output_struct_class.new(
      documents: results,
      total_count: results.size
    )
  end
end
```

### Module DSL Additions

```ruby
class DSPy::Module
  class << self
    def signature(signature_class)
      @bound_signature = signature_class
    end

    def bound_signature
      @bound_signature
    end

    def tool_name
      bound_signature&.name&.underscore&.gsub("::", "_")
    end

    def tool_description
      bound_signature&.description
    end

    def input_schema
      bound_signature&.input_json_schema
    end

    def output_schema
      bound_signature&.output_json_schema
    end
  end

  def tool_name
    self.class.tool_name
  end

  def to_mcp_schema
    {
      name: tool_name,
      description: self.class.tool_description,
      inputSchema: self.class.input_schema
    }
  end
end
```

### Layer 3: Tool Orchestrator (Refactored ReAct)

```ruby
class DSPy::ToolOrchestrator < DSPy::Module
  def initialize(tools:, max_iterations: 10, lm: nil)
    @tools = tools.to_h { |t| [t.tool_name, t] }
    @selector = DSPy::Predict.new(SelectToolSignature, lm: lm)
    @synthesizer = DSPy::Predict.new(SynthesizeSignature, lm: lm)
    @max_iterations = max_iterations
  end

  def forward(task:)
    history = []

    @max_iterations.times do
      selection = @selector.call(
        task: task,
        available_tools: @tools.values.map(&:to_mcp_schema),
        history: history
      )

      break if selection.action == "finish"

      tool = @tools[selection.tool_name]
      result = tool.forward(**selection.tool_input.symbolize_keys)
      history << { tool: selection.tool_name, result: result }
    end

    @synthesizer.call(task: task, history: history)
  end
end
```

### Usage

```ruby
# Create tools (each picks its own LM/technique)
search_tool = APISearchTool.new(index: document_index)
summarize_tool = DSPy::Predict.new(SummarizeDocument, lm: fast_lm)
classify_tool = DSPy::ChainOfThought.new(ClassifyDocument, lm: smart_lm)

# Note: Predict and ChainOfThought could gain `signature` binding too

# Orchestrator manages the loop
agent = DSPy::ToolOrchestrator.new(
  tools: [search_tool, summarize_tool, classify_tool],
  lm: orchestrator_lm
)

result = agent.forward(task: "Find and summarize recent tax law changes")

# MCP export
tools.map(&:to_mcp_schema)
# => [{ name: "search_documents", inputSchema: {...} }, ...]
```

## Consequences

### Positive

- **Unified model** — One pattern for both LLM and code-backed operations
- **Composable** — Mix LLM and code within a single tool
- **Swappable** — Same signature, different implementations
- **MCP-compatible** — Direct export to MCP tool format
- **Selectable techniques** — Each tool picks its own LM and prompting approach
- **Testable** — Modules are regular Ruby classes

### Negative

- **Migration required** — Existing tools need conversion
- **Breaking change** — `Tools::Base` and `Tools::Toolset` deprecated
- **Learning curve** — New `signature` DSL on Module

### Neutral

- **ReAct refactor** — Becomes a thin wrapper around ToolOrchestrator
- **Documentation** — Needs update but clearer overall

## Migration Path

### Phase 1: Add `signature` DSL to Module
- Module gains `signature(klass)` class method
- Add `tool_name`, `to_mcp_schema` instance methods
- No breaking changes

### Phase 2: Create example tool modules
- Convert `MemoryToolset` to individual `MemoryStoreTool`, `MemoryRetrieveTool` modules
- Validate API ergonomics
- Write tests

### Phase 3: Refactor ReAct
- Accept Module-based tools alongside old tools
- Deprecation warning for `Tools::Base` format
- Eventually extract to `ToolOrchestrator`

### Phase 4: Cleanup
- Remove `lib/dspy/tools/base.rb`
- Remove `lib/dspy/tools/toolset.rb`
- Update all documentation

## What Gets Removed

| File | Reason |
|------|--------|
| `lib/dspy/tools/base.rb` | Replaced by Module + signature |
| `lib/dspy/tools/toolset.rb` | Replaced by multiple single-sig modules |
| `lib/dspy/tools/schema.rb` | Already in Signature |
| `ToolProxy` inner class | No longer needed |

## What Gets Migrated

| Current | New |
|---------|-----|
| `MemoryToolset` | `MemoryStoreTool`, `MemoryRetrieveTool`, etc. |
| `TextProcessingToolset` | Individual modules or inline |
| `GithubCliToolset` | Individual modules |
| ReAct tool loop | `ToolOrchestrator` module |

## Alternatives Considered

1. **Keep both systems** — Rejected: Unnecessary complexity, parallel concepts
2. **Signature with `perform` block** — Rejected: Mixes schema and implementation
3. **Multi-signature modules** — Rejected: Adds complexity, compose at orchestrator instead

## References

- ADR-005: Multi-Method Tool System (superseded)
- MCP Tool Specification: https://modelcontextprotocol.io/
- Current implementation: `lib/dspy/tools/`, `lib/dspy/signature.rb`
