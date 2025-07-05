# frozen_string_literal: true

require 'spec_helper'
require 'dspy/memory/memory_manager'
require 'dspy/memory/in_memory_store'
require 'dspy/memory/local_embedding_engine'

RSpec.describe DSPy::Memory::MemoryManager do
  let(:store) { DSPy::Memory::InMemoryStore.new }
  let(:embedding_engine) { DSPy::Memory::NoOpEmbeddingEngine.new }
  let(:manager) { described_class.new(store: store, embedding_engine: embedding_engine) }

  describe 'initialization' do
    it 'uses provided store and embedding engine' do
      expect(manager.store).to eq(store)
      expect(manager.embedding_engine).to eq(embedding_engine)
    end

    it 'uses defaults when not provided' do
      default_manager = described_class.new
      expect(default_manager.store).to be_a(DSPy::Memory::InMemoryStore)
      expect(default_manager.embedding_engine).to be_a(DSPy::Memory::EmbeddingEngine)
    end
  end

  describe '#store_memory' do
    it 'stores memory with embedding' do
      record = manager.store_memory("Test content", user_id: "user1", tags: ["test"])
      
      expect(record).to be_a(DSPy::Memory::MemoryRecord)
      expect(record.content).to eq("Test content")
      expect(record.user_id).to eq("user1")
      expect(record.tags).to eq(["test"])
      expect(record.embedding).to be_a(Array)
      expect(record.embedding.length).to eq(128)  # NoOpEmbeddingEngine dimension
    end

    it 'includes metadata' do
      metadata = {"source" => "test"}
      record = manager.store_memory("Test", metadata: metadata)
      
      expect(record.metadata).to eq(metadata)
    end

    it 'stores record in backend' do
      record = manager.store_memory("Test content")
      retrieved = store.retrieve(record.id)
      
      expect(retrieved).to eq(record)
    end
  end

  describe '#get_memory' do
    let!(:stored_record) { manager.store_memory("Test content", user_id: "user1") }

    it 'retrieves memory by ID' do
      retrieved = manager.get_memory(stored_record.id)
      
      expect(retrieved).to eq(stored_record)
      expect(retrieved.content).to eq("Test content")
    end

    it 'returns nil for non-existing memory' do
      retrieved = manager.get_memory("non-existing-id")
      expect(retrieved).to be_nil
    end

    it 'records access when retrieving' do
      original_count = stored_record.access_count
      manager.get_memory(stored_record.id)
      
      expect(stored_record.access_count).to eq(original_count + 1)
    end
  end

  describe '#update_memory' do
    let!(:stored_record) { manager.store_memory("Original content", user_id: "user1") }

    it 'updates memory content' do
      result = manager.update_memory(stored_record.id, "Updated content")
      
      expect(result).to be true
      updated_record = manager.get_memory(stored_record.id)
      expect(updated_record.content).to eq("Updated content")
      expect(updated_record.embedding).to be_a(Array)  # New embedding generated
    end

    it 'updates tags when provided' do
      new_tags = ["updated", "test"]
      result = manager.update_memory(stored_record.id, "Updated content", tags: new_tags)
      
      expect(result).to be true
      updated_record = manager.get_memory(stored_record.id)
      expect(updated_record.tags).to eq(new_tags)
    end

    it 'updates metadata when provided' do
      new_metadata = {"updated" => true}
      result = manager.update_memory(stored_record.id, "Updated content", metadata: new_metadata)
      
      expect(result).to be true
      updated_record = manager.get_memory(stored_record.id)
      expect(updated_record.metadata).to include(new_metadata)
    end

    it 'returns false for non-existing memory' do
      result = manager.update_memory("non-existing-id", "New content")
      expect(result).to be false
    end
  end

  describe '#delete_memory' do
    let!(:stored_record) { manager.store_memory("Test content") }

    it 'deletes memory' do
      result = manager.delete_memory(stored_record.id)
      
      expect(result).to be true
      expect(manager.get_memory(stored_record.id)).to be_nil
    end

    it 'returns false for non-existing memory' do
      result = manager.delete_memory("non-existing-id")
      expect(result).to be false
    end
  end

  describe '#get_all_memories' do
    before do
      manager.store_memory("Memory 1", user_id: "user1")
      manager.store_memory("Memory 2", user_id: "user1")
      manager.store_memory("Memory 3", user_id: "user2")
    end

    it 'gets all memories when no user_id specified' do
      memories = manager.get_all_memories
      expect(memories.length).to eq(3)
    end

    it 'filters by user_id' do
      memories = manager.get_all_memories(user_id: "user1")
      expect(memories.length).to eq(2)
      expect(memories.all? { |m| m.user_id == "user1" }).to be true
    end

    it 'applies limit and offset' do
      memories = manager.get_all_memories(limit: 2, offset: 1)
      expect(memories.length).to eq(2)
    end
  end

  describe '#search_memories' do
    before do
      manager.store_memory("Ruby programming tutorial", user_id: "user1", tags: ["programming"])
      manager.store_memory("Python data science", user_id: "user1", tags: ["programming"])
      manager.store_memory("Personal journal entry", user_id: "user2", tags: ["personal"])
    end

    it 'searches memories semantically' do
      results = manager.search_memories("programming")
      expect(results.length).to be >= 1
      expect(results.any? { |r| r.content.include?("programming") }).to be true
    end

    it 'filters by user_id' do
      results = manager.search_memories("programming", user_id: "user1")
      expect(results.all? { |r| r.user_id == "user1" }).to be true
    end

    it 'applies limit' do
      results = manager.search_memories("programming", limit: 1)
      expect(results.length).to eq(1)
    end

    it 'respects threshold' do
      results = manager.search_memories("completely unrelated query", threshold: 0.9)
      expect(results.length).to be <= 1  # Should find few or no results with high threshold
    end
  end

  describe '#search_by_tags' do
    before do
      manager.store_memory("Content 1", tags: ["work", "important"])
      manager.store_memory("Content 2", tags: ["work", "project"])
      manager.store_memory("Content 3", tags: ["personal"])
    end

    it 'searches by single tag' do
      results = manager.search_by_tags(["work"])
      expect(results.length).to eq(2)
    end

    it 'searches by multiple tags' do
      results = manager.search_by_tags(["work", "personal"])
      expect(results.length).to eq(3)
    end

    it 'applies limit' do
      results = manager.search_by_tags(["work"], limit: 1)
      expect(results.length).to eq(1)
    end
  end

  describe '#search_text' do
    before do
      manager.store_memory("Ruby programming tutorial")
      manager.store_memory("Python data science")
      manager.store_memory("Personal journal entry")
    end

    it 'searches by text content' do
      results = manager.search_text("programming")
      expect(results.length).to eq(1)
      expect(results.first.content).to include("programming")
    end

    it 'is case-insensitive' do
      results = manager.search_text("RUBY")
      expect(results.length).to eq(1)
    end
  end

  describe '#count_memories' do
    before do
      manager.store_memory("Memory 1", user_id: "user1")
      manager.store_memory("Memory 2", user_id: "user1")
      manager.store_memory("Memory 3", user_id: "user2")
    end

    it 'counts all memories' do
      count = manager.count_memories
      expect(count).to eq(3)
    end

    it 'counts memories for specific user' do
      count = manager.count_memories(user_id: "user1")
      expect(count).to eq(2)
    end
  end

  describe '#clear_memories' do
    before do
      manager.store_memory("Memory 1", user_id: "user1")
      manager.store_memory("Memory 2", user_id: "user1")
      manager.store_memory("Memory 3", user_id: "user2")
    end

    it 'clears all memories' do
      count = manager.clear_memories
      expect(count).to eq(3)
      expect(manager.count_memories).to eq(0)
    end

    it 'clears memories for specific user' do
      count = manager.clear_memories(user_id: "user1")
      expect(count).to eq(2)
      expect(manager.count_memories).to eq(1)
      expect(manager.count_memories(user_id: "user2")).to eq(1)
    end
  end

  describe '#find_similar' do
    let!(:target_record) { manager.store_memory("Ruby programming tutorial", tags: ["programming"]) }
    let!(:similar_record) { manager.store_memory("Python programming guide", tags: ["programming"]) }
    let!(:different_record) { manager.store_memory("Cooking recipes", tags: ["cooking"]) }

    it 'finds similar memories' do
      results = manager.find_similar(target_record.id)
      expect(results).to include(similar_record)
      expect(results).not_to include(target_record)  # Excludes self
    end

    it 'applies limit' do
      results = manager.find_similar(target_record.id, limit: 1)
      expect(results.length).to eq(1)
    end

    it 'returns empty array for memory without embedding' do
      # Create record without embedding
      record = DSPy::Memory::MemoryRecord.new(content: "No embedding")
      store.store(record)
      
      results = manager.find_similar(record.id)
      expect(results).to be_empty
    end
  end

  describe '#store_memories_batch' do
    let(:contents) { ["Memory 1", "Memory 2", "Memory 3"] }

    it 'stores multiple memories with embeddings' do
      records = manager.store_memories_batch(contents, user_id: "user1", tags: ["batch"])
      
      expect(records.length).to eq(3)
      expect(records).to all(be_a(DSPy::Memory::MemoryRecord))
      expect(records.all? { |r| r.user_id == "user1" }).to be true
      expect(records.all? { |r| r.tags == ["batch"] }).to be true
      expect(records.all? { |r| r.embedding.is_a?(Array) }).to be true
    end

    it 'handles empty array' do
      records = manager.store_memories_batch([])
      expect(records).to be_empty
    end
  end

  describe '#stats' do
    before do
      manager.store_memory("Test memory 1")
      manager.store_memory("Test memory 2")
    end

    it 'provides comprehensive statistics' do
      stats = manager.stats
      
      expect(stats).to have_key(:store)
      expect(stats).to have_key(:embedding_engine)
      expect(stats[:total_memories]).to eq(2)
      expect(stats[:store][:total_memories]).to eq(2)
      expect(stats[:embedding_engine][:model_name]).to eq('simple-hash')
    end
  end

  describe '#healthy?' do
    it 'returns true when components are ready' do
      expect(manager.healthy?).to be true
    end

    it 'returns false when embedding engine not ready' do
      broken_engine = double('BrokenEngine', ready?: false)
      allow(broken_engine).to receive(:is_a?).and_return(true)
      broken_manager = T.unsafe(described_class).new(store: store, embedding_engine: broken_engine)
      
      expect(broken_manager.healthy?).to be false
    end
  end

  describe '#export_memories' do
    before do
      manager.store_memory("Memory 1", user_id: "user1")
      manager.store_memory("Memory 2", user_id: "user2")
    end

    it 'exports all memories' do
      exported = manager.export_memories
      expect(exported.length).to eq(2)
      expect(exported).to all(be_a(Hash))
      expect(exported.all? { |h| h.key?('content') }).to be true
    end

    it 'exports memories for specific user' do
      exported = manager.export_memories(user_id: "user1")
      expect(exported.length).to eq(1)
      expect(exported.first['user_id']).to eq("user1")
    end
  end

  describe '#import_memories' do
    let(:memory_data) do
      [
        {
          'id' => 'test-1',
          'content' => 'Imported memory 1',
          'user_id' => 'user1',
          'tags' => ['imported'],
          'created_at' => Time.now.iso8601,
          'updated_at' => Time.now.iso8601,
          'access_count' => 0,
          'metadata' => {}
        },
        {
          'id' => 'test-2',
          'content' => 'Imported memory 2',
          'user_id' => 'user1',
          'tags' => ['imported'],
          'created_at' => Time.now.iso8601,
          'updated_at' => Time.now.iso8601,
          'access_count' => 0,
          'metadata' => {}
        }
      ]
    end

    it 'imports memories from hash data' do
      count = manager.import_memories(memory_data)
      expect(count).to eq(2)
      expect(manager.count_memories).to eq(2)
      
      imported = manager.get_memory('test-1')
      expect(imported.content).to eq('Imported memory 1')
    end

    it 'handles empty array' do
      count = manager.import_memories([])
      expect(count).to eq(0)
    end
  end

  describe 'integration with different embedding engines' do
    context 'when using LocalEmbeddingEngine' do
      it 'works with local embedding engine' do
        # Disable VCR and WebMock for model downloads from Hugging Face
        VCR.turned_off do
          WebMock.allow_net_connect!
          
          begin
            local_engine = DSPy::Memory::LocalEmbeddingEngine.new
            local_manager = described_class.new(store: store, embedding_engine: local_engine)
            
            record = local_manager.store_memory("Test with local embeddings")
            expect(record.embedding).to be_a(Array)
            expect(record.embedding.length).to be > 0
            
            # Should be able to search semantically
            results = local_manager.search_memories("test embeddings")
            expect(results).to include(record)
          ensure
            WebMock.disable_net_connect!
          end
        end
      end
    end
  end
end