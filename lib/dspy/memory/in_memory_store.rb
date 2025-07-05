# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'memory_store'

module DSPy
  module Memory
    # In-memory implementation of MemoryStore for development and testing
    class InMemoryStore < MemoryStore
      extend T::Sig

      sig { void }
      def initialize
        @memories = T.let({}, T::Hash[String, MemoryRecord])
        @mutex = T.let(Mutex.new, Mutex)
      end

      sig { override.params(record: MemoryRecord).returns(T::Boolean) }
      def store(record)
        @mutex.synchronize do
          @memories[record.id] = record
          true
        end
      end

      sig { override.params(id: String).returns(T.nilable(MemoryRecord)) }
      def retrieve(id)
        @mutex.synchronize do
          record = @memories[id]
          record&.record_access!
          record
        end
      end

      sig { override.params(record: MemoryRecord).returns(T::Boolean) }
      def update(record)
        @mutex.synchronize do
          if @memories.key?(record.id)
            @memories[record.id] = record
            true
          else
            false
          end
        end
      end

      sig { override.params(id: String).returns(T::Boolean) }
      def delete(id)
        @mutex.synchronize do
          @memories.delete(id) ? true : false
        end
      end

      sig { override.params(user_id: T.nilable(String), limit: T.nilable(Integer), offset: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def list(user_id: nil, limit: nil, offset: nil)
        @mutex.synchronize do
          records = @memories.values
          
          # Filter by user_id if provided
          records = records.select { |r| r.user_id == user_id } if user_id
          
          # Sort by created_at (newest first)
          records = records.sort_by(&:created_at).reverse
          
          # Apply offset and limit
          records = records.drop(offset) if offset
          records = records.take(limit) if limit
          
          records
        end
      end

      sig { override.params(query: String, user_id: T.nilable(String), limit: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def search(query, user_id: nil, limit: nil)
        @mutex.synchronize do
          regex = Regexp.new(Regexp.escape(query), Regexp::IGNORECASE)
          
          records = @memories.values.select do |record|
            # Filter by user_id if provided
            next false if user_id && record.user_id != user_id
            
            # Search in content and tags
            record.content.match?(regex) || record.tags.any? { |tag| tag.match?(regex) }
          end
          
          # Sort by relevance (exact matches first, then by recency)
          records = records.sort_by do |record|
            exact_match = record.content.downcase.include?(query.downcase) ? 0 : 1
            [exact_match, -record.created_at.to_f]
          end
          
          records = records.take(limit) if limit
          records
        end
      end

      sig { override.params(tags: T::Array[String], user_id: T.nilable(String), limit: T.nilable(Integer)).returns(T::Array[MemoryRecord]) }
      def search_by_tags(tags, user_id: nil, limit: nil)
        @mutex.synchronize do
          records = @memories.values.select do |record|
            # Filter by user_id if provided
            next false if user_id && record.user_id != user_id
            
            # Check if record has any of the specified tags
            tags.any? { |tag| record.has_tag?(tag) }
          end
          
          # Sort by number of matching tags, then by recency
          records = records.sort_by do |record|
            matching_tags = tags.count { |tag| record.has_tag?(tag) }
            [-matching_tags, -record.created_at.to_f]
          end
          
          records = records.take(limit) if limit
          records
        end
      end

      sig { override.params(embedding: T::Array[Float], user_id: T.nilable(String), limit: T.nilable(Integer), threshold: T.nilable(Float)).returns(T::Array[MemoryRecord]) }
      def vector_search(embedding, user_id: nil, limit: nil, threshold: nil)
        @mutex.synchronize do
          records_with_similarity = []
          
          @memories.values.each do |record|
            # Filter by user_id if provided
            next if user_id && record.user_id != user_id
            
            # Skip records without embeddings
            next unless record.embedding
            
            # Calculate cosine similarity
            similarity = cosine_similarity(embedding, record.embedding)
            
            # Apply threshold if provided
            next if threshold && similarity < threshold
            
            records_with_similarity << [record, similarity]
          end
          
          # Sort by similarity (highest first)
          records_with_similarity.sort_by! { |_, similarity| -similarity }
          
          # Apply limit
          records_with_similarity = records_with_similarity.take(limit) if limit
          
          # Return just the records
          records_with_similarity.map(&:first)
        end
      end

      sig { override.params(user_id: T.nilable(String)).returns(Integer) }
      def count(user_id: nil)
        @mutex.synchronize do
          if user_id
            @memories.values.count { |record| record.user_id == user_id }
          else
            @memories.size
          end
        end
      end

      sig { override.params(user_id: T.nilable(String)).returns(Integer) }
      def clear(user_id: nil)
        @mutex.synchronize do
          if user_id
            count = @memories.values.count { |record| record.user_id == user_id }
            @memories.reject! { |_, record| record.user_id == user_id }
            count
          else
            count = @memories.size
            @memories.clear
            count
          end
        end
      end

      sig { override.returns(T::Boolean) }
      def supports_vector_search?
        true
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def stats
        @mutex.synchronize do
          total = @memories.size
          with_embeddings = @memories.values.count(&:embedding)
          users = @memories.values.map(&:user_id).compact.uniq.size
          
          {
            total_memories: total,
            memories_with_embeddings: with_embeddings,
            unique_users: users,
            supports_vector_search: supports_vector_search?,
            avg_access_count: total > 0 ? @memories.values.sum(&:access_count) / total.to_f : 0
          }
        end
      end

      private

      # Calculate cosine similarity between two vectors
      sig { params(a: T::Array[Float], b: T::Array[Float]).returns(Float) }
      def cosine_similarity(a, b)
        return 0.0 if a.empty? || b.empty? || a.size != b.size
        
        dot_product = a.zip(b).sum { |x, y| x * y }
        magnitude_a = Math.sqrt(a.sum { |x| x * x })
        magnitude_b = Math.sqrt(b.sum { |x| x * x })
        
        return 0.0 if magnitude_a == 0.0 || magnitude_b == 0.0
        
        dot_product / (magnitude_a * magnitude_b)
      end
    end
  end
end