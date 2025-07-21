# frozen_string_literal: true

require "spec_helper"

# TypeSerializer is now implemented in lib/dspy/type_serializer.rb

RSpec.describe "Single-field union types" do
  describe "JSON schema generation with _type field" do
    context "when a T::Struct is used in a signature" do
      class TestAction < T::Struct
        const :task_id, String
        const :description, String
      end

      class TestSignature < DSPy::Signature
        input do
          const :query, String
        end
        
        output do
          const :action, TestAction
        end
      end

      it "adds a _type field with const constraint to struct schemas" do
        schema = TestSignature.output_json_schema

        action_schema = schema[:properties][:action]
        expect(action_schema[:properties]).to have_key(:_type)
        expect(action_schema[:properties][:_type]).to eq({
          type: "string",
          const: "TestAction"
        })
        expect(action_schema[:required]).to include("_type")
      end
    end

    context "when T.any() is used with multiple struct types" do
      class SpawnTask < T::Struct
        const :task_description, String
        const :assignee, String
      end

      class CompleteTask < T::Struct
        const :task_id, String
        const :result, String
      end

      class UnionSignature < DSPy::Signature
        input do
          const :query, String
        end
        
        output do
          const :action, T.any(SpawnTask, CompleteTask)
        end
      end

      it "generates oneOf schema with _type fields for each struct" do
        schema = UnionSignature.output_json_schema

        action_schema = schema[:properties][:action]
        expect(action_schema).to have_key(:oneOf)
        expect(action_schema[:oneOf].length).to eq(2)

        spawn_schema = action_schema[:oneOf].find { |s| s[:properties][:_type][:const] == "SpawnTask" }
        expect(spawn_schema).not_to be_nil
        expect(spawn_schema[:properties]).to include(
          _type: { type: "string", const: "SpawnTask" },
          task_description: { type: "string" },
          assignee: { type: "string" }
        )
        expect(spawn_schema[:required]).to include("_type", "task_description", "assignee")

        complete_schema = action_schema[:oneOf].find { |s| s[:properties][:_type][:const] == "CompleteTask" }
        expect(complete_schema).not_to be_nil
        expect(complete_schema[:properties]).to include(
          _type: { type: "string", const: "CompleteTask" },
          task_id: { type: "string" },
          result: { type: "string" }
        )
        expect(complete_schema[:required]).to include("_type", "task_id", "result")
      end
    end

    context "when a struct already has a _type field" do
      class ConflictingStruct < T::Struct
        const :_type, String
        const :data, String
      end

      class ConflictingSignature < DSPy::Signature
        output do
          const :result, ConflictingStruct
        end
      end

      it "raises an error about the conflict" do
        expect {
          ConflictingSignature.output_json_schema
        }.to raise_error(DSPy::ValidationError, /_type field conflict/)
      end
    end
  end

  describe "automatic _type injection during serialization" do
    class SerializableAction < T::Struct
      const :command, String
      const :target, String
    end

    it "injects _type field when converting struct to hash" do
      action = SerializableAction.new(command: "deploy", target: "production")
      
      # This method doesn't exist yet - will need to implement
      serialized = DSPy::TypeSerializer.serialize(action)
      
      expect(serialized).to eq({
        "_type" => "SerializableAction",
        "command" => "deploy",
        "target" => "production"
      })
    end

    it "handles nested structs with _type injection" do
      class NestedPayload < T::Struct
        const :data, String
      end

      class ContainerAction < T::Struct
        const :name, String
        const :payload, NestedPayload
      end

      container = ContainerAction.new(
        name: "test",
        payload: NestedPayload.new(data: "nested")
      )

      serialized = DSPy::TypeSerializer.serialize(container)

      expect(serialized).to eq({
        "_type" => "ContainerAction",
        "name" => "test",
        "payload" => {
          "_type" => "NestedPayload",
          "data" => "nested"
        }
      })
    end
  end

  describe "_type-based deserialization in DSPy::Prediction" do
    class DeserializeSpawn < T::Struct
      const :task, String
    end

    class DeserializeComplete < T::Struct
      const :task_id, String
    end

    class DeserializeSignature < DSPy::Signature
      output do
        const :action, T.any(DeserializeSpawn, DeserializeComplete)
      end
    end

    it "uses _type field to instantiate correct struct type" do
      json_response = {
        action: {
          _type: "DeserializeSpawn",
          task: "Write tests"
        }
      }

      prediction = DSPy::Prediction.new(DeserializeSignature.output_schema, **json_response)
      
      expect(prediction.action).to be_a(DeserializeSpawn)
      expect(prediction.action.task).to eq("Write tests")
    end

    it "handles arrays of unions with _type" do
      class ArrayUnionSignature < DSPy::Signature
        output do
          const :actions, T::Array[T.any(DeserializeSpawn, DeserializeComplete)]
        end
      end

      json_response = {
        actions: [
          { _type: "DeserializeSpawn", task: "Task 1" },
          { _type: "DeserializeComplete", task_id: "123" },
          { _type: "DeserializeSpawn", task: "Task 2" }
        ]
      }

      prediction = DSPy::Prediction.new(ArrayUnionSignature.output_schema, **json_response)
      
      expect(prediction.actions.length).to eq(3)
      expect(prediction.actions[0]).to be_a(DeserializeSpawn)
      expect(prediction.actions[1]).to be_a(DeserializeComplete)
      expect(prediction.actions[2]).to be_a(DeserializeSpawn)
    end

    it "falls back to structural matching when _type field is missing" do
      json_response = {
        action: {
          task: "Missing type"
        }
      }

      # Without _type, it will try to match based on structure
      # DeserializeSpawn has a 'task' field, so it will match
      prediction = DSPy::Prediction.new(DeserializeSignature.output_schema, **json_response)
      
      expect(prediction.action).to be_a(DeserializeSpawn)
      expect(prediction.action.task).to eq("Missing type")
    end
    
    it "returns original hash when _type field is missing and structure doesn't match any type" do
      # Create a hash that doesn't match any struct's required fields
      json_response = {
        action: {
          unknown_field: "test"
        }
      }

      # When no struct matches, it will return the original hash
      prediction = DSPy::Prediction.new(DeserializeSignature.output_schema, **json_response)
      
      expect(prediction.action).to be_a(Hash)
      expect(prediction.action[:unknown_field]).to eq("test")
    end

    it "provides clear error when _type doesn't match any union type" do
      json_response = {
        action: {
          _type: "UnknownType",
          data: "test"
        }
      }

      expect {
        DSPy::Prediction.new(DeserializeSignature.output_schema, **json_response)
      }.to raise_error(DSPy::DeserializationError, /Unknown type: UnknownType/)
    end
  end
end