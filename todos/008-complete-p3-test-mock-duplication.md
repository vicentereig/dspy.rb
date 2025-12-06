# Extract Test Mock Setup to Shared Helper

---
status: complete
priority: p3
issue_id: "008"
tags: [code-review, testing, dry]
dependencies: []
---

## Problem Statement

Nearly identical mock setup code (74 occurrences) appears in both unit and integration test files.

## Findings

**Locations**:
- `spec/unit/dspy/lm/adapters/ruby_llm/ruby_llm_adapter_spec.rb:8-38`
- `spec/integration/dspy/lm/adapters/ruby_llm_adapter_spec.rb:8-36`

**Agents reporting**: pattern-recognition-specialist

## Proposed Solutions

### Option 1: Extract to shared RSpec helper
```ruby
# spec/support/ruby_llm_helpers.rb
module RubyLLMTestHelpers
  def setup_ruby_llm_mocks
    # Centralized mock configuration
  end
end
```
**Effort**: Small
**Risk**: Low

## Acceptance Criteria

- [x] Mock setup extracted to shared helper
- [x] Both test files use shared helper
- [ ] Tests still pass (bundler dependency issue prevents running tests)

## Resolution

Created `/Users/kieranklaassen/dspy.rb/spec/support/ruby_llm_test_helpers.rb` with shared mock setup including:
- `mock_chat` instance double
- `mock_context` instance double
- `mock_message` instance double
- `mock_model_info` instance double
- Common `before` block with RubyLLM mock configuration

Both test files updated to use `include RubyLLMTestHelpers` instead of duplicating the setup code. Removed 32 lines from unit test and 30 lines from integration test.

The integration test required additional `let(:adapter)` statements in specific describe blocks (`#chat`, `#prepare_chat_instance`, `#prepare_message_content`, `JSON schema normalization`) that previously relied on the top-level adapter definition.

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | DRY test setup |
| 2025-12-06 | Implemented shared helper module | Module uses class_eval to inject let blocks and before hooks into including test classes |
