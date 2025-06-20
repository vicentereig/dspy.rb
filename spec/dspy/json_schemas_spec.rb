# frozen_string_literal: true

require 'spec_helper'

# Define test enums for AI agent contexts
class Priority < T::Enum
  enums do
    Low = new("low")
    Medium = new("medium") 
    High = new("high")
    Critical = new("critical")
  end
end

class ActionType < T::Enum
  enums do
    Search = new("search")
    Create = new("create")
    Update = new("update")
    Delete = new("delete")
    Analyze = new("analyze")
  end
end

class ConfidenceLevel < T::Enum
  enums do
    VeryLow = new("very_low")
    Low = new("low")
    Medium = new("medium")
    High = new("high")
    VeryHigh = new("very_high")
  end
end

# Define nested structs for complex AI agent data
class ToolCall < T::Struct
  const :tool_name, String
  const :arguments, T::Hash[String, T.untyped]
  const :timestamp, Float
  prop :result, T.nilable(String)
end

class Evidence < T::Struct
  const :source, String
  const :content, String
  const :confidence, Float
  const :timestamp, Float
end

class Metadata < T::Struct
  prop :priority, Priority
  prop :tags, T::Array[String]
  prop :created_at, Float
  prop :confidence, T.nilable(Float)
end

# AI Agentic Signature Examples demonstrating comprehensive type coverage
RSpec.describe 'AI Agentic Signatures - Comprehensive Type Coverage' do
  describe 'Basic Type Coverage' do
    class BasicTypeSignature < DSPy::SorbetSignature
      description "Demonstrates basic Sorbet type coverage including new additions"

      input do
        const :text, String, description: "Input text to process"
        const :count, Integer, description: "Number of items to process"
        const :threshold, Float, description: "Confidence threshold"
        const :temperature, Numeric, description: "LLM temperature (accepts Float or Integer)"
        const :enabled, T::Boolean, description: "Feature flag"
        const :debug_mode, TrueClass, description: "Debug enabled"
        const :silent_mode, FalseClass, description: "Silent mode disabled"
      end

      output do
        const :processed_text, String
        const :item_count, Integer
        const :confidence_score, Float
        const :adjusted_temperature, Numeric
        const :feature_active, T::Boolean
      end
    end

    it 'generates correct schemas for basic types including new Numeric and T::Boolean' do
      input_schema = BasicTypeSignature.input_json_schema
      output_schema = BasicTypeSignature.output_json_schema

      # Test new Numeric type support
      expect(input_schema[:properties][:temperature][:type]).to eq("number")
      expect(output_schema[:properties][:adjusted_temperature][:type]).to eq("number")

      # Test T::Boolean type support  
      expect(input_schema[:properties][:enabled][:type]).to eq("boolean")
      expect(output_schema[:properties][:feature_active][:type]).to eq("boolean")

      # Verify existing types still work
      expect(input_schema[:properties][:text][:type]).to eq("string")
      expect(input_schema[:properties][:count][:type]).to eq("integer")
      expect(input_schema[:properties][:threshold][:type]).to eq("number")
    end
  end

  describe 'Complex Union Types with oneOf' do
    class UnionTypeSignature < DSPy::SorbetSignature
      description "AI agent with flexible input/output types"

      input do
        const :query, T.any(String, T::Hash[String, T.untyped]), 
          description: "Search query as string or structured query"
        const :limit, T.any(Integer, String),
          description: "Result limit as number or 'all'"
      end

      output do
        const :result, T.any(String, T::Array[String], T::Hash[String, T.untyped]),
          description: "Flexible result format"
      end
    end

    it 'generates oneOf schemas for complex union types' do
      input_schema = UnionTypeSignature.input_json_schema
      
      expect(input_schema[:properties][:query]).to include(:oneOf)
      expect(input_schema[:properties][:query][:oneOf]).to contain_exactly(
        { type: "string" },
        { type: "object", propertyNames: { type: "string" }, additionalProperties: { type: "string" }, description: "A mapping where keys are strings and values are strings" }
      )

      expect(input_schema[:properties][:limit]).to include(:oneOf)
      expect(input_schema[:properties][:limit][:oneOf]).to contain_exactly(
        { type: "integer" },
        { type: "string" }
      )
    end
  end

  describe 'Enum Types for AI Agent Classification' do
    class ClassificationSignature < DSPy::SorbetSignature
      description "AI content classifier with priority and confidence"

      input do
        const :content, String, description: "Content to classify"
        const :context, T.nilable(String), description: "Optional context"
      end

      output do
        const :priority, Priority, description: "Content priority level"
        const :action_type, ActionType, description: "Recommended action"
        const :confidence, ConfidenceLevel, description: "Confidence in classification"
        const :reasoning, String, description: "Explanation of classification"
      end
    end

    it 'generates proper enum schemas for AI classification' do
      output_schema = ClassificationSignature.output_json_schema

      expect(output_schema[:properties][:priority][:type]).to eq("string")
      expect(output_schema[:properties][:priority][:enum]).to eq(["low", "medium", "high", "critical"])

      expect(output_schema[:properties][:action_type][:type]).to eq("string")
      expect(output_schema[:properties][:action_type][:enum]).to eq(["search", "create", "update", "delete", "analyze"])

      expect(output_schema[:properties][:confidence][:type]).to eq("string")
      expect(output_schema[:properties][:confidence][:enum]).to eq(["very_low", "low", "medium", "high", "very_high"])
    end
  end

  describe 'Nested T::Struct Types for Complex AI Data' do
    class AgentWorkflowSignature < DSPy::SorbetSignature
      description "AI agent workflow with nested structured data"

      input do
        const :task_description, String, description: "Task to execute"
        const :previous_tools, T::Array[ToolCall], description: "Previous tool calls"
        const :evidence, T::Array[Evidence], description: "Supporting evidence"
        const :metadata, Metadata, description: "Task metadata"
      end

      output do
        const :next_action, ToolCall, description: "Next tool to call"
        const :updated_metadata, Metadata, description: "Updated task metadata"
        const :summary, String, description: "Workflow summary"
      end
    end

    it 'generates nested object schemas for T::Struct types' do
      input_schema = AgentWorkflowSignature.input_json_schema
      output_schema = AgentWorkflowSignature.output_json_schema

      # Test ToolCall struct schema
      tool_call_schema = input_schema[:properties][:previous_tools][:items]
      expect(tool_call_schema[:type]).to eq("object")
      expect(tool_call_schema[:properties]).to include(:tool_name, :arguments, :timestamp, :result)
      # result is a prop field with nilable type, so should not be required
      expect(tool_call_schema[:required]).to contain_exactly("tool_name", "arguments", "timestamp")

      # Test Evidence struct schema
      evidence_schema = input_schema[:properties][:evidence][:items]
      expect(evidence_schema[:type]).to eq("object")
      expect(evidence_schema[:properties]).to include(:source, :content, :confidence, :timestamp)
      expect(evidence_schema[:required]).to contain_exactly("source", "content", "confidence", "timestamp")

      # Test Metadata struct schema
      metadata_schema = input_schema[:properties][:metadata]
      expect(metadata_schema[:type]).to eq("object")
      expect(metadata_schema[:properties]).to include(:priority, :tags, :created_at, :confidence)
      # priority, tags, created_at are prop fields but not nilable, confidence is nilable
      expect(metadata_schema[:required]).to contain_exactly("priority", "tags", "created_at")
    end
  end

  describe 'Advanced Array and Hash Types for AI Data Processing' do
    class DataProcessingSignature < DSPy::SorbetSignature
      description "AI data processor with complex collection types"

      input do
        const :documents, T::Array[String], description: "Documents to process"
        const :keywords, T::Array[T::Array[String]], description: "Nested keyword arrays"
        const :weights, T::Hash[String, Float], description: "Keyword weights"
        const :config, T::Hash[String, T.any(String, Integer, T::Boolean)], description: "Processing config"
        const :embeddings, T::Array[T::Array[Float]], description: "Document embeddings matrix"
      end

      output do
        const :processed_docs, T::Array[String], description: "Processed documents"
        const :similarity_matrix, T::Array[T::Array[Float]], description: "Document similarity matrix"
        const :keyword_scores, T::Hash[String, Float], description: "Computed keyword scores"
        const :metadata, T::Hash[String, T.untyped], description: "Processing metadata"
      end
    end

    it 'generates proper schemas for complex array and hash types' do
      input_schema = DataProcessingSignature.input_json_schema
      output_schema = DataProcessingSignature.output_json_schema

      # Test nested arrays
      expect(input_schema[:properties][:keywords][:type]).to eq("array")
      expect(input_schema[:properties][:keywords][:items][:type]).to eq("array")
      expect(input_schema[:properties][:keywords][:items][:items][:type]).to eq("string")

      expect(output_schema[:properties][:similarity_matrix][:type]).to eq("array")
      expect(output_schema[:properties][:similarity_matrix][:items][:type]).to eq("array")
      expect(output_schema[:properties][:similarity_matrix][:items][:items][:type]).to eq("number")

      # Test typed hashes
      expect(input_schema[:properties][:weights][:type]).to eq("object")
      expect(input_schema[:properties][:weights][:propertyNames][:type]).to eq("string")
      expect(input_schema[:properties][:weights][:additionalProperties][:type]).to eq("number")

      # Test hash with union values
      expect(input_schema[:properties][:config][:type]).to eq("object")
      expect(input_schema[:properties][:config][:additionalProperties]).to include(:oneOf)
    end
  end

  describe 'Multi-Agent Communication Signature' do
    class AgentMessage < T::Struct
      const :from_agent, String
      const :to_agent, String
      const :message_type, ActionType
      const :content, String
      const :timestamp, Float
      prop :metadata, T.nilable(T::Hash[String, T.untyped])
    end

    class MultiAgentSignature < DSPy::SorbetSignature
      description "Multi-agent system communication handler"

      input do
        const :incoming_messages, T::Array[AgentMessage], description: "Messages from other agents"
        const :agent_id, String, description: "Current agent identifier"
        const :system_state, T::Hash[String, T.untyped], description: "Current system state"
      end

      output do
        const :outgoing_messages, T::Array[AgentMessage], description: "Messages to send"
        const :state_updates, T::Hash[String, T.untyped], description: "System state updates"
        const :coordination_plan, String, description: "Coordination strategy"
      end
    end

    it 'generates schemas for multi-agent communication' do
      input_schema = MultiAgentSignature.input_json_schema
      
      # Test AgentMessage struct in array
      message_schema = input_schema[:properties][:incoming_messages][:items]
      expect(message_schema[:type]).to eq("object")
      expect(message_schema[:properties]).to include(:from_agent, :to_agent, :message_type, :content, :timestamp, :metadata)
      
      # message_type should be ActionType enum
      expect(message_schema[:properties][:message_type][:type]).to eq("string")
      expect(message_schema[:properties][:message_type][:enum]).to eq(["search", "create", "update", "delete", "analyze"])
      
      # metadata is nilable, so not in required array
      expect(message_schema[:required]).to contain_exactly("from_agent", "to_agent", "message_type", "content", "timestamp")
    end
  end

  describe 'T.class_of and Class Types' do
    class ClassTypeSignature < DSPy::SorbetSignature
      description "AI signature with class type parameters"

      input do
        const :model_class, T.class_of(T::Struct), description: "Model class to instantiate"
        const :tool_class, T.class_of(DSPy::Tools::Tool), description: "Tool class to use"
        const :strategy_name, String, description: "Strategy class name"
      end

      output do
        const :instantiated_model, String, description: "Model instance info"
        const :tool_result, String, description: "Tool execution result"
      end
    end

    it 'generates schemas for class type parameters' do
      input_schema = ClassTypeSignature.input_json_schema
      
      expect(input_schema[:properties][:model_class][:type]).to eq("string")
      expect(input_schema[:properties][:model_class][:description]).to eq("Model class to instantiate")

      expect(input_schema[:properties][:tool_class][:type]).to eq("string")
      expect(input_schema[:properties][:tool_class][:description]).to eq("Tool class to use")
    end
  end

  describe 'Real-world AI Agent Scenarios' do
    describe 'RAG (Retrieval-Augmented Generation) Agent' do
      class DocumentChunk < T::Struct
        const :content, String
        const :source, String
        const :chunk_id, String
        const :embedding, T::Array[Float]
        prop :metadata, T.nilable(T::Hash[String, T.untyped])
      end

      class RAGSignature < DSPy::SorbetSignature
        description "RAG agent for document retrieval and synthesis"

        input do
          const :query, String, description: "User query"
          const :retrieved_chunks, T::Array[DocumentChunk], description: "Retrieved document chunks"
          const :max_tokens, Integer, description: "Maximum response tokens"
          const :temperature, Float, description: "Generation temperature"
        end

        output do
          const :synthesized_response, String, description: "Generated response"
          const :source_citations, T::Array[String], description: "Source citations"
          const :confidence_score, Float, description: "Response confidence"
          const :used_chunks, T::Array[String], description: "Chunk IDs used in response"
        end
      end

      it 'generates proper schema for RAG agent' do
        input_schema = RAGSignature.input_json_schema
        
        chunk_schema = input_schema[:properties][:retrieved_chunks][:items]
        expect(chunk_schema[:type]).to eq("object")
        expect(chunk_schema[:properties][:embedding]).to eq({
          type: "array",
          items: { type: "number" }
        })
      end
    end

    describe 'Code Generation Agent' do
      class CodeContext < T::Struct
        const :language, String
        const :framework, T.nilable(String)
        const :dependencies, T::Array[String]
        const :style_preferences, T::Hash[String, T.untyped]
      end

      class CodeGenSignature < DSPy::SorbetSignature
        description "AI code generation agent"

        input do
          const :requirements, String, description: "Code requirements"
          const :context, CodeContext, description: "Development context"
          const :existing_code, T.nilable(String), description: "Existing code to modify"
          const :test_examples, T::Array[T::Hash[String, T.untyped]], description: "Test cases"
        end

        output do
          const :generated_code, String, description: "Generated code"
          const :explanation, String, description: "Code explanation"
          const :test_code, T.nilable(String), description: "Generated tests"
          const :documentation, String, description: "Code documentation"
        end
      end

      it 'generates schema for code generation agent' do
        input_schema = CodeGenSignature.input_json_schema
        
        context_schema = input_schema[:properties][:context]
        expect(context_schema[:type]).to eq("object")
        expect(context_schema[:properties][:dependencies]).to eq({
          type: "array",
          items: { type: "string" }
        })
      end
    end
  end
end
