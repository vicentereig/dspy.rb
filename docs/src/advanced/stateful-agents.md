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
    name: Memory Systems
    url: "/advanced/memory-systems/"
  next:
    name: Custom Toolsets
    url: "/advanced/custom-toolsets/"
date: 2025-07-11 00:00:00 +0000
---
# Stateful Agents

Stateful agents maintain context and information across multiple interactions, enabling them to provide responses that take into account previous conversations and user preferences. This guide covers production patterns for building robust stateful agents using DSPy.rb's memory system.

## Core Concepts

### State vs Memory

**State** refers to temporary information that agents maintain during a conversation or session:
- Current conversation context
- User preferences for the session
- Temporary calculations or intermediate results

**Memory** refers to persistent information that agents store across sessions:
- User preferences and settings
- Historical interactions
- Learned patterns and behaviors

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

### 2. Persistent Memory Agent

A persistent memory agent stores information across sessions using the memory system:

```ruby
class PersistentAgent < DSPy::Module
  class MemoryAwareSignature < DSPy::Signature
    description "Agent that uses persistent memory for context"
    
    input do
      const :user_message, String
      const :user_id, String
    end
    
    output do
      const :response, String
      const :memory_actions, T::Array[String]
    end
  end
  
  def initialize
    super
    
    # Get memory tools for the agent
    memory_tools = DSPy::Tools::MemoryToolset.to_tools
    
    @agent = DSPy::ReAct.new(
      MemoryAwareSignature,
      tools: memory_tools,
      max_iterations: 5
    )
  end
  
  def forward(user_message:, user_id:)
    # The agent can use memory tools to:
    # - Retrieve relevant past interactions
    # - Store new information about the user
    # - Search for context-relevant memories
    
    result = @agent.call(
      user_message: user_message,
      user_id: user_id
    )
    
    # Optional: Store this interaction for future reference
    store_interaction(user_id, user_message, result.response)
    
    result
  end
  
  private
  
  def store_interaction(user_id, message, response)
    interaction_data = {
      user_message: message,
      assistant_response: response,
      timestamp: Time.now.iso8601
    }
    
    DSPy::Memory.manager.store_memory(
      interaction_data.to_json,
      user_id: user_id,
      tags: ["interaction", "conversation"]
    )
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
    
    @memory_tools = DSPy::Tools::MemoryToolset.to_tools
    @sessions = {}
    
    @agent = DSPy::ReAct.new(
      ContextualSignature,
      tools: @memory_tools,
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
      "Session context: #{session_context[:turn_count]} turns, topics: #{session_context[:topics].join(', ')}",
      "Note: You can use memory tools to recall user preferences and past interactions."
    ]
    
    context_parts.join("\n")
  end
  
  def update_contexts(user_id, session_id, message, result)
    # Update session context
    session = @sessions[session_id]
    session[:turn_count] += 1
    session[:last_activity] = Time.now
    
    # Store interaction in persistent memory
    store_interaction_with_context(user_id, session_id, message, result)
  end
  
  def store_interaction_with_context(user_id, session_id, message, result)
    interaction_data = {
      message: message,
      response: result.response,
      confidence: result.confidence,
      context_used: result.context_used,
      session_id: session_id,
      timestamp: Time.now.iso8601
    }
    
    DSPy::Memory.manager.store_memory(
      interaction_data.to_json,
      user_id: user_id,
      tags: ["interaction", "multi_modal", "session_#{session_id}"]
    )
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
    
    @memory_tools = DSPy::Tools::MemoryToolset.to_tools
    @agent = DSPy::ReAct.new(
      LearningSignature,
      tools: @memory_tools,
      max_iterations: 8
    )
  end
  
  def forward(user_message:, user_id:)
    # Get user's interaction history for learning
    user_patterns = analyze_user_patterns(user_id)
    
    # Build adaptive prompt
    adaptive_message = build_adaptive_prompt(
      user_message, 
      user_id, 
      user_patterns
    )
    
    result = @agent.call(
      user_message: adaptive_message,
      user_id: user_id
    )
    
    # Learn from this interaction
    learn_from_interaction(user_id, user_message, result)
    
    result
  end
  
  private
  
  def analyze_user_patterns(user_id)
    # This would be implemented by the agent using memory tools
    # Here we provide guidance for the agent
    {
      common_topics: [],
      communication_style: "unknown",
      preferences: [],
      expertise_level: "unknown"
    }
  end
  
  def build_adaptive_prompt(message, user_id, patterns)
    prompt_parts = [
      "User message: #{message}",
      "User ID: #{user_id}",
      "",
      "Instructions:",
      "1. Use memory tools to recall this user's preferences and interaction history",
      "2. Adapt your response style based on their communication patterns",
      "3. Reference relevant past interactions if helpful",
      "4. Store any new preferences or patterns you notice",
      "5. Note what you learned from this interaction"
    ]
    
    prompt_parts.join("\n")
  end
  
  def learn_from_interaction(user_id, message, result)
    # Store learning insights
    learning_data = {
      user_message: message,
      response: result.response,
      learned_patterns: result.learned_patterns,
      adaptation_notes: result.adaptation_notes,
      timestamp: Time.now.iso8601
    }
    
    DSPy::Memory.manager.store_memory(
      learning_data.to_json,
      user_id: user_id,
      tags: ["learning", "adaptation", "patterns"]
    )
  end
end
```

## Error Handling and Resilience

### Memory Failure Recovery

```ruby
class ResilientAgent < DSPy::Module
  def initialize
    super
    
    @memory_tools = DSPy::Tools::MemoryToolset.to_tools
    @fallback_memory = {}  # In-memory fallback
    
    @agent = DSPy::ReAct.new(
      AgentSignature,
      tools: @memory_tools
    )
  end
  
  def forward(user_message:, user_id:)
    begin
      # Try normal operation
      result = @agent.call(
        user_message: user_message,
        user_id: user_id
      )
      
      # Store in fallback memory as backup
      store_fallback(user_id, user_message, result.response)
      
      result
    rescue => e
      # Fall back to session-only mode
      DSPy.logger.warning("Memory system unavailable: #{e.message}")
      fallback_response(user_message, user_id)
    end
  end
  
  private
  
  def store_fallback(user_id, message, response)
    @fallback_memory[user_id] ||= []
    @fallback_memory[user_id] << {
      message: message,
      response: response,
      timestamp: Time.now
    }
    
    # Keep only last 10 interactions per user
    @fallback_memory[user_id] = @fallback_memory[user_id].last(10)
  end
  
  def fallback_response(message, user_id)
    # Use fallback memory for context
    context = @fallback_memory[user_id]&.last(3) || []
    
    # Create simple response without memory tools
    class SimpleSignature < DSPy::Signature
      description "Simple response without memory tools"
      
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
    @memory_tools = DSPy::Tools::MemoryToolset.to_tools
    @agent = DSPy::ReAct.new(RecoverySignature, tools: @memory_tools)
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
    # Check if user state is consistent
    # This would use memory tools to verify state integrity
    true
  end
  
  def recover_state(user_id)
    DSPy.logger.info("Recovering state for user #{user_id}")
    # Implement state recovery logic
  end
  
  def result_valid?(result)
    result.respond_to?(:response) && 
    result.response.is_a?(String) &&
    result.response.length > 0
  end
  
  def store_with_checksum(user_id, result)
    # Store with integrity check
    data = {
      response: result.response,
      checksum: generate_checksum(result),
      version: @state_version,
      timestamp: Time.now.iso8601
    }
    
    DSPy::Memory.manager.store_memory(
      data.to_json,
      user_id: user_id,
      tags: ["state", "verified", "v#{@state_version}"]
    )
  end
  
  def generate_checksum(result)
    # Simple checksum for integrity
    Digest::MD5.hexdigest(result.response)
  end
end
```

## Performance Considerations

### Memory Usage Optimization

```ruby
class OptimizedStatefulAgent < DSPy::Module
  class OptimizedSignature < DSPy::Signature
    description "Optimized agent with memory cleanup"
    
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
    
    # Use memory tools
    @memory_tools = DSPy::Tools::MemoryToolset.to_tools
    @agent = DSPy::ReAct.new(OptimizedSignature, tools: @memory_tools)
  end
  
  def forward(user_message:, user_id:)
    # Periodically trigger memory cleanup
    cleanup_old_memories(user_id) if should_cleanup?
    
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
    # Cleanup every 100 interactions
    @interaction_count = (@interaction_count || 0) + 1
    @interaction_count % 100 == 0
  end
  
  def cleanup_old_memories(user_id)
    # Force memory compaction
    DSPy::Memory.manager.force_compact!(user_id)
  end
  
  def store_essential_data(user_id, message, result)
    # Store only if response is significant
    return if result.response.length < 10
    
    essential_data = {
      message_summary: summarize_message(message),
      response_key_points: extract_key_points(result.response),
      timestamp: Time.now.iso8601
    }
    
    DSPy::Memory.manager.store_memory(
      essential_data.to_json,
      user_id: user_id,
      tags: ["essential", "summary"]
    )
  end
  
  def summarize_message(message)
    # Simple summarization
    message.length > 100 ? "#{message[0..97]}..." : message
  end
  
  def extract_key_points(response)
    # Extract key points from response
    response.split('.').first(3).join('. ')
  end
end
```

## Testing Stateful Agents

### Unit Testing with Memory

```ruby
RSpec.describe PersistentAgent do
  let(:agent) { described_class.new }
  
  before do
    DSPy::Memory.reset!  # Clear memory between tests
  end
  
  describe '#forward' do
    it 'remembers information across calls' do
      # First interaction
      result1 = agent.call(
        user_message: "My name is Alice",
        user_id: "user123"
      )
      
      # Second interaction
      result2 = agent.call(
        user_message: "What is my name?",
        user_id: "user123"
      )
      
      expect(result2.response).to include("Alice")
    end
    
    it 'handles different users separately' do
      # User 1
      agent.call(
        user_message: "My name is Alice",
        user_id: "user123"
      )
      
      # User 2
      result = agent.call(
        user_message: "What is my name?",
        user_id: "user456"
      )
      
      expect(result.response).not_to include("Alice")
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Stateful Agent Integration" do
  let(:agent) { MultiContextAgent.new }
  
  before do
    DSPy::Memory.reset!
    DSPy.configure { |config| config.lm = test_lm }
  end
  
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

### 1. Memory Management

- **Tag consistently**: Use consistent tagging strategies for easy retrieval
- **Limit memory size**: Don't store every interaction; focus on important information
- **Clean up regularly**: Use memory compaction to prevent performance degradation

### 2. Error Handling

- **Graceful degradation**: Provide fallback behavior when memory is unavailable
- **State validation**: Validate stored state before using it
- **Recovery mechanisms**: Implement ways to recover from corrupted state

### 3. Performance

- **Batch operations**: Store multiple memories in batches when possible
- **Selective storage**: Only store information that will be useful later
- **Monitor memory usage**: Track memory system performance in production

### 4. Privacy and Security

- **Data minimization**: Store only necessary information
- **User consent**: Ensure users understand what information is being stored
- **Secure storage**: Use appropriate security measures for sensitive data

## Common Pitfalls

### 1. Memory Leaks
```ruby
# BAD: Storing too much detail
DSPy::Memory.manager.store_memory(
  full_conversation_transcript,  # Too much data
  user_id: user_id
)

# GOOD: Store essential information
DSPy::Memory.manager.store_memory(
  conversation_summary,  # Just the key points
  user_id: user_id
)
```

### 2. Context Confusion
```ruby
# BAD: Mixing contexts
def build_context(user_id, session_id)
  all_memories = get_all_memories(user_id)  # Too broad
  all_memories.join("\n")
end

# GOOD: Focused context
def build_context(user_id, session_id)
  recent_memories = get_recent_relevant_memories(user_id, limit: 5)
  recent_memories.map(&:content).join("\n")
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