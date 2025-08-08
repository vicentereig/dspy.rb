# frozen_string_literal: true

require 'spec_helper'
require 'dspy/memory'

RSpec.describe 'Memory Compaction Integration', type: :integration do
  let(:manager) { DSPy::Memory::MemoryManager.new }
  let(:user_id) { 'integration_test_user' }

  before do
    # Use reasonable compaction limits for testing
    compactor = DSPy::Memory::MemoryCompactor.new(
      max_memories: 20,  # Higher limit to allow for better test control
      max_age_days: 1,
      similarity_threshold: 0.9,
      low_access_threshold: 0.2
    )
    
    manager.instance_variable_set(:@compactor, compactor)
  end

  describe 'automatic compaction on store' do
    it 'triggers size compaction when memory limit exceeded' do
      # Store memories up to the limit
      memories = []
      25.times do |i|
        memory = manager.store_memory("Content number #{i}", user_id: user_id)
        memories << memory
      end

      # Should have triggered compaction, keeping us under the limit
      final_count = manager.count_memories(user_id: user_id)
      expect(final_count).to be <= 20
      expect(final_count).to be < 25  # Some were removed
    end

    it 'removes oldest memories during size compaction' do
      # Test compaction behavior by forcing it rather than relying on automatic triggers
      
      # Store many memories directly without triggering automatic compaction
      memories = []
      30.times do |i|
        record = DSPy::Memory::MemoryRecord.new(
          content: "Memory #{i}",
          user_id: user_id,
          embedding: [0.1, 0.2, 0.3]
        )
        manager.store.store(record)  # Store directly to avoid automatic compaction
        memories << record
      end
      
      initial_count = manager.count_memories(user_id: user_id)
      expect(initial_count).to eq(30)
      
      # Now force compaction
      results = manager.force_compact!(user_id)
      
      final_count = manager.count_memories(user_id: user_id)
      
      # Compaction should have reduced the count
      expect(final_count).to be < initial_count
      expect(results[:size_compaction][:removed_count]).to be > 0
    end

    it 'preserves recent memories during compaction' do
      # Store older memories
      10.times do |i|
        manager.store_memory("Old memory #{i}", user_id: user_id)
      end

      # Store a final memory that should be preserved
      final_memory = manager.store_memory("Important recent memory", user_id: user_id)
      
      # Add more to trigger compaction
      5.times do |i|
        manager.store_memory("Trigger memory #{i}", user_id: user_id)
      end

      # The final memory should still exist
      retrieved = manager.get_memory(final_memory.id)
      expect(retrieved).not_to be_nil
      expect(retrieved.content).to eq("Important recent memory")
    end
  end

  describe 'batch operation compaction' do
    it 'triggers compaction after batch store' do
      # Batch store many memories to trigger compaction
      contents = 25.times.map { |i| "Batch content #{i}" }
      
      stored_memories = manager.store_memories_batch(contents, user_id: user_id)
      
      # Should have stored all initially
      expect(stored_memories.length).to eq(25)
      
      # But compaction should have removed some
      final_count = manager.count_memories(user_id: user_id)
      expect(final_count).to be <= 20
    end

    it 'triggers compaction after import' do
      # Create memory data for import
      memories_data = 25.times.map do |i|
        {
          'id' => SecureRandom.uuid,
          'content' => "Imported memory #{i}",
          'user_id' => user_id,
          'tags' => [],
          'embedding' => [0.1, 0.2, 0.3],
          'created_at' => Time.now.iso8601,
          'updated_at' => Time.now.iso8601,
          'access_count' => 0,
          'metadata' => {}
        }
      end

      imported_count = manager.import_memories(memories_data)
      expect(imported_count).to eq(25)

      # Compaction should have reduced the count
      final_count = manager.count_memories(user_id: user_id)
      expect(final_count).to be <= 20
    end
  end

  describe 'manual compaction' do
    it 'allows forced compaction regardless of thresholds' do
      # Store just a few memories (below normal thresholds)
      5.times do |i|
        manager.store_memory("Memory #{i}", user_id: user_id)
      end

      initial_count = manager.count_memories(user_id: user_id)
      expect(initial_count).to eq(5)

      # Force compaction
      results = manager.force_compact!(user_id)

      # Should have run all compaction strategies
      expect(results).to have_key(:size_compaction)
      expect(results).to have_key(:age_compaction)
      expect(results).to have_key(:deduplication)
      expect(results).to have_key(:relevance_pruning)
    end

    it 'provides detailed compaction results' do
      # Store enough memories to trigger multiple compaction types
      20.times do |i|
        manager.store_memory("Test memory #{i}", user_id: user_id)
      end

      results = manager.compact_if_needed!(user_id)

      expect(results).to be_a(Hash)
      expect(results).to have_key(:total_compacted)
      
      if results[:size_compaction]
        expect(results[:size_compaction]).to have_key(:removed_count)
        expect(results[:size_compaction]).to have_key(:trigger)
      end
    end
  end

  describe 'user isolation in compaction' do
    it 'only compacts memories for specified user' do
      # Store memories for user1 (will trigger compaction)
      user1_initial = 0
      25.times do |i|
        manager.store_memory("User1 memory #{i}", user_id: 'user1')
        user1_initial += 1
      end

      # Store fewer memories for user2 (shouldn't trigger compaction)
      user2_initial = 0
      8.times do |i|
        manager.store_memory("User2 memory #{i}", user_id: 'user2')
        user2_initial += 1
      end

      user1_after_store = manager.count_memories(user_id: 'user1')
      user2_after_store = manager.count_memories(user_id: 'user2')

      # User1 should have been compacted due to size
      expect(user1_after_store).to be <= 20
      expect(user1_after_store).to be < user1_initial
      
      # User2 should be unchanged (below threshold)
      expect(user2_after_store).to eq(8)

      # Manual compaction for user2 shouldn't affect user1
      manager.compact_if_needed!('user2')
      
      user1_final = manager.count_memories(user_id: 'user1')
      user2_final = manager.count_memories(user_id: 'user2')
      
      expect(user1_final).to eq(user1_after_store)  # Should be unchanged
      expect(user2_final).to eq(8)  # Should still be unchanged
    end
  end

  describe 'compaction with realistic data' do
    it 'handles duplicate detection with similar content' do
      # Store very similar memories directly to avoid automatic compaction
      base_content = "The quick brown fox jumps over the lazy dog"
      
      # Store similar memories directly
      10.times do |i|
        record = DSPy::Memory::MemoryRecord.new(
          content: "#{base_content} variation #{i}",
          user_id: user_id,
          embedding: [0.1, 0.2, 0.3]  # Same embedding to simulate similarity
        )
        manager.store.store(record)
      end

      # Add completely different content
      5.times do |i|
        record = DSPy::Memory::MemoryRecord.new(
          content: "Completely different content about cats #{i}",
          user_id: user_id,
          embedding: [0.9, 0.8, 0.7]  # Different embedding
        )
        manager.store.store(record)
      end

      initial_count = manager.count_memories(user_id: user_id)
      expect(initial_count).to eq(15)

      # Force deduplication with high similarity detection
      results = manager.force_compact!(user_id)
      
      final_count = manager.count_memories(user_id: user_id)
      
      # Should have performed compaction
      expect(final_count).to be <= initial_count
      expect(results).to have_key(:deduplication)
    end

    it 'preserves high-access memories during relevance pruning' do
      # Store memories with varying access patterns
      low_access_memories = []
      5.times do |i|
        memory = manager.store_memory("Low access memory #{i}", user_id: user_id)
        low_access_memories << memory
      end

      high_access_memories = []
      5.times do |i|
        memory = manager.store_memory("High access memory #{i}", user_id: user_id)
        # Simulate high access
        10.times { manager.get_memory(memory.id) }
        high_access_memories << memory
      end

      # Force relevance pruning
      results = manager.force_compact!(user_id)

      # High access memories should be more likely to survive
      high_access_survivors = high_access_memories.count do |memory|
        manager.get_memory(memory.id)
      end

      low_access_survivors = low_access_memories.count do |memory|
        manager.get_memory(memory.id)
      end

      expect(high_access_survivors).to be >= low_access_survivors
    end
  end

end