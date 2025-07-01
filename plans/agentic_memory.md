# Agentic Memory Implementation Plan

## Overview

This plan outlines the implementation of a comprehensive agentic memory system for DSPy.rb, inspired by the MemoryTools API design pattern and informed by modern context engineering research. The system will provide agents with persistent, searchable memory capabilities while addressing the four primary context failure modes: poisoning, distraction, confusion, and clash.

## Research Foundation

### Context Engineering Insights

Based on recent research by Drew Breunig and Simon Willison, we must address:

1. **Context Poisoning**: Hallucinations embedded in context get repeatedly referenced
2. **Context Distraction**: Extensive context causes models to repeat past actions instead of generating novel solutions
3. **Context Confusion**: Superfluous context leads to low-quality responses
4. **Context Clash**: Conflicting information within accumulated context causes reasoning failures

### MemoryTools API Design

The inspiration comes from DSPy's MemoryTools API with these core operations:
- `store_memory(content, user_id)` - Store information with user context
- `search_memories(query, user_id, limit)` - Semantic search for relevant memories
- `get_all_memories(user_id)` - Retrieve complete memory history
- `update_memory(memory_id, new_content)` - Update existing memories
- `delete_memory(memory_id)` - Remove memories

## Architecture Design

### Core Components

```
DSPy::Memory
├── MemoryStore          # Storage abstraction layer
├── EmbeddingEngine      # Vector embedding generation
├── MemoryManager        # High-level memory operations
├── ContextEngineer      # Smart context assembly
└── MemoryTools          # Agent-facing tool interface
```

### Memory Store Layer

```ruby
module DSPy
  class MemoryStore
    # Abstract base class for memory storage backends
    def store(memory_record); end
    def search(query_embedding, limit: 10, user_id: nil); end
    def retrieve(memory_id); end
    def update(memory_id, updates); end
    def delete(memory_id); end
    def list_all(user_id: nil); end
  end
  
  class InMemoryStore < MemoryStore
    # In-memory implementation for development/testing
  end
  
  class FileStore < MemoryStore
    # File-based storage with JSON serialization
  end
  
  class RedisStore < MemoryStore
    # Redis-based storage for production caching and fast retrieval
    def initialize(redis_client = nil)
      @redis = redis_client || Redis.new
    end
    
    def store(memory_record)
      key = "memory:#{memory_record.id}"
      @redis.hset(key, memory_record.to_h)
      @redis.expire(key, 86400) # 24 hours default TTL
      
      # Store in user index
      if memory_record.user_id
        user_key = "user_memories:#{memory_record.user_id}"
        @redis.sadd(user_key, memory_record.id)
      end
      
      # Store embedding for vector search (using Redis Vector Similarity)
      embedding_key = "embedding:#{memory_record.id}"
      @redis.hset(embedding_key, {
        vector: memory_record.embedding.to_json,
        content: memory_record.content,
        user_id: memory_record.user_id
      })
    end
    
    def search(query_embedding, limit: 10, user_id: nil)
      # Use Redis Vector Similarity Search (Redis Stack)
      search_cmd = ["FT.SEARCH", "embedding_idx"]
      
      if user_id
        search_cmd += ["@user_id:{#{user_id}}"]
      end
      
      # Vector similarity search
      search_cmd += [
        "=>[KNN", limit.to_s, "@vector", "$query_vec",
        "AS", "distance"
      ]
      
      results = @redis.call(search_cmd, "PARAMS", 2, "query_vec", query_embedding.to_json)
      parse_search_results(results)
    end
  end
  
  class ActiveRecordStore < MemoryStore
    # ActiveRecord-based storage for relational database persistence
    def initialize(model_class = nil)
      @model_class = model_class || DSPy::Memory::Record
    end
    
    def store(memory_record)
      @model_class.create!(
        external_id: memory_record.id,
        content: memory_record.content,
        user_id: memory_record.user_id,
        metadata: memory_record.metadata,
        embedding: memory_record.embedding,
        created_at: memory_record.created_at,
        updated_at: memory_record.updated_at
      )
    end
    
    def search(query_embedding, limit: 10, user_id: nil)
      scope = @model_class.all
      scope = scope.where(user_id: user_id) if user_id
      
      # Use pgvector for similarity search if available
      if @model_class.connection.adapter_name.downcase.include?('postgresql')
        scope = scope.order("embedding <-> '#{query_embedding}'::vector")
      else
        # Fallback to content-based search
        scope = scope.where("content ILIKE ?", "%#{extract_keywords(query_embedding)}%")
      end
      
      scope.limit(limit).map(&:to_memory_record)
    end
    
    def retrieve(memory_id)
      record = @model_class.find_by(external_id: memory_id)
      record&.to_memory_record
    end
    
    def update(memory_id, updates)
      @model_class.find_by(external_id: memory_id)&.update!(updates)
    end
    
    def delete(memory_id)
      @model_class.find_by(external_id: memory_id)&.destroy
    end
    
    def list_all(user_id: nil)
      scope = @model_class.all
      scope = scope.where(user_id: user_id) if user_id
      scope.map(&:to_memory_record)
    end
  end
end

# ActiveRecord model for database storage
module DSPy
  module Memory
    class Record < ActiveRecord::Base
      self.table_name = 'dspy_memories'
      
      # Define the table structure
      # t.string :external_id, null: false, index: true
      # t.text :content, null: false
      # t.string :user_id, index: true
      # t.json :metadata
      # t.vector :embedding, limit: 1536  # For pgvector
      # t.integer :access_count, default: 0
      # t.datetime :last_accessed_at
      # t.timestamps
      
      validates :external_id, presence: true, uniqueness: true
      validates :content, presence: true
      
      def to_memory_record
        MemoryRecord.new(
          id: external_id,
          content: content,
          user_id: user_id,
          metadata: metadata || {},
          embedding: embedding,
          created_at: created_at,
          updated_at: updated_at,
          access_count: access_count,
          last_accessed_at: last_accessed_at
        )
      end
    end
  end
end
```

### Memory Record Structure

```ruby
class MemoryRecord < T::Struct
  const :id, String
  const :content, String
  const :user_id, T.nilable(String)
  const :metadata, T::Hash[String, T.untyped]
  const :embedding, T::Array[Float]
  const :created_at, Time
  const :updated_at, Time
  const :relevance_score, T.nilable(Float)
  const :access_count, Integer
  const :last_accessed_at, T.nilable(Time)
end
```

### Embedding Engine

```ruby
module DSPy
  class EmbeddingEngine
    # Strategy pattern for different embedding providers
    def generate_embedding(text); end
  end
  
  class LocalEmbeddingEngine < EmbeddingEngine
    # Uses ankane/informers for local embeddings
    def initialize(model: "sentence-transformers/all-MiniLM-L6-v2")
      @model = Informers.pipeline("embedding", model)
    end
  end
  
  class OpenAIEmbeddingEngine < EmbeddingEngine
    # Uses OpenAI's text-embedding-3-small
    def initialize(client: nil)
      @client = client || OpenAI::Client.new
    end
  end
  
  class AnthropicEmbeddingEngine < EmbeddingEngine
    # Future: When Anthropic releases embedding models
  end
end
```

### Context Engineering Layer

```ruby
module DSPy
  class ContextEngineer
    # Implements context engineering best practices
    def assemble_context(memories, max_tokens: 4000)
      # 1. Context Pruning: Remove irrelevant memories
      # 2. Context Summarization: Condense when needed
      # 3. Context Quarantine: Separate conflicting info
      # 4. Smart Ordering: Most relevant first
    end
    
    private
    
    def detect_conflicts(memories); end
    def relevance_score(memory, query); end
    def summarize_memories(memories); end
    def prune_irrelevant(memories, threshold: 0.3); end
  end
end
```

### Memory Manager

```ruby
module DSPy
  class MemoryManager
    def initialize(
      store: InMemoryStore.new,
      embedding_engine: LocalEmbeddingEngine.new,
      context_engineer: ContextEngineer.new
    )
      @store = store
      @embedding_engine = embedding_engine
      @context_engineer = context_engineer
    end
    
    def store_memory(content, user_id: nil, metadata: {})
      embedding = @embedding_engine.generate_embedding(content)
      record = MemoryRecord.new(
        id: SecureRandom.uuid,
        content: content,
        user_id: user_id,
        metadata: metadata,
        embedding: embedding,
        created_at: Time.current,
        updated_at: Time.current,
        access_count: 0
      )
      @store.store(record)
    end
    
    def search_memories(query, user_id: nil, limit: 10)
      query_embedding = @embedding_engine.generate_embedding(query)
      memories = @store.search(query_embedding, limit: limit * 2, user_id: user_id)
      
      # Apply context engineering principles
      @context_engineer.assemble_context(memories, max_tokens: 4000)
        .take(limit)
    end
    
    def get_contextual_memories(query, user_id: nil)
      memories = search_memories(query, user_id: user_id, limit: 20)
      @context_engineer.assemble_context(memories)
    end
  end
end
```

## Agent Integration

### MemoryTools for DSPy::React

```ruby
module DSPy
  class MemoryTools
    include T::Sig
    
    def initialize(memory_manager: MemoryManager.new, user_id: nil)
      @memory_manager = memory_manager
      @user_id = user_id
    end
    
    sig { params(content: String).returns(String) }
    def store_memory(content)
      result = @memory_manager.store_memory(content, user_id: @user_id)
      "Memory stored with ID: #{result.id}"
    end
    
    sig { params(query: String, limit: Integer).returns(String) }
    def search_memories(query, limit = 5)
      memories = @memory_manager.search_memories(query, user_id: @user_id, limit: limit)
      memories.map { |m| "#{m.id}: #{m.content}" }.join("\n")
    end
    
    sig { returns(String) }
    def get_all_memories
      memories = @memory_manager.get_all_memories(user_id: @user_id)
      memories.map { |m| "#{m.created_at}: #{m.content}" }.join("\n")
    end
    
    sig { params(memory_id: String, new_content: String).returns(String) }
    def update_memory(memory_id, new_content)
      @memory_manager.update_memory(memory_id, new_content)
      "Memory #{memory_id} updated successfully"
    end
    
    sig { params(memory_id: String).returns(String) }
    def delete_memory(memory_id)
      @memory_manager.delete_memory(memory_id)
      "Memory #{memory_id} deleted successfully"
    end
  end
end
```

### React Agent Integration

```ruby
class MemoryReactAgent < DSPy::React
  def initialize(memory_manager: nil, user_id: nil, **kwargs)
    @memory_tools = MemoryTools.new(
      memory_manager: memory_manager || MemoryManager.new,
      user_id: user_id
    )
    
    super(
      tools: default_tools + memory_tool_definitions,
      **kwargs
    )
  end
  
  private
  
  def memory_tool_definitions
    [
      {
        name: "store_memory",
        description: "Store information in long-term memory for future reference",
        parameters: {
          type: "object",
          properties: {
            content: {
              type: "string",
              description: "The information to store in memory"
            }
          },
          required: ["content"]
        }
      },
      {
        name: "search_memories",
        description: "Search stored memories for relevant information",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query to find relevant memories"
            },
            limit: {
              type: "integer",
              description: "Maximum number of memories to return (default: 5)"
            }
          },
          required: ["query"]
        }
      }
      # ... other memory tools
    ]
  end
  
  def execute_tool(tool_name, parameters)
    case tool_name
    when "store_memory"
      @memory_tools.store_memory(parameters["content"])
    when "search_memories"
      @memory_tools.search_memories(
        parameters["query"], 
        parameters["limit"] || 5
      )
    # ... other memory tools
    else
      super
    end
  end
end
```

## Configuration System

```ruby
module DSPy
  class Configuration
    # Add memory configuration options
    attr_accessor :memory_store_backend
    attr_accessor :memory_store_options
    attr_accessor :embedding_engine
    attr_accessor :memory_context_window
    attr_accessor :memory_relevance_threshold
    
    def initialize
      @memory_store_backend = :in_memory
      @memory_store_options = {}
      @embedding_engine = :local
      @memory_context_window = 4000
      @memory_relevance_threshold = 0.3
    end
  end
end

# Usage Examples

# In-memory for development
DSPy.configure do |config|
  config.memory_store_backend = :in_memory
  config.embedding_engine = :local
end

# Redis for production caching
DSPy.configure do |config|
  config.memory_store_backend = :redis
  config.memory_store_options = {
    redis_client: Redis.new(url: ENV['REDIS_URL']),
    ttl: 86400,  # 24 hours
    namespace: 'dspy_memories'
  }
  config.embedding_engine = :openai
end

# ActiveRecord for persistent storage
DSPy.configure do |config|
  config.memory_store_backend = :activerecord
  config.memory_store_options = {
    model_class: CustomMemoryModel,  # Optional custom model
    enable_pgvector: true            # Use pgvector for similarity search
  }
  config.embedding_engine = :openai
end

# File-based for simple persistence
DSPy.configure do |config|
  config.memory_store_backend = :file
  config.memory_store_options = {
    storage_path: Rails.root.join('storage', 'dspy_memories'),
    compression: true,
    encryption_key: ENV['DSPY_MEMORY_ENCRYPTION_KEY']
  }
  config.embedding_engine = :local
end
```

## Implementation Phases

### Phase 1: Core Memory System (2 weeks)
- [ ] Implement MemoryRecord structure
- [ ] Create MemoryStore abstraction with InMemoryStore
- [ ] Implement LocalEmbeddingEngine using ankane/informers
- [ ] Basic MemoryManager functionality
- [ ] Unit tests for core components

### Phase 2: Context Engineering (1 week)
- [ ] Implement ContextEngineer with pruning/summarization
- [ ] Add conflict detection algorithms
- [ ] Implement relevance scoring
- [ ] Integration tests with various context scenarios

### Phase 3: Agent Integration (1 week)
- [ ] Create MemoryTools interface
- [ ] Integrate with DSPy::React
- [ ] Tool definition system
- [ ] End-to-end integration tests

### Phase 4: Advanced Backends (2 weeks)
- [ ] FileStore implementation with JSON serialization
- [ ] DatabaseStore with PostgreSQL + pgvector
- [ ] OpenAI embedding engine integration
- [ ] Performance optimization and benchmarking

### Phase 5: Production Features (1 week)
- [ ] Memory analytics and metrics
- [ ] Logging and error handling
- [ ] Memory cleanup and archival
- [ ] Configuration system
- [ ] Documentation and examples

## Local Embedding Models

### Recommended Models via ankane/informers

Based on research and testing:

1. **sentence-transformers/all-MiniLM-L6-v2** (Default)
   - Size: ~90MB
   - Speed: Fast
   - Quality: Good for general-purpose memory storage
   - Best for: Development and testing

2. **sentence-transformers/all-mpnet-base-v2**
   - Size: ~420MB
   - Speed: Moderate
   - Quality: High quality embeddings
   - Best for: Production applications requiring high accuracy

3. **mixedbread-ai/mxbai-embed-large-v1**
   - Size: ~1.2GB
   - Speed: Slower but high quality
   - Quality: State-of-the-art performance
   - Best for: Applications requiring maximum accuracy

4. **BAAI/bge-base-en-v1.5**
   - Size: ~420MB
   - Speed: Fast
   - Quality: Excellent for retrieval tasks
   - Best for: Memory search and retrieval optimization

### Usage Pattern

```ruby
# Configure different models for different use cases
DSPy.configure do |config|
  config.embedding_engine = :local
  config.local_embedding_model = case Rails.env
    when 'development'
      'sentence-transformers/all-MiniLM-L6-v2'
    when 'production'
      'BAAI/bge-base-en-v1.5'
    end
end
```

## Ollama Integration for Local Models

### Research Summary

Ruby ecosystem has several mature Ollama clients:

1. **ollama-ai** (by gbaptista)
   - Comprehensive API coverage
   - Server-sent events support
   - Low-level access for building abstractions
   - **Recommended choice**

2. **ollama-ruby** (by flori)
   - Full-featured client with CLI
   - Interactive console for testing
   - Well-documented API

3. **ruby-openai** compatibility
   - Can be configured to use Ollama endpoints
   - Familiar OpenAI-style interface

### Implementation Plan

#### Phase 1: Basic Ollama Support

```ruby
# Add to gemspec
spec.add_dependency "ollama-ai", "~> 1.3"

# Ollama LM adapter
module DSPy
  class LM
    class OllamaAdapter < BaseAdapter
      def initialize(model, host: 'http://localhost:11434', **options)
        @client = Ollama.new(
          credentials: { address: host },
          options: { server_sent_events: true }
        )
        @model = model
        @options = options
      end
      
      def generate(prompt, **params)
        result = @client.generate({
          model: @model,
          prompt: prompt,
          **params.merge(@options)
        })
        
        result['response']
      end
      
      def chat(messages, **params)
        result = @client.chat({
          model: @model,
          messages: messages,
          **params.merge(@options)
        })
        
        result.dig('message', 'content')
      end
    end
  end
end
```

#### Phase 2: Ollama Embedding Support

```ruby
module DSPy
  class OllamaEmbeddingEngine < EmbeddingEngine
    def initialize(model: 'mxbai-embed-large', host: 'http://localhost:11434')
      @client = Ollama.new(
        credentials: { address: host },
        options: { server_sent_events: false }
      )
      @model = model
    end
    
    def generate_embedding(text)
      result = @client.embeddings({
        model: @model,
        prompt: text
      })
      
      result['embedding']
    end
  end
end
```

#### Phase 3: Configuration Integration

```ruby
DSPy.configure do |config|
  # Use Ollama for both LLM and embeddings
  config.lm = DSPy::LM.new('ollama/llama3', host: 'http://localhost:11434')
  config.embedding_engine = :ollama
  config.ollama_embedding_model = 'mxbai-embed-large'
  config.ollama_host = 'http://localhost:11434'
end
```

#### Phase 4: Recommended Ollama Models

**For Text Generation:**
- `llama3` - General purpose, good reasoning
- `mistral` - Fast, efficient for agent tasks
- `codellama` - Enhanced for code-related memories
- `neural-chat` - Optimized for conversational agents

**For Embeddings:**
- `mxbai-embed-large` - High-quality embeddings (default)
- `nomic-embed-text` - Good balance of speed/quality
- `all-minilm` - Lightweight option

### Setup Documentation

```markdown
## Local Models with Ollama

### Prerequisites

1. Install Ollama: https://ollama.ai/
2. Pull required models:
   ```bash
   ollama pull llama3
   ollama pull mxbai-embed-large
   ```

### Configuration

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new('ollama/llama3')
  config.embedding_engine = :ollama
  config.ollama_embedding_model = 'mxbai-embed-large'
end
```

### Memory-Enhanced Agent Example

```ruby
# Create agent with local Ollama models
agent = MemoryReactAgent.new(
  memory_manager: MemoryManager.new(
    embedding_engine: OllamaEmbeddingEngine.new
  ),
  user_id: 'demo_user'
)

# Agent automatically uses local models for both reasoning and memory
response = agent.call(input: "Remember that I prefer Python over Ruby for data science tasks")
```
## Testing Strategy

### Unit Tests
- Memory storage/retrieval operations
- Embedding generation and similarity
- Context engineering algorithms
- Tool integration with React agents

### Integration Tests
- End-to-end memory workflows
- Multi-agent memory sharing
- Context failure mode prevention
- Performance with large memory stores

### Benchmarks
- Memory retrieval latency
- Embedding generation speed
- Context assembly performance
- Memory accuracy across different models

## Success Metrics

1. **Memory Accuracy**: Relevant memory retrieval rate > 90%
2. **Context Quality**: Reduced context failure incidents by 75%
3. **Performance**: Memory operations < 100ms average
4. **Agent Effectiveness**: Improved task completion rates with memory
5. **Developer Experience**: Simple 3-line integration for existing agents

## Future Enhancements

### Advanced Memory Types
- **Episodic Memory**: Event-based memories with temporal relationships
- **Semantic Memory**: Fact-based knowledge storage
- **Procedural Memory**: Skill and process memories
- **Meta-Memory**: Memory about memory usage patterns

### Memory Optimization
- **Hierarchical Memory**: Multi-level memory organization
- **Memory Consolidation**: Automatic memory merging and summarization
- **Forgetting Mechanisms**: Intelligent memory cleanup
- **Memory Sharing**: Cross-agent memory networks

### Enterprise Features
- **Memory Governance**: Access controls and audit trails
- **Memory Analytics**: Usage patterns and optimization insights
- **Distributed Memory**: Multi-instance memory synchronization
- **Memory Backup/Restore**: Enterprise data protection

## Dependencies to Add

```ruby
# Core memory system
spec.add_dependency "informers", "~> 0.7"  # Local embeddings

# Redis support (optional)
spec.add_dependency "redis", "~> 5.0"      # Redis client
spec.add_dependency "redis-stack", "~> 1.0"  # Redis Stack for vector search

# ActiveRecord support (optional)
spec.add_dependency "activerecord", ">= 7.0"  # ActiveRecord ORM

# Vector storage (optional)
spec.add_dependency "pg", "~> 1.5"        # PostgreSQL for pgvector
spec.add_dependency "pgvector", "~> 0.2"  # Vector similarity search

# Ollama support (optional)
spec.add_dependency "ollama-ai", "~> 1.3"

# Serialization and utilities
spec.add_dependency "oj", "~> 3.16"       # Fast JSON processing
spec.add_dependency "concurrent-ruby", "~> 1.2"  # Thread-safe data structures
```

## Database Migration for ActiveRecord

```ruby
# db/migrate/create_dspy_memories.rb
class CreateDspyMemories < ActiveRecord::Migration[7.0]
  def change
    create_table :dspy_memories do |t|
      t.string :external_id, null: false, index: { unique: true }
      t.text :content, null: false
      t.string :user_id, index: true
      t.json :metadata
      t.integer :access_count, default: 0
      t.datetime :last_accessed_at
      t.timestamps
      
      # Add vector column if using pgvector
      if connection.adapter_name.downcase.include?('postgresql')
        t.vector :embedding, limit: 1536  # OpenAI embedding size
        t.index :embedding, using: :ivfflat, opclass: :vector_cosine_ops
      else
        t.text :embedding_json  # Fallback for other databases
      end
    end
    
    add_index :dspy_memories, [:user_id, :created_at]
    add_index :dspy_memories, :access_count
  end
end
```

## Redis Setup for Vector Search

```bash
# Install Redis Stack (includes RedisSearch for vector similarity)
docker run -d --name redis-stack -p 6379:6379 -p 8001:8001 redis/redis-stack:latest

# Or using Redis Cloud with vector search capabilities
```

```ruby
# Initialize Redis vector index
def setup_redis_vector_index(redis_client)
  # Create vector similarity search index
  begin
    redis_client.call([
      "FT.CREATE", "embedding_idx",
      "ON", "HASH",
      "PREFIX", "1", "embedding:",
      "SCHEMA",
      "user_id", "TAG",
      "content", "TEXT",
      "vector", "VECTOR", "FLAT", "6",
      "TYPE", "FLOAT32",
      "DIM", "1536",  # OpenAI embedding dimensions
      "DISTANCE_METRIC", "COSINE"
    ])
  rescue Redis::CommandError => e
    # Index already exists
    puts "Vector index already exists: #{e.message}" if e.message.include?("Index already exists")
  end
end
```

This comprehensive plan provides a production-ready agentic memory system that addresses modern context engineering challenges while providing flexible integration options for different deployment scenarios.
