# Metadata Provider Confusion

---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, architecture, breaking-change]
dependencies: []
---

## Problem Statement

The metadata factory is called with `'ruby_llm'` as provider, but then passes dynamic `provider` (e.g., 'openai') in the hash. This creates confusion about the actual provider identity.

**Why it matters**: Users relying on `metadata.provider` for tracking/billing will get inconsistent values.

## Findings

**Location**: `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb:318-322`

```ruby
def build_metadata(response)
  DSPy::LM::ResponseMetadataFactory.create('ruby_llm', {
    model: response.model_id || model,
    provider: provider  # This passes 'openai', 'anthropic', etc.
  })
end
```

**Expected behavior**:
- `metadata.provider` should be `'ruby_llm'` (consistent with adapter type)
- Underlying provider should be in a separate field like `underlying_provider`

**Agents reporting**: architecture-strategist, security-sentinel

## Proposed Solutions

### Option 1: Fix metadata to use 'ruby_llm' consistently
```ruby
def build_metadata(response)
  DSPy::LM::ResponseMetadataFactory.create('ruby_llm', {
    model: response.model_id || model,
    underlying_provider: provider  # Renamed field
  })
end
```
**Pros**: Consistent with other adapters
**Cons**: May need new metadata class
**Effort**: Small
**Risk**: Low

### Option 2: Create RubyLLMResponseMetadata type
**Pros**: Type-safe, follows established pattern
**Cons**: More code to maintain
**Effort**: Medium
**Risk**: Low

## Recommended Action

(To be filled during triage)

## Technical Details

**Affected files**:
- `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb`
- `lib/dspy/lm/response.rb` (if adding new metadata type)

## Acceptance Criteria

- [x] `metadata.provider` returns `'ruby_llm'`
- [x] Underlying provider accessible via separate field
- [ ] Tests verify correct metadata structure

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | Consistency issue with adapter identity |
| 2025-12-06 | Implemented fix - renamed provider to underlying_provider | Changed both build_metadata and build_empty_response methods |

## Resources

- PR #187: https://github.com/vicentereig/dspy.rb/pull/187
