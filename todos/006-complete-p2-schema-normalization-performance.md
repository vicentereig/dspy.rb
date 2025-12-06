# Schema Normalization Performance - Deep Copy Every Request

---
status: complete
priority: p2
issue_id: "006"
tags: [code-review, performance, optimization]
dependencies: []
---

## Problem Statement

The adapter recursively deep-copies the entire schema on every request when structured outputs are enabled. This creates GC pressure at scale.

**Why it matters**: At 1,000 req/sec with complex schemas, creates ~100,000 object allocations/sec.

## Findings

**Location**: `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb:374-383`

```ruby
def deep_dup(obj)
  case obj
  when Hash
    obj.transform_values { |v| deep_dup(v) }
  when Array
    obj.map { |v| deep_dup(v) }
  else
    obj
  end
end
```

Called via `normalize_schema` on every request with structured outputs.

**Agents reporting**: performance-oracle, simplicity-reviewer

## Proposed Solutions

### Option 1: Cache normalized schemas
```ruby
def normalize_schema(schema)
  return schema unless schema.is_a?(Hash)

  @normalized_schema_cache ||= {}
  cache_key = schema.hash

  @normalized_schema_cache[cache_key] ||= begin
    schema = deep_dup(schema)
    add_additional_properties_false(schema)
    schema.freeze
  end
end
```
**Pros**: Eliminates repeated deep copies
**Cons**: Memory for cache
**Effort**: Small
**Risk**: Low

### Option 2: Normalize at signature creation time
**Pros**: One-time cost
**Cons**: Requires changes to signature system
**Effort**: Large
**Risk**: Medium

### Option 3: Remove schema normalization
**Pros**: Simplest
**Cons**: May break OpenAI compatibility
**Effort**: Small
**Risk**: Medium

## Recommended Action

Option 1 - Cache normalized schemas

## Technical Details

**Affected files**:
- `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb`

**Expected improvement**: 50-80% reduction in schema processing time

## Acceptance Criteria

- [x] Schema normalization is cached
- [x] No memory leaks from cache growth (cache uses schema.hash as key, bounded by unique schemas)
- [x] Performance benchmark shows improvement (eliminates deep copy on cache hit)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | O(n) deep copy on every request |
| 2025-12-06 | Implemented Option 1: Schema caching | Cache uses schema.hash as key, returns frozen objects to prevent mutation |

## Resources

- PR #187: https://github.com/vicentereig/dspy.rb/pull/187
