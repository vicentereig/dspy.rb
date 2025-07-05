# frozen_string_literal: true

require_relative 'memory/memory_record'
require_relative 'memory/memory_store'
require_relative 'memory/in_memory_store'
require_relative 'memory/embedding_engine'
require_relative 'memory/local_embedding_engine'
require_relative 'memory/memory_manager'

module DSPy
  # Memory system for persistent, searchable agent memory
  module Memory
    class << self
      extend T::Sig

      # Configure the memory system
      sig { returns(MemoryManager) }
      def manager
        @manager ||= MemoryManager.new
      end

      # Reset the memory system (useful for testing)
      sig { void }
      def reset!
        @manager = nil
      end
    end
  end
end