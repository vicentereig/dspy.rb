# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'memory_record'
require_relative 'memory_store'
require_relative 'in_memory_store'
require_relative 'embedding_engine'
require_relative 'local_embedding_engine'

module DSPy
  module Memory
    # High-level memory management interface implementing MemoryTools API
    class MemoryManager
      extend T::Sig

      sig { returns(MemoryStore) }
      attr_reader :store

      sig { returns(EmbeddingEngine) }
      attr_reader :embedding_engine

      sig { params(store: T.nilable(MemoryStore), embedding_engine: T.nilable(EmbeddingEngine)).void }
      def initialize(store: nil, embedding_engine: nil)
        @store = store || InMemoryStore.new
        @embedding_engine = embedding_engine || create_default_embedding_engine
      end

      # Store a memory with automatic embedding generation
      sig { params(content: String, user_id: T.nilable(String), tags: T::Array[String], metadata: T::Hash[String, T.untyped]).returns(MemoryRecord) }
      def store_memory(content, user_id: nil, tags: [], metadata: {})
        # Generate embedding for the content
        embedding = @embedding_engine.embed(content)
        
        # Create memory record
        record = MemoryRecord.new(
          content: content,
          user_id: user_id,
          tags: tags,
          embedding: embedding,
          metadata: metadata
        )
        
        # Store in backend
        success = @store.store(record)
        raise "Failed to store memory" unless success
        
        record
      end

      # Retrieve a memory by ID
      sig { params(memory_id: String).returns(T.nilable(MemoryRecord)) }
      def get_memory(memory_id)
        @store.retrieve(memory_id)
      end

      # Update an existing memory
      sig { params(memory_id: String, new_content: String, tags: T.nilable(T::Array[String]), metadata: T.nilable(T::Hash[String, T.untyped])).returns(T::Boolean) }
      def update_memory(memory_id, new_content, tags: nil, metadata: nil)
        record = @store.retrieve(memory_id)
        return false unless record
        
        # Update content and regenerate embedding
        record.update_content!(new_content)
        record.embedding = @embedding_engine.embed(new_content)
        
        # Update tags if provided
        record.tags = tags if tags
        
        # Update metadata if provided
        record.metadata.merge!(metadata) if metadata
        
        @store.update(record)
      end

      # Delete a memory
      sig { params(memory_id: String).returns(T::Boolean) }
      def delete_memory(memory_id)
        @store.delete(memory_id)
      end

      # Get all memories for a user
      sig { params(user_id: T.nilable(String), limit: T.nilable(Integer), offset: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def get_all_memories(user_id: nil, limit: nil, offset: nil)
        @store.list(user_id: user_id, limit: limit, offset: offset)
      end

      # Semantic search using embeddings
      sig { params(query: String, user_id: T.nilable(String), limit: T.nilable(Integer), threshold: T.nilable(Float)).returns(T::Array[MemoryRecord]) }
      def search_memories(query, user_id: nil, limit: 10, threshold: 0.5)
        # Generate embedding for the query
        query_embedding = @embedding_engine.embed(query)
        
        # Perform vector search if supported
        if @store.supports_vector_search?
          @store.vector_search(query_embedding, user_id: user_id, limit: limit, threshold: threshold)
        else
          # Fallback to text search
          @store.search(query, user_id: user_id, limit: limit)
        end
      end

      # Search by tags
      sig { params(tags: T::Array[String], user_id: T.nilable(String), limit: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def search_by_tags(tags, user_id: nil, limit: nil)
        @store.search_by_tags(tags, user_id: user_id, limit: limit)
      end

      # Text-based search (fallback when embeddings not available)
      sig { params(query: String, user_id: T.nilable(String), limit: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def search_text(query, user_id: nil, limit: nil)
        @store.search(query, user_id: user_id, limit: limit)
      end

      # Count memories
      sig { params(user_id: T.nilable(String)).returns(Integer) }
      def count_memories(user_id: nil)
        @store.count(user_id: user_id)
      end

      # Clear all memories for a user
      sig { params(user_id: T.nilable(String)).returns(Integer) }
      def clear_memories(user_id: nil)
        @store.clear(user_id: user_id)
      end

      # Find similar memories to a given memory
      sig { params(memory_id: String, limit: T.nilable(Integer), threshold: T.nilable(Float)).returns(T::Array[MemoryRecord]) }
      def find_similar(memory_id, limit: 5, threshold: 0.7)
        record = @store.retrieve(memory_id)
        return [] unless record&.embedding
        
        results = @store.vector_search(record.embedding, user_id: record.user_id, limit: limit + 1, threshold: threshold)
        
        # Remove the original record from results
        results.reject { |r| r.id == memory_id }
      end

      # Batch operations
      sig { params(contents: T::Array[String], user_id: T.nilable(String), tags: T::Array[String]).returns(T::Array[MemoryRecord]) }
      def store_memories_batch(contents, user_id: nil, tags: [])
        # Generate embeddings in batch for efficiency
        embeddings = @embedding_engine.embed_batch(contents)
        
        records = contents.zip(embeddings).map do |content, embedding|
          MemoryRecord.new(
            content: content,
            user_id: user_id,
            tags: tags,
            embedding: embedding
          )
        end
        
        # Store all records
        results = @store.store_batch(records)
        
        # Return only successfully stored records
        records.select.with_index { |_, idx| results[idx] }
      end

      # Get memory statistics
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def stats
        store_stats = @store.stats
        engine_stats = @embedding_engine.stats
        
        {
          store: store_stats,
          embedding_engine: engine_stats,
          total_memories: store_stats[:total_memories] || 0
        }
      end

      # Health check
      sig { returns(T::Boolean) }
      def healthy?
        @embedding_engine.ready? && @store.respond_to?(:count)
      end

      # Export memories to hash format
      sig { params(user_id: T.nilable(String)).returns(T::Array[T::Hash[String, T.untyped]]) }
      def export_memories(user_id: nil)
        memories = get_all_memories(user_id: user_id)
        memories.map(&:to_h)
      end

      # Import memories from hash format
      sig { params(memories_data: T::Array[T::Hash[String, T.untyped]]).returns(Integer) }
      def import_memories(memories_data)
        records = memories_data.map { |data| MemoryRecord.from_h(data) }
        results = @store.store_batch(records)
        results.count(true)
      end

      private

      # Create default embedding engine
      sig { returns(EmbeddingEngine) }
      def create_default_embedding_engine
        LocalEmbeddingEngine.new
      rescue => e
        # Fallback to no-op engine if local engine fails
        NoOpEmbeddingEngine.new
      end
    end
  end
end