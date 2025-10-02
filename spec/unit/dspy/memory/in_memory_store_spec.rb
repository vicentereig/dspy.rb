# frozen_string_literal: true

require 'spec_helper'
require 'dspy/memory/in_memory_store'
require 'dspy/memory/memory_record'

RSpec.describe DSPy::Memory::InMemoryStore do
  let(:store) { described_class.new }
  let(:record1) do
    DSPy::Memory::MemoryRecord.new(
      content: "First memory",
      user_id: "user1",
      tags: ["work", "important"],
      embedding: [0.1, 0.2, 0.3]
    )
  end
  let(:record2) do
    DSPy::Memory::MemoryRecord.new(
      content: "Second memory about work project",
      user_id: "user1",
      tags: ["work", "project"],
      embedding: [0.4, 0.5, 0.6]
    )
  end
  let(:record3) do
    DSPy::Memory::MemoryRecord.new(
      content: "Third memory for different user",
      user_id: "user2",
      tags: ["personal"],
      embedding: [0.7, 0.8, 0.9]
    )
  end

  describe '#store' do
    it 'stores a memory record' do
      result = store.store(record1)
      expect(result).to be true
    end

    it 'stores multiple records' do
      expect(store.store(record1)).to be true
      expect(store.store(record2)).to be true
      expect(store.count).to eq(2)
    end
  end

  describe '#retrieve' do
    before do
      store.store(record1)
      store.store(record2)
    end

    it 'retrieves existing record' do
      retrieved = store.retrieve(record1.id)
      expect(retrieved).to eq(record1)
      expect(retrieved.content).to eq("First memory")
    end

    it 'returns nil for non-existing record' do
      retrieved = store.retrieve("non-existing-id")
      expect(retrieved).to be_nil
    end

    it 'records access when retrieving' do
      original_count = record1.access_count
      store.retrieve(record1.id)
      expect(record1.access_count).to eq(original_count + 1)
      expect(record1.last_accessed_at).to be_a(Time)
    end
  end

  describe '#update' do
    before { store.store(record1) }

    it 'updates existing record' do
      record1.update_content!("Updated content")
      result = store.update(record1)
      
      expect(result).to be true
      retrieved = store.retrieve(record1.id)
      expect(retrieved.content).to eq("Updated content")
    end

    it 'returns false for non-existing record' do
      new_record = DSPy::Memory::MemoryRecord.new(content: "New", id: "non-existing")
      result = store.update(new_record)
      expect(result).to be false
    end
  end

  describe '#delete' do
    before { store.store(record1) }

    it 'deletes existing record' do
      result = store.delete(record1.id)
      expect(result).to be true
      expect(store.retrieve(record1.id)).to be_nil
    end

    it 'returns false for non-existing record' do
      result = store.delete("non-existing-id")
      expect(result).to be false
    end
  end

  describe '#list' do
    before do
      store.store(record1)
      store.store(record2)
      store.store(record3)
    end

    it 'lists all records when no user_id specified' do
      records = store.list
      expect(records.length).to eq(3)
      expect(records).to include(record1, record2, record3)
    end

    it 'filters by user_id' do
      records = store.list(user_id: "user1")
      expect(records.length).to eq(2)
      expect(records).to include(record1, record2)
      expect(records).not_to include(record3)
    end

    it 'sorts by created_at (newest first)' do
      records = store.list
      expect(records.first.created_at).to be >= records.last.created_at
    end

    it 'applies limit' do
      records = store.list(limit: 2)
      expect(records.length).to eq(2)
    end

    it 'applies offset' do
      records = store.list(offset: 1)
      expect(records.length).to eq(2)
    end

    it 'applies both limit and offset' do
      records = store.list(limit: 1, offset: 1)
      expect(records.length).to eq(1)
    end
  end

  describe '#search' do
    before do
      store.store(record1)
      store.store(record2)
      store.store(record3)
    end

    it 'searches by content' do
      results = store.search("work project")
      expect(results.length).to eq(1)
      expect(results.first).to eq(record2)
    end

    it 'searches case-insensitively' do
      results = store.search("WORK")
      expect(results.length).to eq(2)
      expect(results).to include(record1, record2)
    end

    it 'searches in tags' do
      results = store.search("important")
      expect(results.length).to eq(1)
      expect(results.first).to eq(record1)
    end

    it 'filters by user_id' do
      results = store.search("memory", user_id: "user2")
      expect(results.length).to eq(1)
      expect(results.first).to eq(record3)
    end

    it 'applies limit' do
      results = store.search("memory", limit: 2)
      expect(results.length).to eq(2)
    end

    it 'sorts by exact match and recency' do
      # Record with exact match should come first
      exact_match = DSPy::Memory::MemoryRecord.new(content: "work", user_id: "user1")
      store.store(exact_match)
      
      results = store.search("work")
      expect(results.first).to eq(exact_match)
    end
  end

  describe '#search_by_tags' do
    before do
      store.store(record1)
      store.store(record2)
      store.store(record3)
    end

    it 'searches by single tag' do
      results = store.search_by_tags(["work"])
      expect(results.length).to eq(2)
      expect(results).to include(record1, record2)
    end

    it 'searches by multiple tags' do
      results = store.search_by_tags(["work", "personal"])
      expect(results.length).to eq(3)
    end

    it 'filters by user_id' do
      results = store.search_by_tags(["work"], user_id: "user1")
      expect(results.length).to eq(2)
      expect(results).to include(record1, record2)
    end

    it 'sorts by number of matching tags' do
      # Record1 has "work" and "important", Record2 has "work" and "project"
      results = store.search_by_tags(["work", "important"])
      expect(results.first).to eq(record1)  # Should match 2 tags
    end

    it 'applies limit' do
      results = store.search_by_tags(["work"], limit: 1)
      expect(results.length).to eq(1)
    end
  end

  describe '#vector_search' do
    before do
      store.store(record1)
      store.store(record2)
      store.store(record3)
    end

    it 'finds similar vectors' do
      # Search with embedding similar to record1
      query_embedding = [0.1, 0.2, 0.3]  # Same as record1
      results = store.vector_search(query_embedding)
      
      expect(results.length).to be >= 1
      expect(results.first).to eq(record1)  # Should find exact match first
    end

    it 'sorts by similarity (highest first)' do
      query_embedding = [0.1, 0.2, 0.3]  # Closer to record1
      results = store.vector_search(query_embedding)
      
      # record1 should be more similar than record2 or record3
      expect(results.first).to eq(record1)
    end

    it 'applies threshold' do
      query_embedding = [0.1, 0.2, 0.3]
      results = store.vector_search(query_embedding, threshold: 0.99)  # Very high threshold
      
      expect(results.length).to eq(1)  # Only exact match should pass
      expect(results.first).to eq(record1)
    end

    it 'filters by user_id' do
      query_embedding = [0.1, 0.2, 0.3]
      results = store.vector_search(query_embedding, user_id: "user2")
      
      expect(results.length).to eq(1)
      expect(results.first).to eq(record3)
    end

    it 'applies limit' do
      query_embedding = [0.1, 0.2, 0.3]
      results = store.vector_search(query_embedding, limit: 1)
      
      expect(results.length).to eq(1)
    end

    it 'skips records without embeddings' do
      no_embedding = DSPy::Memory::MemoryRecord.new(content: "No embedding")
      store.store(no_embedding)
      
      query_embedding = [0.1, 0.2, 0.3]
      results = store.vector_search(query_embedding)
      
      expect(results).not_to include(no_embedding)
    end
  end

  describe '#count' do
    before do
      store.store(record1)
      store.store(record2)
      store.store(record3)
    end

    it 'counts all records' do
      expect(store.count).to eq(3)
    end

    it 'counts records for specific user' do
      expect(store.count(user_id: "user1")).to eq(2)
      expect(store.count(user_id: "user2")).to eq(1)
    end
  end

  describe '#clear' do
    before do
      store.store(record1)
      store.store(record2)
      store.store(record3)
    end

    it 'clears all records' do
      count = store.clear
      expect(count).to eq(3)
      expect(store.count).to eq(0)
    end

    it 'clears records for specific user' do
      count = store.clear(user_id: "user1")
      expect(count).to eq(2)
      expect(store.count).to eq(1)
      expect(store.count(user_id: "user2")).to eq(1)
    end
  end

  describe '#supports_vector_search?' do
    it 'returns true' do
      expect(store.supports_vector_search?).to be true
    end
  end

  describe '#stats' do
    before do
      store.store(record1)
      store.store(record2)
      store.store(record3)
      
      # Access some records
      store.retrieve(record1.id)
      store.retrieve(record1.id)
    end

    it 'provides store statistics' do
      stats = store.stats
      
      expect(stats[:total_memories]).to eq(3)
      expect(stats[:memories_with_embeddings]).to eq(3)
      expect(stats[:unique_users]).to eq(2)
      expect(stats[:supports_vector_search]).to be true
      expect(stats[:avg_access_count]).to be > 0
    end
  end

  describe 'batch operations' do
    let(:records) { [record1, record2, record3] }

    describe '#store_batch' do
      it 'stores multiple records' do
        results = store.store_batch(records)
        expect(results).to all(be true)
        expect(store.count).to eq(3)
      end
    end

    describe '#retrieve_batch' do
      before { store.store_batch(records) }

      it 'retrieves multiple records' do
        ids = records.map(&:id)
        results = store.retrieve_batch(ids)
        
        expect(results.length).to eq(3)
        expect(results).to all(be_a(DSPy::Memory::MemoryRecord))
      end

      it 'handles missing records' do
        ids = [record1.id, "missing", record2.id]
        results = store.retrieve_batch(ids)
        
        expect(results.length).to eq(3)
        expect(results[0]).to eq(record1)
        expect(results[1]).to be_nil
        expect(results[2]).to eq(record2)
      end
    end

    describe '#update_batch' do
      before { store.store_batch(records) }

      it 'updates multiple records' do
        records.each { |r| r.update_content!("Updated: #{r.content}") }
        results = store.update_batch(records)
        
        expect(results).to all(be true)
      end
    end

    describe '#delete_batch' do
      before { store.store_batch(records) }

      it 'deletes multiple records' do
        ids = records.map(&:id)
        results = store.delete_batch(ids)
        
        expect(results).to all(be true)
        expect(store.count).to eq(0)
      end
    end
  end

  describe 'thread safety' do
    it 'handles concurrent operations' do
      threads = []
      
      # Create multiple threads that store records
      10.times do |i|
        threads << Thread.new do
          record = DSPy::Memory::MemoryRecord.new(content: "Thread #{i}")
          store.store(record)
        end
      end
      
      threads.each(&:join)
      
      expect(store.count).to eq(10)
    end
  end
end