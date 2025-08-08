# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Memory
    # Simple memory compaction system with inline triggers
    # Handles deduplication, relevance pruning, and conflict resolution
    class MemoryCompactor
      extend T::Sig

      # Compaction thresholds
      DEFAULT_MAX_MEMORIES = 1000
      DEFAULT_MAX_AGE_DAYS = 90
      DEFAULT_SIMILARITY_THRESHOLD = 0.95
      DEFAULT_LOW_ACCESS_THRESHOLD = 0.1

      sig { returns(Integer) }
      attr_reader :max_memories

      sig { returns(Integer) }
      attr_reader :max_age_days

      sig { returns(Float) }
      attr_reader :similarity_threshold

      sig { returns(Float) }
      attr_reader :low_access_threshold

      sig do
        params(
          max_memories: Integer,
          max_age_days: Integer,
          similarity_threshold: Float,
          low_access_threshold: Float
        ).void
      end
      def initialize(
        max_memories: DEFAULT_MAX_MEMORIES,
        max_age_days: DEFAULT_MAX_AGE_DAYS,
        similarity_threshold: DEFAULT_SIMILARITY_THRESHOLD,
        low_access_threshold: DEFAULT_LOW_ACCESS_THRESHOLD
      )
        @max_memories = max_memories
        @max_age_days = max_age_days
        @similarity_threshold = similarity_threshold
        @low_access_threshold = low_access_threshold
      end

      # Main compaction entry point - checks all triggers and compacts if needed
      sig { params(store: MemoryStore, embedding_engine: EmbeddingEngine, user_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      def compact_if_needed!(store, embedding_engine, user_id: nil)
        DSPy::Context.with_span(operation: 'memory.compaction_check', 'memory.user_id' => user_id) do
          results = {}
          
          # Check triggers in order of impact
          if size_compaction_needed?(store, user_id)
            results[:size_compaction] = perform_size_compaction!(store, user_id)
          end
          
          if age_compaction_needed?(store, user_id)
            results[:age_compaction] = perform_age_compaction!(store, user_id)
          end
          
          if duplication_compaction_needed?(store, embedding_engine, user_id)
            results[:deduplication] = perform_deduplication!(store, embedding_engine, user_id)
          end
          
          if relevance_compaction_needed?(store, user_id)
            results[:relevance_pruning] = perform_relevance_pruning!(store, user_id)
          end
          
          results[:total_compacted] = results.values.sum { |r| r.is_a?(Hash) ? r[:removed_count] || 0 : 0 }
          results
        end
      end

      # Check if size-based compaction is needed
      sig { params(store: MemoryStore, user_id: T.nilable(String)).returns(T::Boolean) }
      def size_compaction_needed?(store, user_id)
        store.count(user_id: user_id) > @max_memories
      end

      # Check if age-based compaction is needed
      sig { params(store: MemoryStore, user_id: T.nilable(String)).returns(T::Boolean) }
      def age_compaction_needed?(store, user_id)
        memories = store.list(user_id: user_id)
        return false if memories.empty?
        
        # Check if any memory exceeds the age limit
        memories.any? { |memory| memory.age_in_days > @max_age_days }
      end

      # Check if deduplication is needed (simple heuristic)
      sig { params(store: MemoryStore, embedding_engine: EmbeddingEngine, user_id: T.nilable(String)).returns(T::Boolean) }
      def duplication_compaction_needed?(store, embedding_engine, user_id)
        # Sample recent memories to check for duplicates
        recent_memories = store.list(user_id: user_id, limit: 50)
        return false if recent_memories.length < 10
        
        # Quick duplicate check on a sample
        sample_size = [recent_memories.length / 4, 10].max
        sample = recent_memories.sample(sample_size)
        
        duplicate_count = 0
        sample.each_with_index do |memory1, i|
          sample[(i+1)..-1].each do |memory2|
            next unless memory1.embedding && memory2.embedding
            
            similarity = embedding_engine.cosine_similarity(memory1.embedding, memory2.embedding)
            duplicate_count += 1 if similarity > @similarity_threshold
          end
        end
        
        # Need deduplication if > 20% of sample has duplicates
        (duplicate_count.to_f / sample_size) > 0.2
      end

      # Check if relevance-based pruning is needed
      sig { params(store: MemoryStore, user_id: T.nilable(String)).returns(T::Boolean) }
      def relevance_compaction_needed?(store, user_id)
        memories = store.list(user_id: user_id, limit: 100)
        return false if memories.length < 50
        
        # Check if many memories have low access counts
        total_access = memories.sum(&:access_count)
        return false if total_access == 0
        
        # Calculate relative access for each memory
        low_access_count = memories.count do |memory|
          relative_access = memory.access_count.to_f / total_access
          relative_access < @low_access_threshold
        end
        
        # Need pruning if > 30% of memories have low relative access
        low_access_ratio = low_access_count.to_f / memories.length
        low_access_ratio > 0.3
      end

      private

      # Remove oldest memories when over size limit
      sig { params(store: MemoryStore, user_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      def perform_size_compaction!(store, user_id)
        DSPy::Context.with_span(operation: 'memory.size_compaction', 'memory.user_id' => user_id) do
          current_count = store.count(user_id: user_id)
          target_count = (@max_memories * 0.8).to_i  # Remove to 80% of limit
          remove_count = current_count - target_count
          
          # Don't remove if already under target
          if remove_count <= 0
            return {
              trigger: 'size_limit_exceeded',
              removed_count: 0,
              before_count: current_count,
              after_count: current_count,
              note: 'already_under_target'
            }
          end
          
          # Get oldest memories
          all_memories = store.list(user_id: user_id)
          oldest_memories = all_memories.sort_by(&:created_at).first(remove_count)
          
          removed_count = 0
          oldest_memories.each do |memory|
            if store.delete(memory.id)
              removed_count += 1
            end
          end
          
          {
            trigger: 'size_limit_exceeded',
            removed_count: removed_count,
            before_count: current_count,
            after_count: current_count - removed_count
          }
        end
      end

      # Remove memories older than age limit
      sig { params(store: MemoryStore, user_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      def perform_age_compaction!(store, user_id)
        DSPy::Context.with_span(operation: 'memory.age_compaction', 'memory.user_id' => user_id) do
          cutoff_time = Time.now - (@max_age_days * 24 * 60 * 60)
          all_memories = store.list(user_id: user_id)
          old_memories = all_memories.select { |m| m.created_at < cutoff_time }
          
          removed_count = 0
          old_memories.each do |memory|
            if store.delete(memory.id)
              removed_count += 1
            end
          end
          
          {
            trigger: 'age_limit_exceeded',
            removed_count: removed_count,
            cutoff_age_days: @max_age_days,
            oldest_removed_age: old_memories.empty? ? nil : old_memories.max_by(&:created_at).age_in_days
          }
        end
      end

      # Remove near-duplicate memories using embedding similarity
      sig { params(store: MemoryStore, embedding_engine: EmbeddingEngine, user_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      def perform_deduplication!(store, embedding_engine, user_id)
        DSPy::Context.with_span(operation: 'memory.deduplication', 'memory.user_id' => user_id) do
          memories = store.list(user_id: user_id)
          memories_with_embeddings = memories.select(&:embedding)
          
          duplicates_to_remove = []
          processed = Set.new
          
          memories_with_embeddings.each_with_index do |memory1, i|
            next if processed.include?(memory1.id)
            
            memories_with_embeddings[(i+1)..-1].each do |memory2|
              next if processed.include?(memory2.id)
              
              similarity = embedding_engine.cosine_similarity(memory1.embedding, memory2.embedding)
              
              if similarity > @similarity_threshold
                # Keep the one with higher access count, or newer if tied
                keeper, duplicate = if memory1.access_count > memory2.access_count
                  [memory1, memory2]
                elsif memory1.access_count < memory2.access_count
                  [memory2, memory1]
                else
                  # Tie: keep newer one
                  memory1.created_at > memory2.created_at ? [memory1, memory2] : [memory2, memory1]
                end
                
                duplicates_to_remove << duplicate
                processed.add(duplicate.id)
              end
            end
            
            processed.add(memory1.id)
          end
          
          removed_count = 0
          duplicates_to_remove.uniq.each do |memory|
            if store.delete(memory.id)
              removed_count += 1
            end
          end
          
          {
            trigger: 'duplicate_similarity_detected',
            removed_count: removed_count,
            similarity_threshold: @similarity_threshold,
            total_checked: memories_with_embeddings.length
          }
        end
      end

      # Remove memories with low relevance (low access patterns)
      sig { params(store: MemoryStore, user_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
      def perform_relevance_pruning!(store, user_id)
        DSPy::Context.with_span(operation: 'memory.relevance_pruning', 'memory.user_id' => user_id) do
          memories = store.list(user_id: user_id)
          total_access = memories.sum(&:access_count)
          return { removed_count: 0, trigger: 'no_access_data' } if total_access == 0
          
          # Calculate relevance scores
          scored_memories = memories.map do |memory|
            # Combine access frequency with recency
            access_score = memory.access_count.to_f / total_access
            recency_score = 1.0 / (memory.age_in_days + 1) # Avoid division by zero
            relevance_score = (access_score * 0.7) + (recency_score * 0.3)
            
            { memory: memory, score: relevance_score }
          end
          
          # Remove bottom 20% by relevance
          sorted_by_relevance = scored_memories.sort_by { |item| item[:score] }
          remove_count = (memories.length * 0.2).to_i
          to_remove = sorted_by_relevance.first(remove_count)
          
          removed_count = 0
          to_remove.each do |item|
            if store.delete(item[:memory].id)
              removed_count += 1
            end
          end
          
          {
            trigger: 'low_relevance_detected',
            removed_count: removed_count,
            lowest_score: to_remove.first&.dig(:score),
            highest_score: sorted_by_relevance.last&.dig(:score)
          }
        end
      end
    end
  end
end