# Message History Loss - Only Last User Message Used

---
status: complete
priority: p1
issue_id: "001"
tags: [code-review, architecture, regression-risk]
dependencies: []
---

## Problem Statement

The RubyLLM adapter extracts only the last user message, discarding conversation history. This is fundamentally different from OpenAI/Anthropic/Gemini adapters which pass ALL messages to the API.

**Why it matters**: Multi-turn conversations, ReAct agents, and ChainOfThought modules may silently lose context.

## Findings

**Location**: `lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb:238-248`

```ruby
def prepare_message_content(messages)
  last_user_message = messages.reverse.find { |m| m[:role] == 'user' }
  return [nil, []] unless last_user_message
  extract_content_and_attachments(last_user_message)
end
```

**Evidence from other adapters**:
- OpenAI adapter (line 24): Passes full `normalized_messages` array
- Anthropic adapter (line 23): Processes ALL messages
- Gemini adapter (line 50): Converts ALL messages to Gemini format

**Agents reporting**: architecture-strategist, kieran-rails-reviewer, dhh-rails-reviewer

## Solution Implemented

**Option Selected**: Build conversation history via add_message() API (hybrid of Option 1 & 3)

### Implementation Details

Modified `prepare_chat_instance` method in `/Users/kieranklaassen/dspy.rb/lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb` to:

1. Use `with_instructions()` for system messages (existing behavior)
2. Use `add_message(role:, content:)` to build conversation history for all messages before the last user message
3. Pass the last user message to `ask()` as before

This approach:
- Leverages RubyLLM's `add_message` API which accepts `:user`, `:assistant`, and `:system` roles
- Maintains consistency with how other adapters handle full message history
- Preserves the existing `ask()` pattern for the final user message
- Works with both single-turn and multi-turn conversations

### Code Changes

```ruby
# Common setup: apply system instructions, build conversation history, and optional schema
def prepare_chat_instance(chat_instance, messages, signature)
  # First, handle system messages via with_instructions for proper system prompt handling
  system_message = messages.find { |m| m[:role] == 'system' }
  chat_instance = chat_instance.with_instructions(system_message[:content]) if system_message

  # Build conversation history by adding all non-system messages except the last user message
  # The last user message will be passed to ask() to get the response
  messages_to_add = messages.reject { |m| m[:role] == 'system' }

  # Find the index of the last user message
  last_user_index = messages_to_add.rindex { |m| m[:role] == 'user' }

  if last_user_index && last_user_index > 0
    # Add all messages before the last user message to build history
    messages_to_add[0...last_user_index].each do |msg|
      content, attachments = extract_content_and_attachments(msg)
      next unless content

      # Add message with appropriate role
      if attachments.any?
        chat_instance.add_message(role: msg[:role].to_sym, content: content, attachments: attachments)
      else
        chat_instance.add_message(role: msg[:role].to_sym, content: content)
      end
    end
  end

  if signature && @structured_outputs_enabled
    schema = build_json_schema(signature)
    chat_instance = chat_instance.with_schema(schema) if schema
  end

  chat_instance
end
```

## Technical Details

**Modified files**:
- `/Users/kieranklaassen/dspy.rb/lib/dspy/ruby_llm/lm/adapters/ruby_llm_adapter.rb` (lines 235-269)
- `/Users/kieranklaassen/dspy.rb/spec/integration/dspy/lm/adapters/ruby_llm_adapter_spec.rb` (added multi-turn conversation tests)

**Affected components**:
- ReAct agents - NOW SUPPORTED with full history
- ChainOfThought modules - NOW SUPPORTED with full history
- Any multi-turn conversation patterns - NOW SUPPORTED

## Acceptance Criteria

- [x] Verify RubyLLM's actual capabilities for message arrays
  - Confirmed: RubyLLM supports `add_message(role:, content:)` with `:user`, `:assistant`, `:system` roles
  - Confirmed: RubyLLM automatically sends full conversation history with each `ask()` call
- [x] Either fix to pass full history OR document limitation clearly
  - FIXED: Now passes full history using `add_message` API
- [x] Add tests verifying multi-turn behavior
  - Added test: "builds conversation history using add_message before final ask"
  - Added test: "handles single-turn conversations without add_message calls"
- [x] Update README with any limitations
  - No limitations to document - full history support implemented

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2025-12-06 | Created from code review | Critical regression risk identified by 3 agents |
| 2025-12-06 | Investigated RubyLLM API | Found `add_message` method supports user/assistant/system roles |
| 2025-12-06 | Implemented fix | Used `add_message` to build history before final `ask()` call |
| 2025-12-06 | Added tests | Verified multi-turn and single-turn conversation handling |
| 2025-12-06 | Resolved issue | Full message history now passed to RubyLLM adapter |

## Resources

- PR #187: https://github.com/vicentereig/dspy.rb/pull/187
- RubyLLM Chat API docs: https://rubyllm.com
