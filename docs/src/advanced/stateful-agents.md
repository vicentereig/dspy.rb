---
layout: docs
title: Stateful Agents
description: Production patterns for building agents that maintain context and state
breadcrumb:
- name: Advanced
  url: "/advanced/"
- name: Stateful Agents
  url: "/advanced/stateful-agents/"
nav:
  prev:
    name: LangChain Comparison
    url: "/advanced/dspy-vs-langchain/"
  next:
    name: Custom Toolsets
    url: "/advanced/custom-toolsets/"
date: 2025-07-11 00:00:00 +0000
---
# Stateful Agents

Stateful agents maintain context and information across multiple interactions, enabling them to provide responses that take into account previous conversations and user preferences. This guide covers production patterns for building robust stateful agents with DSPy.rb.

## Core Concepts

### State vs Memory

**State** refers to temporary information that agents maintain during a conversation or session:
- Current conversation context
- User preferences for the session
- Temporary calculations or intermediate results

**Memory** refers to persistent information stored across sessions at the application level:
- User preferences and settings
- Historical interactions
- Learned patterns and behaviors

DSPy.rb provides the building blocks (modules, tools, ReAct agents) while your application manages persistence using your preferred storage backend (database, Redis, etc.).

## Production Patterns

### 1. Session-Based Agent

A session-based agent maintains state during a conversation but doesn't persist information between sessions:

```ruby
class SessionAgent < DSPy::Module
  class ConversationSignature < DSPy::Signature
    description "Conversational agent that maintains context"

    input do
      const :user_message, String
      const :session_id, String
    end

    output do
      const :response, String
      const :context_summary, String
    end
  end

  def initialize
    super
    @sessions = {}
    @agent = DSPy::ReAct.new(ConversationSignature, tools: [])
  end

  def forward(user_message:, session_id:)
    # Get or create session context
    session = get_session(session_id)

    # Add context to the message
    contextual_message = build_contextual_message(user_message, session)

    # Get response from agent
    result = @agent.call(
      user_message: contextual_message,
      session_id: session_id
    )

    # Update session context
    update_session(session_id, user_message, result)

    result
  end

  private

  def get_session(session_id)
    @sessions[session_id] ||= {
      messages: [],
      context: "",
      started_at: Time.now
    }
  end

  def build_contextual_message(message, session)
    if session[:messages].empty?
      message
    else
      "Previous context: #{session[:context]}\n\nCurrent message: #{message}"
    end
  end

  def update_session(session_id, message, result)
    session = @sessions[session_id]
    session[:messages] << {
      user: message,
      assistant: result.response,
      timestamp: Time.now
    }
    session[:context] = result.context_summary
  end
end
```

### 2. Persistent Agent with Custom Storage

A persistent agent stores information across sessions using application-level storage. Define custom tools that wrap your storage backend:

```ruby
# Custom tool for storing and retrieving data
class StorageTool < DSPy::Tools::Base
  tool_name "storage"
  tool_description "Store and retrieve key-value data"

  sig { params(action: String, key: String, value: T.nilable(String)).returns(String) }
  def call(action:, key:, value: nil)
    case action
    when "store"
      @store[key] = value
      "Stored '#{key}'"
    when "retrieve"
      @store.fetch(key, "No data found for '#{key}'")
    when "list"
      @store.keys.join(", ")
    else
      "Unknown action: #{action}"
    end
  end

  def initialize
    @store = {}
  end
end

class PersistentAgent < DSPy::Module
  class MemoryAwareSignature < DSPy::Signature
    description "Agent that stores and retrieves user context"

    input do
      const :user_message, String
      const :user_id, String
    end

    output do
      const :response, String
      const :actions_taken, T::Array[String]
    end
  end

  def initialize
    super
    @storage = StorageTool.new

    @agent = DSPy::ReAct.new(
      MemoryAwareSignature,
      tools: [@storage],
      max_iterations: 5
    )
  end

  def forward(user_message:, user_id:)
    result = @agent.call(
      user_message: user_message,
      user_id: user_id
    )

    # Application-level persistence (e.g., database, Redis)
    store_interaction(user_id, user_message, result.response)

    result
  end

  private

  def store_interaction(user_id, message, response)
    # Replace with your persistence layer (ActiveRecord, Redis, etc.)
    @interactions ||= Hash.new { |h, k| h[k] = [] }
    @interactions[user_id] << {
      user_message: message,
      assistant_response: response,
      timestamp: Time.now.iso8601
    }
  end
end
```

### 3. Multi-Context Agent

An agent that maintains different types of context and state:

```ruby
class MultiContextAgent < DSPy::Module
  class ContextualSignature < DSPy::Signature
    description "Agent with rich context management"

    input do
      const :user_message, String
      const :user_id, String
      const :session_id, String
    end

    output do
      const :response, String
      const :confidence, Float
      const :context_used, T::Array[String]
    end
  end

  def initialize
    super
    @sessions = {}

    @agent = DSPy::ReAct.new(
      ContextualSignature,
      tools: DSPy::Tools::TextProcessingToolset.to_tools,
      max_iterations: 6
    )
  end

  def forward(user_message:, user_id:, session_id:)
    # 1. Get session context
    session_context = get_session_context(session_id)

    # 2. Build enriched context
    enriched_message = build_enriched_context(
      user_message,
      user_id,
      session_context
    )

    # 3. Get agent response
    result = @agent.call(
      user_message: enriched_message,
      user_id: user_id,
      session_id: session_id
    )

    # 4. Update contexts
    update_contexts(user_id, session_id, user_message, result)

    result
  end

  private

  def get_session_context(session_id)
    @sessions[session_id] ||= {
      turn_count: 0,
      topics: [],
      sentiment: "neutral",
      last_activity: Time.now
    }
  end

  def build_enriched_context(message, user_id, session_context)
    context_parts = [
      "User message: #{message}",
      "Session context: #{session_context[:turn_count]} turns, topics: #{session_context[:topics].join(', ')}"
    ]

    context_parts.join("\n")
  end

  def update_contexts(user_id, session_id, message, result)
    session = @sessions[session_id]
    session[:turn_count] += 1
    session[:last_activity] = Time.now
  end
end
```

### 4. Adaptive Learning Agent

An agent that learns from interactions and adapts its behavior:

```ruby
class AdaptiveLearningAgent < DSPy::Module
  class LearningSignature < DSPy::Signature
    description "Agent that learns from interactions and adapts"

    input do
      const :user_message, String
      const :user_id, String
    end

    output do
      const :response, String
      const :learned_patterns, T::Array[String]
      const :adaptation_notes, String
    end
  end

  def initialize
    super
    @user_profiles = Hash.new { |h, k| h[k] = { patterns: [], interactions: 0 } }

    @agent = DSPy::ReAct.new(
      LearningSignature,
      tools: DSPy::Tools::TextProcessingToolset.to_tools,
      max_iterations: 8
    )
  end

  def forward(user_message:, user_id:)
    # Get user's interaction history for learning
    user_profile = @user_profiles[user_id]

    # Build adaptive prompt
    adaptive_message = build_adaptive_prompt(
      user_message,
      user_id,
      user_profile
    )

    result = @agent.call(
      user_message: adaptive_message,
      user_id: user_id
    )

    # Learn from this interaction
    learn_from_interaction(user_id, result)

    result
  end

  private

  def build_adaptive_prompt(message, user_id, profile)
    prompt_parts = [
      "User message: #{message}",
      "User ID: #{user_id}",
      "Interaction count: #{profile[:interactions]}",
      "Known patterns: #{profile[:patterns].last(5).join(', ')}"
    ]

    prompt_parts.join("\n")
  end

  def learn_from_interaction(user_id, result)
    profile = @user_profiles[user_id]
    profile[:interactions] += 1
    profile[:patterns].concat(result.learned_patterns)

    # Keep only recent patterns
    profile[:patterns] = profile[:patterns].last(50)
  end
end
```

## Error Handling and Resilience

### Failure Recovery

```ruby
class ResilientAgent < DSPy::Module
  def initialize
    super
    @fallback_context = {}

    @agent = DSPy::ReAct.new(
      AgentSignature,
      tools: DSPy::Tools::TextProcessingToolset.to_tools
    )
  end

  def forward(user_message:, user_id:)
    begin
      result = @agent.call(
        user_message: user_message,
        user_id: user_id
      )

      # Store in fallback context as backup
      store_fallback(user_id, user_message, result.response)

      result
    rescue => e
      # Fall back to session-only mode
      DSPy.logger.warning("Agent failed: #{e.message}")
      fallback_response(user_message, user_id)
    end
  end

  private

  def store_fallback(user_id, message, response)
    @fallback_context[user_id] ||= []
    @fallback_context[user_id] << {
      message: message,
      response: response,
      timestamp: Time.now
    }

    # Keep only last 10 interactions per user
    @fallback_context[user_id] = @fallback_context[user_id].last(10)
  end

  def fallback_response(message, user_id)
    # Use fallback context for simple response
    context = @fallback_context[user_id]&.last(3) || []

    class SimpleSignature < DSPy::Signature
      description "Simple response without tools"

      input do
        const :message, String
        const :context, String
      end

      output do
        const :response, String
      end
    end

    simple_agent = DSPy::Predict.new(SimpleSignature)
    simple_agent.call(
      message: message,
      context: context.to_json
    )
  end
end
```

### State Corruption Recovery

```ruby
class StateRecoveryAgent < DSPy::Module
  class RecoverySignature < DSPy::Signature
    description "Agent with state recovery capabilities"

    input do
      const :user_message, String
      const :user_id, String
    end

    output do
      const :response, String
    end
  end

  def initialize
    super
    @state_version = 1
    @state = Hash.new { |h, k| h[k] = {} }
    @agent = DSPy::ReAct.new(RecoverySignature, tools: [])
  end

  def forward(user_message:, user_id:)
    # Check state integrity
    unless state_valid?(user_id)
      recover_state(user_id)
    end

    result = @agent.call(
      user_message: user_message,
      user_id: user_id
    )

    # Validate result before storing
    if result_valid?(result)
      store_with_checksum(user_id, result)
    else
      DSPy.logger.error("Invalid result detected for user #{user_id}")
    end

    result
  end

  private

  def state_valid?(user_id)
    state = @state[user_id]
    return true if state.empty?

    # Verify checksum integrity
    state[:checksum] == Digest::MD5.hexdigest(state[:response].to_s)
  end

  def recover_state(user_id)
    DSPy.logger.info("Recovering state for user #{user_id}")
    @state[user_id] = {}
  end

  def result_valid?(result)
    result.respond_to?(:response) &&
    result.response.is_a?(String) &&
    result.response.length > 0
  end

  def store_with_checksum(user_id, result)
    @state[user_id] = {
      response: result.response,
      checksum: Digest::MD5.hexdigest(result.response),
      version: @state_version,
      timestamp: Time.now.iso8601
    }
  end
end
```

## Performance Considerations

### State Management Optimization

```ruby
class OptimizedStatefulAgent < DSPy::Module
  class OptimizedSignature < DSPy::Signature
    description "Optimized agent with state cleanup"

    input do
      const :user_message, String
      const :user_id, String
    end

    output do
      const :response, String
    end
  end

  MAX_HISTORY = 50
  CLEANUP_INTERVAL = 100

  def initialize
    super
    @interaction_count = 0
    @user_history = Hash.new { |h, k| h[k] = [] }
    @agent = DSPy::ReAct.new(OptimizedSignature, tools: [])
  end

  def forward(user_message:, user_id:)
    # Periodically trigger cleanup
    cleanup_old_state(user_id) if should_cleanup?

    result = @agent.call(
      user_message: user_message,
      user_id: user_id
    )

    # Store only essential information
    store_essential_data(user_id, user_message, result)

    result
  end

  private

  def should_cleanup?
    @interaction_count += 1
    @interaction_count % CLEANUP_INTERVAL == 0
  end

  def cleanup_old_state(user_id)
    history = @user_history[user_id]
    @user_history[user_id] = history.last(MAX_HISTORY) if history.size > MAX_HISTORY
  end

  def store_essential_data(user_id, message, result)
    return if result.response.length < 10

    @user_history[user_id] << {
      message_summary: message.length > 100 ? "#{message[0..97]}..." : message,
      timestamp: Time.now.iso8601
    }
  end
end
```

## Testing Stateful Agents

### Unit Testing

```ruby
RSpec.describe SessionAgent do
  let(:agent) { described_class.new }

  describe '#forward' do
    it 'maintains session context across calls', vcr: { cassette_name: "session_agent_context" } do
      session_id = "test_session"

      # First interaction
      result1 = agent.call(
        user_message: "My name is Alice",
        session_id: session_id
      )

      # Second interaction
      result2 = agent.call(
        user_message: "What is my name?",
        session_id: session_id
      )

      expect(result2.response).to include("Alice")
    end

    it 'isolates different sessions', vcr: { cassette_name: "session_agent_isolation" } do
      agent.call(
        user_message: "My name is Alice",
        session_id: "session_1"
      )

      result = agent.call(
        user_message: "What is my name?",
        session_id: "session_2"
      )

      expect(result.response).not_to include("Alice")
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Stateful Agent Integration", vcr: { cassette_name: "stateful_agent_integration" } do
  let(:agent) { MultiContextAgent.new }

  it 'maintains context across a conversation' do
    session_id = "test_session_#{Time.now.to_i}"

    # Conversation flow
    responses = [
      "I'm planning a trip to Japan",
      "What's the weather like there?",
      "Should I pack warm clothes?"
    ].map do |message|
      agent.call(
        user_message: message,
        user_id: "test_user",
        session_id: session_id
      )
    end

    # Verify context awareness
    expect(responses.last.response).to include("Japan")
    expect(responses.last.context_used).to include("trip")
  end
end
```

## Best Practices

### 1. State Management

- **Use application-level storage**: Manage persistence with your preferred backend (database, Redis, etc.)
- **Keep state minimal**: Don't store every interaction; focus on important information
- **Clean up regularly**: Implement cleanup strategies to prevent unbounded growth

### 2. Error Handling

- **Graceful degradation**: Provide fallback behavior when state is unavailable
- **State validation**: Validate stored state before using it
- **Recovery mechanisms**: Implement ways to recover from corrupted state

### 3. Performance

- **Batch operations**: Store multiple state updates in batches when possible
- **Selective storage**: Only store information that will be useful later
- **Monitor usage**: Track state management performance in production

### 4. Privacy and Security

- **Data minimization**: Store only necessary information
- **User consent**: Ensure users understand what information is being stored
- **Secure storage**: Use appropriate security measures for sensitive data

## Common Pitfalls

### 1. Unbounded State Growth
```ruby
# BAD: Storing too much detail
@history[user_id] << full_conversation_transcript  # Grows forever

# GOOD: Store essential information with limits
@history[user_id] << conversation_summary
@history[user_id] = @history[user_id].last(50)  # Bounded
```

### 2. Context Confusion
```ruby
# BAD: Mixing contexts
def build_context(user_id, session_id)
  all_history = @history[user_id]  # Too broad
  all_history.join("\n")
end

# GOOD: Focused context
def build_context(user_id, session_id)
  recent = @history[user_id].last(5)  # Relevant subset
  recent.map { |h| h[:summary] }.join("\n")
end
```

### 3. State Inconsistency
```ruby
# BAD: Not validating state
def use_stored_preference(user_id)
  pref = get_user_preference(user_id)
  pref.value  # Could be nil or invalid
end

# GOOD: Validate before use
def use_stored_preference(user_id)
  pref = get_user_preference(user_id)
  return default_preference unless pref&.valid?
  pref.value
end
```

Stateful agents require careful design and implementation, but they enable much more sophisticated and personalized user experiences. By following these patterns and best practices, you can build robust agents that maintain context effectively while handling edge cases gracefully.
