# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Memory
    # Abstract base class for memory storage backends
    class MemoryStore
      extend T::Sig
      extend T::Helpers
      abstract!

      # Store a memory record
      sig { abstract.params(record: MemoryRecord).returns(T::Boolean) }
      def store(record); end

      # Retrieve a memory record by ID
      sig { abstract.params(id: String).returns(T.nilable(MemoryRecord)) }
      def retrieve(id); end

      # Update an existing memory record
      sig { abstract.params(record: MemoryRecord).returns(T::Boolean) }
      def update(record); end

      # Delete a memory record by ID
      sig { abstract.params(id: String).returns(T::Boolean) }
      def delete(id); end

      # List all memory records for a user
      sig { abstract.params(user_id: T.nilable(String), limit: T.nilable(Integer), offset: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def list(user_id: nil, limit: nil, offset: nil); end

      # Search memories by content (basic text search)
      sig { abstract.params(query: String, user_id: T.nilable(String), limit: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def search(query, user_id: nil, limit: nil); end

      # Search memories by tags
      sig { abstract.params(tags: T::Array[String], user_id: T.nilable(String), limit: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def search_by_tags(tags, user_id: nil, limit: nil); end

      # Vector similarity search (if supported by backend)
      sig { abstract.params(embedding: T::Array[Float], user_id: T.nilable(String), limit: T.nilable(Integer), threshold: T.nilable(Float)).returns(T::Array[MemoryRecord]) }
      def vector_search(embedding, user_id: nil, limit: nil, threshold: nil); end

      # Count total memories
      sig { abstract.params(user_id: T.nilable(String)).returns(Integer) }
      def count(user_id: nil); end

      # Clear all memories for a user (or all if user_id is nil)
      sig { abstract.params(user_id: T.nilable(String)).returns(Integer) }
      def clear(user_id: nil); end

      # Check if the store supports vector search
      sig { returns(T::Boolean) }
      def supports_vector_search?
        false
      end

      # Get store statistics
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def stats
        {
          total_memories: count,
          supports_vector_search: supports_vector_search?
        }
      end

      # Batch operations
      sig { params(records: T::Array[MemoryRecord]).returns(T::Array[T::Boolean]) }
      def store_batch(records)
        records.map { |record| store(record) }
      end

      sig { params(ids: T::Array[String]).returns(T::Array[T.nilable(MemoryRecord)]) }
      def retrieve_batch(ids)
        ids.map { |id| retrieve(id) }
      end

      sig { params(records: T::Array[MemoryRecord]).returns(T::Array[T::Boolean]) }
      def update_batch(records)
        records.map { |record| update(record) }
      end

      sig { params(ids: T::Array[String]).returns(T::Array[T::Boolean]) }
      def delete_batch(ids)
        ids.map { |id| delete(id) }
      end
    end
  end
end