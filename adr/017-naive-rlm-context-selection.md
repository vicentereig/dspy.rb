# ADR-017: Naive RLM - Structured Output for Context Selection

## Status
Accepted

## Context
The Recursive Language Model (RLM) technique allows LLMs to navigate large contexts that don't fit in the context window. The original RLM implementation ([github.com/alexzhang13/rlm](https://github.com/alexzhang13/rlm)) uses a Python REPL where the LLM generates code to:

1. **Peek**: Access slices of context (`context[:2000]`)
2. **Grep**: Search with regex (`[l for l in context if re.search(pat, l)]`)
3. **Partition**: Chunk context for parallel processing (`[context[i:i+1000] for i in range(0, len, 1000)]`)
4. **Recursive call**: Query subsets (`llm_query(f"Summarize: {chunk}")`)

The LLM outputs Python code → REPL executes → results return to LLM → iterate until `FINAL(answer)`.

This approach is powerful but requires:
- A sandboxed code execution environment
- LLM capable of generating valid Python code
- Security considerations for arbitrary code execution

### Existing DSPy.rb Approach
The current `RLMSummarizer` in `examples/pdf_recursive_summarizer.rb` uses a fixed 3-stage pipeline:
1. Discover structure from preview (LLM outputs line ranges)
2. Map: summarize each section
3. Reduce: synthesize summaries

This is predictable but doesn't allow the LLM to navigate dynamically based on what it finds.

## Decision
Implement a "Naive RLM" that encodes the original RLM primitives as **structured output** via DSPy.rb signatures, instead of code generation.

### Primitives as Enum
```ruby
class RLMAction < T::Enum
  enums do
    Peek = new('peek')         # Read line range
    Grep = new('grep')         # Regex search
    Partition = new('partition') # Chunk processing
    Finish = new('finish')     # Done, provide answer
  end
end
```

### Mapping Code to Structured Output
```
Original RLM (code)              Naive RLM (structured output)
─────────────────────────────    ─────────────────────────────
context[0:2000]                  { action: "peek", peek_range: [1, 100] }
re.search("results", context)   { action: "grep", grep_pattern: "results" }
chunks = partition(context)      { action: "partition", partition_size: 500 }
llm_query("summarize", chunk)   Ruby calls @summarizer.call(chunk)
FINAL(answer)                   { action: "finish", final_answer: "..." }
```

### Control Flow
1. LLM sees preview + query + history of previous actions
2. LLM outputs action enum + parameters via `SelectAction` signature
3. Ruby executes the primitive (peek/grep/partition)
4. Results go back to LLM as updated `context_window`
5. Iterate until LLM outputs `Finish` action

### Architecture
```
Document (hidden from LLM)     LLM Context (small)
┌─────────────────────────┐    ┌─────────────────────────┐
│ 2500 lines of text      │    │ - Preview (100 lines)   │
│ (never fully sent)      │◄──▶│ - Query                 │
│                         │    │ - Action history        │
└─────────────────────────┘    └─────────────────────────┘
         │                                │
         │ Ruby executes primitives       │ LLM outputs actions
         ▼                                ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│ Extracted regions       │───▶│ Summarize each region   │
│ (peek/grep results)     │    │ → update history        │
└─────────────────────────┘    └─────────────────────────┘
```

## Consequences

### Benefits
- **No code execution**: Safe, no sandbox needed
- **Type-safe**: Sorbet validates all action parameters
- **Simpler LLM task**: Pick from 4 primitives vs generate arbitrary Python
- **Debuggable**: Clear action history trace with summaries
- **DSPy.rb native**: Uses existing Signature/Predict/ChainOfThought patterns
- **Control inversion**: LLM decides navigation strategy dynamically

### Trade-offs
- **Less flexible**: Only 4 primitives vs unlimited Python
- **May need more iterations**: Can't combine operations in one step
- **Pattern limitations**: Regex only, no complex string manipulation
- **No arbitrary computation**: Can't write loops or conditionals in selection

### Comparison
| Aspect | Original RLM | Naive RLM | Current RLMSummarizer |
|--------|--------------|-----------|----------------------|
| Selection | Python code | Structured output | Fixed line ranges |
| Safety | Needs sandbox | No code execution | No code execution |
| Flexibility | Unlimited | 4 primitives | 3-stage pipeline |
| LLM complexity | Generate code | Fill schema | Fill schema |
| Navigation | Dynamic | Dynamic | Static |

## Implementation

### Key Files
- `lib/dspy/naive_rlm.rb` - Module with enum, signatures, and forward loop
- `spec/dspy/naive_rlm_spec.rb` - Unit tests for primitives
- `spec/integration/naive_rlm_integration_spec.rb` - Integration tests with VCR
- `examples/naive_rlm_document.rb` - Usage example

### Signatures
1. **SelectAction**: LLM outputs action enum + parameters
2. **SummarizeChunk**: Summarize extracted content for history

## References
- Original RLM: https://github.com/alexzhang13/rlm
- RLM Minimal: https://github.com/alexzhang13/rlm-minimal
- Blog post: https://alexzhang13.github.io/blog/2025/rlm/
- Existing RLMSummarizer: `examples/pdf_recursive_summarizer.rb`
