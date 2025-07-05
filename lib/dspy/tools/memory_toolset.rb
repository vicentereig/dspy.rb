# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'toolset'

module DSPy
  module Tools
    # Example implementation of a memory toolset for agents
    # Provides tools for storing, retrieving, and managing memory
    class MemoryToolset < Toolset
      extend T::Sig

      toolset_name "memory"

      # Expose methods as tools with descriptions
      tool :store, description: "Store a key-value pair in memory with optional tags"
      tool :retrieve, description: "Retrieve a value by key from memory"
      tool :search, description: "Search memories by pattern in keys and/or values"
      tool :list_keys, tool_name: "memory_list", description: "List all stored memory keys"
      tool :update, description: "Update an existing memory value"
      tool :delete, description: "Delete a memory by key"
      tool :clear, description: "Clear all stored memories"
      tool :count, description: "Get the count of stored memories"
      tool :get_metadata, description: "Get metadata for a specific memory"

      sig { void }
      def initialize
        @memory = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
      end

      sig { params(key: String, value: String, tags: T.nilable(T::Array[String])).returns(String) }
      def store(key:, value:, tags: nil)
        @memory[key] = {
          value: value,
          tags: tags || [],
          created_at: Time.now,
          updated_at: Time.now,
          access_count: 0
        }
        "Stored memory '#{key}' successfully"
      end

      sig { params(key: String).returns(T.nilable(String)) }
      def retrieve(key:)
        entry = @memory[key]
        return nil unless entry

        # Track access
        entry[:access_count] += 1
        entry[:last_accessed_at] = Time.now
        entry[:value]
      end

      sig { params(pattern: String, in_keys: T::Boolean, in_values: T::Boolean).returns(T::Array[T::Hash[Symbol, String]]) }
      def search(pattern:, in_keys: true, in_values: true)
        results = []
        regex = Regexp.new(pattern, Regexp::IGNORECASE)

        @memory.each do |key, entry|
          match = (in_keys && key.match?(regex)) || (in_values && entry[:value].match?(regex))
          results << { key: key, value: entry[:value] } if match
        end

        results
      end

      sig { returns(T::Array[String]) }
      def list_keys
        @memory.keys.sort
      end

      sig { params(key: String, value: String).returns(String) }
      def update(key:, value:)
        return "Memory '#{key}' not found" unless @memory.key?(key)

        @memory[key][:value] = value
        @memory[key][:updated_at] = Time.now
        "Updated memory '#{key}' successfully"
      end

      sig { params(key: String).returns(String) }
      def delete(key:)
        return "Memory '#{key}' not found" unless @memory.key?(key)

        @memory.delete(key)
        "Deleted memory '#{key}' successfully"
      end

      sig { returns(String) }
      def clear
        count = @memory.size
        @memory.clear
        "Cleared #{count} memories"
      end

      sig { returns(Integer) }
      def count
        @memory.size
      end

      sig { params(key: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def get_metadata(key:)
        entry = @memory[key]
        return nil unless entry

        {
          created_at: entry[:created_at],
          updated_at: entry[:updated_at],
          access_count: entry[:access_count],
          last_accessed_at: entry[:last_accessed_at],
          tags: entry[:tags],
          value_length: entry[:value].length
        }
      end
    end
  end
end