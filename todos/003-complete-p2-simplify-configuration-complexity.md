# Simplify Dual Configuration Mode Complexity

---
status: complete
priority: p2
issue_id: "003"
tags: [code-review, simplification, yagni]
dependencies: []
---

## Problem Statement

The adapter has complex dual-mode configuration (global vs scoped) with 7 conditional checks. This adds cognitive overhead and differs from all other adapters.

**Why it matters**: No other adapter has this pattern. It makes the adapter harder to understand and test.

## Findings

**Location**: `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb:107-121`

```ruby
def should_use_global_config?(api_key, options)
  return false if api_key
  return false if options[:base_url]
  return false if options[:secret_key]  # Bedrock
  return false if options[:region]      # Bedrock
  return false if options[:location]    # VertexAI
  return false if options[:timeout]
  return false if options[:max_retries]
  true
end
```

**Agents reporting**: dhh-rails-reviewer, simplicity-reviewer, architecture-strategist, kieran-rails-reviewer

**DHH's take**: "What in the name of pattern matching is this? You've got Ruby 3.3 available and you're writing procedural guard clauses like it's 2005."

## Proposed Solutions

### Option 1: Simplify with set intersection
```ruby
SCOPED_OPTIONS = %i[base_url secret_key region location timeout max_retries].freeze

def should_use_global_config?(api_key, options)
  api_key.nil? && (options.keys & SCOPED_OPTIONS).empty?
end
```
**Pros**: One line, clear intent
**Cons**: Still keeps dual-mode
**Effort**: Small
**Risk**: Low

### Option 2: Remove global config mode entirely
**Pros**: Matches other adapters, simpler mental model
**Cons**: May inconvenience users who rely on RubyLLM.configure
**Effort**: Medium
**Risk**: Medium

### Option 3: Add explicit `config_mode:` parameter
```ruby
def initialize(model:, api_key: nil, config_mode: :auto, **options)
```
**Pros**: Explicit is better than implicit
**Cons**: More API surface
**Effort**: Small
**Risk**: Low

## Recommended Action

(To be filled during triage)

## Technical Details

**Affected files**:
- `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb`

**LOC reduction potential**: ~30 lines (per simplicity-reviewer)

## Acceptance Criteria

- [ ] Configuration logic is simplified or well-justified
- [ ] Behavior is documented clearly
- [ ] Tests cover all configuration paths

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | Multiple agents flagged complexity |
| 2025-12-06 | Implemented Option 1 | Added SCOPED_OPTIONS constant, simplified method to one line using set intersection |

## Resources

- PR #187: https://github.com/vicentereig/dspy.rb/pull/187
