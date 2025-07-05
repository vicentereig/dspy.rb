# frozen_string_literal: true

require 'sorbet-runtime'
require 'securerandom'

module DSPy
  module Memory
    # Represents a single memory entry with metadata and embeddings
    class MemoryRecord
      extend T::Sig

      sig { returns(String) }
      attr_reader :id

      sig { returns(String) }
      attr_accessor :content

      sig { returns(T.nilable(String)) }
      attr_accessor :user_id

      sig { returns(T::Array[String]) }
      attr_accessor :tags

      sig { returns(T.nilable(T::Array[Float])) }
      attr_accessor :embedding

      sig { returns(Time) }
      attr_reader :created_at

      sig { returns(Time) }
      attr_accessor :updated_at

      sig { returns(Integer) }
      attr_accessor :access_count

      sig { returns(T.nilable(Time)) }
      attr_accessor :last_accessed_at

      sig { returns(T::Hash[String, T.untyped]) }
      attr_accessor :metadata

      sig do
        params(
          content: String,
          user_id: T.nilable(String),
          tags: T::Array[String],
          embedding: T.nilable(T::Array[Float]),
          id: T.nilable(String),
          metadata: T::Hash[String, T.untyped]
        ).void
      end
      def initialize(content:, user_id: nil, tags: [], embedding: nil, id: nil, metadata: {})
        @id = id || SecureRandom.uuid
        @content = content
        @user_id = user_id
        @tags = tags
        @embedding = embedding
        @created_at = Time.now
        @updated_at = Time.now
        @access_count = 0
        @last_accessed_at = nil
        @metadata = metadata
      end

      # Record an access to this memory
      sig { void }
      def record_access!
        @access_count += 1
        @last_accessed_at = Time.now
      end

      # Update the content and timestamp
      sig { params(new_content: String).void }
      def update_content!(new_content)
        @content = new_content
        @updated_at = Time.now
      end

      # Calculate age in seconds
      sig { returns(Float) }
      def age_in_seconds
        Time.now - @created_at
      end

      # Calculate age in days
      sig { returns(Float) }
      def age_in_days
        age_in_seconds / 86400.0
      end

      # Check if memory has been accessed recently (within last N seconds)
      sig { params(seconds: Integer).returns(T::Boolean) }
      def accessed_recently?(seconds = 3600)
        return false if @last_accessed_at.nil?
        (Time.now - @last_accessed_at) <= seconds
      end

      # Check if memory matches a tag
      sig { params(tag: String).returns(T::Boolean) }
      def has_tag?(tag)
        @tags.include?(tag)
      end

      # Add a tag if not already present
      sig { params(tag: String).void }
      def add_tag(tag)
        @tags << tag unless @tags.include?(tag)
      end

      # Remove a tag
      sig { params(tag: String).void }
      def remove_tag(tag)
        @tags.delete(tag)
      end

      # Convert to hash for serialization
      sig { returns(T::Hash[String, T.untyped]) }
      def to_h
        {
          'id' => @id,
          'content' => @content,
          'user_id' => @user_id,
          'tags' => @tags,
          'embedding' => @embedding,
          'created_at' => @created_at.iso8601,
          'updated_at' => @updated_at.iso8601,
          'access_count' => @access_count,
          'last_accessed_at' => @last_accessed_at&.iso8601,
          'metadata' => @metadata
        }
      end

      # Create from hash (for deserialization)
      sig { params(hash: T::Hash[String, T.untyped]).returns(MemoryRecord) }
      def self.from_h(hash)
        record = allocate
        record.instance_variable_set(:@id, hash['id'])
        record.instance_variable_set(:@content, hash['content'])
        record.instance_variable_set(:@user_id, hash['user_id'])
        record.instance_variable_set(:@tags, hash['tags'] || [])
        record.instance_variable_set(:@embedding, hash['embedding'])
        record.instance_variable_set(:@created_at, Time.parse(hash['created_at']))
        record.instance_variable_set(:@updated_at, Time.parse(hash['updated_at']))
        record.instance_variable_set(:@access_count, hash['access_count'] || 0)
        record.instance_variable_set(:@last_accessed_at, 
          hash['last_accessed_at'] ? Time.parse(hash['last_accessed_at']) : nil)
        record.instance_variable_set(:@metadata, hash['metadata'] || {})
        record
      end

      # String representation
      sig { returns(String) }
      def to_s
        "#<MemoryRecord id=#{@id[0..7]}... content=\"#{@content[0..50]}...\" tags=#{@tags}>"
      end

      sig { returns(String) }
      def inspect
        to_s
      end
    end
  end
end