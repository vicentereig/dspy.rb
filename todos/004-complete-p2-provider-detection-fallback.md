# Provider Detection Falls Back Silently to OpenAI

---
status: complete
priority: p2
issue_id: "004"
tags: [code-review, error-handling, user-experience]
dependencies: []
---

## Problem Statement

When a model name doesn't match any known pattern, the adapter silently defaults to 'openai'. This can lead to confusing errors when the model doesn't exist on OpenAI.

**Why it matters**: Users get cryptic errors instead of clear guidance.

## Findings

**Location**: `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb:89-105`

```ruby
def infer_provider_from_model_name(model_name)
  case model_name.downcase
  when /^gpt/, /^o[134]/, /^davinci/, /^text-/
    'openai'
  # ... more patterns ...
  else
    'openai' # Default fallback - DANGEROUS
  end
end
```

**Problem scenario**:
```ruby
# User typo: "gtp-4o" instead of "gpt-4o"
lm = DSPy::LM.new('ruby_llm/gtp-4o')
# Silently routes to OpenAI with wrong model name
```

**Agents reporting**: architecture-strategist, kieran-rails-reviewer, security-sentinel

## Proposed Solutions

### Option 1: Raise error for unknown models
```ruby
else
  raise DSPy::LM::ConfigurationError,
    "Cannot infer provider for model '#{model_name}'. " \
    "Use provider: option to specify explicitly."
end
```
**Pros**: Fail fast, clear error message
**Cons**: Breaks if RubyLLM adds new models we don't recognize
**Effort**: Small
**Risk**: Low

### Option 2: Log warning but still fallback
**Pros**: Doesn't break existing code
**Cons**: Errors may go unnoticed
**Effort**: Small
**Risk**: Medium

### Option 3: Query RubyLLM registry more aggressively
**Pros**: Uses RubyLLM's knowledge
**Cons**: Already tried (line 76-87), this is fallback when that fails
**Effort**: N/A
**Risk**: N/A

## Recommended Action

Option 1 - Fail fast with clear error

## Technical Details

**Affected files**:
- `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb`
- `spec/unit/dspy/lm/adapters/ruby_llm/ruby_llm_adapter_spec.rb`

## Acceptance Criteria

- [x] Unknown model names raise clear error
- [x] Error message includes guidance (use provider: option)
- [x] Tests verify error behavior

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | Silent failures cause confusion |
| 2025-12-06 | Implemented solution | Replaced silent fallback with explicit ConfigurationError, added test case |

## Resources

- PR #187: https://github.com/vicentereig/dspy.rb/pull/187
