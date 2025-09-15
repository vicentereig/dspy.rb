# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  # Langfuse observation types as a T::Enum for type safety
  # Maps to the official Langfuse observation types: https://langfuse.com/docs/observability/features/observation-types
  class ObservationType < T::Enum
    enums do
      # LLM generation calls - used for direct model inference
      Generation = new('generation')
      
      # Agent operations - decision-making processes using tools/LLM guidance
      Agent = new('agent')
      
      # External tool calls (APIs, functions, etc.)
      Tool = new('tool')
      
      # Chains linking different application steps/components
      Chain = new('chain')
      
      # Data retrieval operations (vector stores, databases, memory search)
      Retriever = new('retriever')
      
      # Embedding generation calls
      Embedding = new('embedding')
      
      # Functions that assess quality/relevance of outputs
      Evaluator = new('evaluator')
      
      # Generic spans for durations of work units
      Span = new('span')
      
      # Discrete events/moments in time
      Event = new('event')
    end

    # Get the appropriate observation type for a DSPy module class
    sig { params(module_class: T.class_of(DSPy::Module)).returns(ObservationType) }
    def self.for_module_class(module_class)
      case module_class.name
      when /ReAct/, /CodeAct/
        Agent
      when /ChainOfThought/
        Chain
      when /Evaluator/
        Evaluator
      else
        Span
      end
    end

    # Returns the langfuse attribute key and value as an array
    sig { returns([String, String]) }
    def langfuse_attribute
      ['langfuse.observation.type', serialize]
    end

    # Returns a hash with the langfuse attribute for easy merging
    sig { returns(T::Hash[String, String]) }
    def langfuse_attributes
      { 'langfuse.observation.type' => serialize }
    end
  end
end