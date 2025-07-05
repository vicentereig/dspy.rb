# frozen_string_literal: true

require 'spec_helper'
require 'dspy/memory/memory_record'

RSpec.describe DSPy::Memory::MemoryRecord do
  describe 'initialization' do
    it 'creates a memory record with required parameters' do
      record = described_class.new(content: "Test content")
      
      expect(record.content).to eq("Test content")
      expect(record.id).to be_a(String)
      expect(record.id.length).to eq(36)  # UUID length
      expect(record.tags).to eq([])
      expect(record.user_id).to be_nil
      expect(record.embedding).to be_nil
      expect(record.access_count).to eq(0)
      expect(record.last_accessed_at).to be_nil
      expect(record.metadata).to eq({})
    end

    it 'creates a memory record with all parameters' do
      embedding = [0.1, 0.2, 0.3]
      tags = ["important", "work"]
      metadata = {"source" => "test"}
      
      record = described_class.new(
        content: "Test content",
        user_id: "user123",
        tags: tags,
        embedding: embedding,
        id: "custom-id",
        metadata: metadata
      )
      
      expect(record.content).to eq("Test content")
      expect(record.user_id).to eq("user123")
      expect(record.tags).to eq(tags)
      expect(record.embedding).to eq(embedding)
      expect(record.id).to eq("custom-id")
      expect(record.metadata).to eq(metadata)
    end

    it 'sets timestamps on creation' do
      record = described_class.new(content: "Test")
      
      expect(record.created_at).to be_a(Time)
      expect(record.updated_at).to be_a(Time)
      expect(record.created_at).to be_within(1).of(Time.now)
      expect(record.updated_at).to be_within(1).of(Time.now)
    end
  end

  describe '#record_access!' do
    it 'increments access count and updates last accessed time' do
      record = described_class.new(content: "Test")
      expect(record.access_count).to eq(0)
      expect(record.last_accessed_at).to be_nil
      
      record.record_access!
      
      expect(record.access_count).to eq(1)
      expect(record.last_accessed_at).to be_a(Time)
      expect(record.last_accessed_at).to be_within(1).of(Time.now)
      
      sleep(0.01)  # Small delay to ensure time difference
      record.record_access!
      
      expect(record.access_count).to eq(2)
    end
  end

  describe '#update_content!' do
    it 'updates content and timestamp' do
      record = described_class.new(content: "Original")
      original_updated_at = record.updated_at
      
      sleep(0.01)  # Ensure time difference
      record.update_content!("Updated content")
      
      expect(record.content).to eq("Updated content")
      expect(record.updated_at).to be > original_updated_at
    end
  end

  describe '#age_in_seconds' do
    it 'returns age in seconds' do
      record = described_class.new(content: "Test")
      age = record.age_in_seconds
      
      expect(age).to be >= 0
      expect(age).to be < 1  # Should be very recent
    end
  end

  describe '#age_in_days' do
    it 'returns age in days' do
      record = described_class.new(content: "Test")
      age = record.age_in_days
      
      expect(age).to be >= 0
      expect(age).to be < 0.001  # Should be very recent (less than 0.001 days)
    end
  end

  describe '#accessed_recently?' do
    it 'returns false when never accessed' do
      record = described_class.new(content: "Test")
      expect(record.accessed_recently?).to be false
    end

    it 'returns true when accessed recently' do
      record = described_class.new(content: "Test")
      record.record_access!
      
      expect(record.accessed_recently?(3600)).to be true  # Within last hour
      expect(record.accessed_recently?(1)).to be true     # Within last second
    end

    it 'returns false when accessed too long ago' do
      record = described_class.new(content: "Test")
      
      # Manually set last_accessed_at to 2 hours ago
      record.instance_variable_set(:@last_accessed_at, Time.now - 7200)
      
      expect(record.accessed_recently?(3600)).to be false  # Not within last hour
    end
  end

  describe 'tag management' do
    let(:record) { described_class.new(content: "Test", tags: ["tag1", "tag2"]) }

    describe '#has_tag?' do
      it 'returns true for existing tags' do
        expect(record.has_tag?("tag1")).to be true
        expect(record.has_tag?("tag2")).to be true
      end

      it 'returns false for non-existing tags' do
        expect(record.has_tag?("tag3")).to be false
      end
    end

    describe '#add_tag' do
      it 'adds new tags' do
        record.add_tag("tag3")
        expect(record.tags).to include("tag3")
      end

      it 'does not add duplicate tags' do
        record.add_tag("tag1")
        expect(record.tags.count("tag1")).to eq(1)
      end
    end

    describe '#remove_tag' do
      it 'removes existing tags' do
        record.remove_tag("tag1")
        expect(record.tags).not_to include("tag1")
        expect(record.tags).to include("tag2")
      end

      it 'does nothing for non-existing tags' do
        original_tags = record.tags.dup
        record.remove_tag("nonexistent")
        expect(record.tags).to eq(original_tags)
      end
    end
  end

  describe 'serialization' do
    let(:record) do
      described_class.new(
        content: "Test content",
        user_id: "user123",
        tags: ["tag1", "tag2"],
        embedding: [0.1, 0.2, 0.3],
        metadata: {"source" => "test"}
      )
    end

    describe '#to_h' do
      it 'converts record to hash' do
        hash = record.to_h
        
        expect(hash).to include(
          'id' => record.id,
          'content' => "Test content",
          'user_id' => "user123",
          'tags' => ["tag1", "tag2"],
          'embedding' => [0.1, 0.2, 0.3],
          'metadata' => {"source" => "test"},
          'access_count' => 0
        )
        
        expect(hash['created_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(hash['updated_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    describe '.from_h' do
      it 'creates record from hash' do
        original_hash = record.to_h
        restored_record = described_class.from_h(original_hash)
        
        expect(restored_record.id).to eq(record.id)
        expect(restored_record.content).to eq(record.content)
        expect(restored_record.user_id).to eq(record.user_id)
        expect(restored_record.tags).to eq(record.tags)
        expect(restored_record.embedding).to eq(record.embedding)
        expect(restored_record.metadata).to eq(record.metadata)
        expect(restored_record.access_count).to eq(record.access_count)
        expect(restored_record.created_at).to be_within(1).of(record.created_at)
        expect(restored_record.updated_at).to be_within(1).of(record.updated_at)
      end

      it 'handles missing optional fields' do
        minimal_hash = {
          'id' => 'test-id',
          'content' => 'test content',
          'created_at' => Time.now.iso8601,
          'updated_at' => Time.now.iso8601
        }
        
        record = described_class.from_h(minimal_hash)
        
        expect(record.id).to eq('test-id')
        expect(record.content).to eq('test content')
        expect(record.user_id).to be_nil
        expect(record.tags).to eq([])
        expect(record.embedding).to be_nil
        expect(record.metadata).to eq({})
        expect(record.access_count).to eq(0)
        expect(record.last_accessed_at).to be_nil
      end
    end
  end

  describe 'string representation' do
    it 'provides readable string representation' do
      record = described_class.new(
        content: "This is a very long content that should be truncated in the string representation",
        tags: ["tag1", "tag2"]
      )
      
      str = record.to_s
      expect(str).to include("MemoryRecord")
      expect(str).to include(record.id[0..7])
      expect(str).to include("This is a very long content that should be trunca")
      expect(str).to include(["tag1", "tag2"].to_s)
    end

    it 'inspect returns same as to_s' do
      record = described_class.new(content: "Test")
      expect(record.inspect).to eq(record.to_s)
    end
  end
end