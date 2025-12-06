# Simplify send_message Method - 4 Code Paths

---
status: complete
priority: p3
issue_id: "007"
tags: [code-review, simplification, ruby-idioms]
dependencies: []
---

## Problem Statement

The `send_message` method has 4 nearly identical code blocks (2x2 matrix of streaming × attachments).

## Findings

**Location**: `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb:245-256`

**Original implementation** (4 code paths):
```ruby
def send_message(chat_instance, content, attachments, &block)
  if block_given?
    if attachments.any?
      chat_instance.ask(content, with: attachments) do |chunk|
        block.call(chunk.content) if chunk.content
      end
    else
      chat_instance.ask(content) do |chunk|
        block.call(chunk.content) if chunk.content
      end
    end
  else
    if attachments.any?
      chat_instance.ask(content, with: attachments)
    else
      chat_instance.ask(content)
    end
  end
end
```

**Agents reporting**: dhh-rails-reviewer, pattern-recognition-specialist, simplicity-reviewer

## Solution Implemented

Used Ruby kwargs spread to eliminate code duplication:
```ruby
def send_message(chat_instance, content, attachments, &block)
  kwargs = attachments.any? ? { with: attachments } : {}

  if block_given?
    chat_instance.ask(content, **kwargs) do |chunk|
      block.call(chunk.content) if chunk.content
    end
  else
    chat_instance.ask(content, **kwargs)
  end
end
```

**Benefits**:
- Reduced from 4 code paths to 2
- Eliminated nested conditionals
- Improved readability
- Leveraged Ruby idioms (kwargs spread)

## Acceptance Criteria

- [x] Method simplified to 2 code paths
- [x] Tests still pass (verified with existing unit/integration test coverage)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | Ruby idiom improvement |
| 2025-12-06 | Implemented simplification | Ruby kwargs spread works correctly with empty hashes |
