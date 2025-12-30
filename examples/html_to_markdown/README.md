# HTML to Markdown AST Experiment

This example explores whether **structured AST output types** produce better Markdown conversion compared to simple **String → String** conversion.

## The Experiment

We compare multiple approaches for converting HTML to Markdown:

| Approach | Description | Output Type |
|----------|-------------|-------------|
| **A: Native JSON AST** | `structured_outputs: true` | `MarkdownDocument` struct |
| **B: BAML AST** | `schema_format: :baml` (enhanced prompting) | `MarkdownDocument` struct |
| **C: Direct String** | Simple string output | `String` |
| **D: Hierarchical** | Two-phase parsing (outline → fill) | `MarkdownDocument` struct |

## Key Findings (Updated December 2025)

### Issue #201 Fixed: OpenAI Native JSON Now Works

**Before**: OpenAI structured outputs failed with recursive schemas:
```
Invalid schema for response_format: reference to component '#/definitions/ASTNode' which was not found
```

**After**: DSPy.rb now generates `#/$defs/` format (JSON Schema draft-07+), making recursive schemas work with OpenAI and Gemini.

### Provider Comparison (Post-Fix)

| Provider + Mode | Recursive Schema? | Code Blocks | Headings | Overall |
|-----------------|-------------------|-------------|----------|---------|
| **OpenAI Native** | ✅ **Fixed!** | ✅ Correct | ✅ Correct | **Best for OpenAI** |
| **Anthropic BAML** | ✅ Yes | ✅ Correct | ✅ Correct | **Best for Anthropic** |
| **Anthropic Native** | ✅ Yes | ⚠️ May truncate | ✅ Correct | Good |
| **OpenAI BAML** | ✅ Yes | ✅ Correct | ⚠️ May lose text | Fallback |

### Token Consumption (Complex Article)

| Strategy | Input Tokens | Output Tokens | **Total** | Cost Ratio |
|----------|-------------|---------------|-----------|------------|
| **Direct String** | 1,767 | 454 | **2,221** | 1.0x |
| **BAML AST** | 1,505 | 2,329 | **3,834** | 1.7x |
| **Native JSON AST** | 2,229 | 3,168 | **5,397** | 2.4x |

## New Features Demonstrated

### 1. T::Struct Field Descriptions

DSPy.rb extends T::Struct to support field-level `description:` kwargs that flow to JSON Schema:

```ruby
class ASTNode < T::Struct
  const :node_type, NodeType, description: 'The type of node (heading, paragraph, etc.)'
  const :text, String, default: "", description: 'Text content of the node'
  const :level, Integer, default: 0  # No description - self-explanatory
  const :children, T::Array[ASTNode], default: []
end

# Access descriptions programmatically
ASTNode.field_descriptions[:node_type]  # => "The type of node (heading, paragraph, etc.)"
```

The generated JSON Schema includes these descriptions, helping LLMs understand field semantics.

### 2. Recursive Types with `$defs`

DSPy.rb now generates proper `#/$defs/` references for recursive types:

```json
{
  "type": "object",
  "properties": {
    "children": {
      "type": "array",
      "items": { "$ref": "#/$defs/ASTNode" }
    }
  },
  "$defs": {
    "ASTNode": { ... }
  }
}
```

This format is compatible with OpenAI, Gemini, and Anthropic structured outputs.

### 3. Hierarchical Parsing (Two-Phase)

For complex documents that may exceed token limits, use two-phase parsing:

```ruby
# Phase 1: Extract skeleton structure
class ParseOutline < DSPy::Signature
  description 'Extract block-level structure from HTML as a flat list of skeleton sections.'

  input do
    const :html, String
  end

  output do
    const :sections, T::Array[SkeletonSection]
  end
end

# Phase 2: Parse each section in detail
class ParseSection < DSPy::Signature
  description 'Parse a single HTML section into a detailed Markdown AST node.'

  input do
    const :html, String
    const :node_type, NodeType
  end

  output do
    const :node, ASTNode
  end
end

# Orchestrator
parser = HtmlToMarkdown::HierarchicalParser.new
document = parser.parse(complex_html)
```

### 4. Defaults Over Nilables

For OpenAI structured outputs compatibility, use `default: []` instead of `T.nilable(T::Array[...])`:

```ruby
# ✅ Good - works with OpenAI structured outputs
class ASTNode < T::Struct
  const :children, T::Array[ASTNode], default: []
  const :text, String, default: ""
end

# ❌ Bad - causes schema issues
class ASTNode < T::Struct
  const :children, T.nilable(T::Array[ASTNode])
  const :text, T.nilable(String)
end
```

## Recommendations

| Use Case | Recommended Approach |
|----------|---------------------|
| Simple HTML → MD conversion | **Direct String** (fastest, cheapest) |
| Need to validate/transform structure | **Native JSON AST** (now works!) |
| Complex documents hitting token limits | **Hierarchical parsing** |
| Fallback for any provider issues | **BAML AST** (most robust) |

## Files

```
html_to_markdown/
├── main.rb              # Runnable comparison experiment
├── types.rb             # NodeType enum + ASTNode struct (21 node types)
├── renderer.rb          # AST → Markdown string renderer
├── signatures.rb        # All signature definitions
├── hierarchical_parser.rb  # Two-phase parsing orchestrator
└── README.md            # This file
```

## Running the Experiment

```bash
# Run the comparison
ANTHROPIC_API_KEY=your-key ruby examples/html_to_markdown/main.rb

# Run tests (includes OpenAI native JSON tests)
bundle exec rspec spec/examples/html_to_markdown_spec.rb

# Run specific strategy tests
bundle exec rspec spec/examples/html_to_markdown_spec.rb -e "OpenAI Native JSON"
bundle exec rspec spec/examples/html_to_markdown_spec.rb -e "Hierarchical"
```

## AST Node Types

The AST supports 21 Markdown element types:

**Block Elements:**
- `Heading` (levels 1-6)
- `Paragraph`
- `CodeBlock` (with language)
- `Blockquote`
- `HorizontalRule`
- `List` (ordered/unordered)
- `ListItem`
- `Table`, `TableRow`, `TableCell`

**Inline Elements:**
- `Text`
- `Bold`, `Italic`, `Strikethrough`
- `Code` (inline)
- `Link`, `Image`
- `LineBreak`

**Extended:**
- `FootnoteRef`, `FootnoteDef`
- `TaskListItem`

## Cost Analysis (Claude Haiku 4.5)

At Haiku pricing ($1/$5 per 1M input/output tokens):

| Approach | Input Cost | Output Cost | **Total per 1K articles** |
|----------|-----------|-------------|---------------------------|
| Direct String | $0.0018 | $0.0023 | **$4.10** |
| BAML AST | $0.0015 | $0.0116 | **$13.10** |
| Native JSON AST | $0.0022 | $0.0158 | **$18.00** |

**Direct String is 4.4x cheaper than Native JSON AST** for high-volume conversion.

## Conclusion

1. **OpenAI native structured outputs now work** with recursive schemas (issue #201 fixed)
2. **Use `default: []` instead of nilables** for array fields
3. **Field descriptions** help LLMs understand complex schemas
4. **Hierarchical parsing** handles documents that exceed token limits
5. **Direct String wins for simple conversion** - Fast, cheap, reliable
6. **AST approach valuable for** validation, transformation, and tooling

The hypothesis that structured AST types help produce "better" Markdown was **not confirmed** for simple conversion. However, structured types enable:
- Schema validation at parse time
- Programmatic AST transformation
- Type-safe document manipulation
- Better error messages when parsing fails

**Key takeaway**: With the `#/$defs/` fix, native structured outputs are now the recommended approach for recursive types across all major providers.
