# frozen_string_literal: true

require "spec_helper"

# TypeSerializer is now implemented in lib/dspy/type_serializer.rb

RSpec.describe "Single-field union types" do
  describe "JSON schema generation with _type field" do
    context "when a T::Struct is used in a signature" do
      class SingleFieldTestAction < T::Struct
        const :task_id, String
        const :description, String
      end

      class SingleFieldTestSignature < DSPy::Signature
        description "Test signature for single field type discrimination"

        input do
          const :query, String
        end

        output do
          const :action, SingleFieldTestAction
        end
      end

      it "adds a _type field with const constraint to struct schemas" do
        schema = SingleFieldTestSignature.output_json_schema

        action_schema = schema[:properties][:action]
        expect(action_schema[:properties]).to have_key(:_type)
        expect(action_schema[:properties][:_type]).to eq({
          type: "string",
          const: "SingleFieldTestAction"
        })
        expect(action_schema[:required]).to include("_type")
      end
    end

    context "when T.any() is used with multiple struct types" do
      class UnionTypeSpawnTask < T::Struct
        const :task_description, String
        const :assignee, String
      end

      class UnionTypeCompleteTask < T::Struct
        const :task_id, String
        const :result, String
      end

      class UnionTypeSignature < DSPy::Signature
        description "Test signature for union types with type discrimination"

        input do
          const :query, String
        end

        output do
          const :action, T.any(UnionTypeSpawnTask, UnionTypeCompleteTask)
        end
      end

      it "generates oneOf schema with _type fields for each struct" do
        schema = UnionTypeSignature.output_json_schema

        action_schema = schema[:properties][:action]
        expect(action_schema).to have_key(:oneOf)
        expect(action_schema[:oneOf].length).to eq(2)

        spawn_schema = action_schema[:oneOf].find { |s| s[:properties][:_type][:const] == "UnionTypeSpawnTask" }
        expect(spawn_schema).not_to be_nil
        expect(spawn_schema[:properties]).to include(
          _type: { type: "string", const: "UnionTypeSpawnTask" },
          task_description: { type: "string" },
          assignee: { type: "string" }
        )
        expect(spawn_schema[:required]).to include("_type", "task_description", "assignee")

        complete_schema = action_schema[:oneOf].find { |s| s[:properties][:_type][:const] == "UnionTypeCompleteTask" }
        expect(complete_schema).not_to be_nil
        expect(complete_schema[:properties]).to include(
          _type: { type: "string", const: "UnionTypeCompleteTask" },
          task_id: { type: "string" },
          result: { type: "string" }
        )
        expect(complete_schema[:required]).to include("_type", "task_id", "result")
      end
    end

    context "when a struct already has a _type field" do
      class UnionTypeConflictingStruct < T::Struct
        const :_type, String
        const :data, String
      end

      class UnionTypeConflictingSignature < DSPy::Signature
        description "Test signature for _type field conflicts"

        output do
          const :result, UnionTypeConflictingStruct
        end
      end

      it "raises an error about the conflict" do
        expect {
          UnionTypeConflictingSignature.output_json_schema
        }.to raise_error(DSPy::ValidationError, /_type field conflict/)
      end
    end
  end

  describe "automatic _type injection during serialization" do
    class UnionTypeSerializableAction < T::Struct
      const :command, String
      const :target, String
    end

    it "injects _type field when converting struct to hash" do
      action = UnionTypeSerializableAction.new(command: "deploy", target: "production")

      # This method doesn't exist yet - will need to implement
      serialized = DSPy::TypeSerializer.serialize(action)

      expect(serialized).to eq({
        "_type" => "UnionTypeSerializableAction",
        "command" => "deploy",
        "target" => "production"
      })
    end

    it "handles nested structs with _type injection" do
      class UnionTypeNestedPayload < T::Struct
        const :data, String
      end

      class UnionTypeContainerAction < T::Struct
        const :name, String
        const :payload, UnionTypeNestedPayload
      end

      container = UnionTypeContainerAction.new(
        name: "test",
        payload: UnionTypeNestedPayload.new(data: "nested")
      )

      serialized = DSPy::TypeSerializer.serialize(container)

      expect(serialized).to eq({
        "_type" => "UnionTypeContainerAction",
        "name" => "test",
        "payload" => {
          "_type" => "UnionTypeNestedPayload",
          "data" => "nested"
        }
      })
    end
  end

  describe "_type-based deserialization in DSPy::Prediction" do
    class UnionTypeDeserializeSpawn < T::Struct
      const :task, String
    end

    class UnionTypeDeserializeComplete < T::Struct
      const :task_id, String
    end

    class UnionTypeDeserializeSignature < DSPy::Signature
      description "Test signature for union type deserialization"

      output do
        const :action, T.any(UnionTypeDeserializeSpawn, UnionTypeDeserializeComplete)
      end
    end

    it "uses _type field to instantiate correct struct type" do
      json_response = {
        action: {
          _type: "UnionTypeDeserializeSpawn",
          task: "Write tests"
        }
      }

      prediction = DSPy::Prediction.new(UnionTypeDeserializeSignature.output_schema, **json_response)

      expect(prediction.action).to be_a(UnionTypeDeserializeSpawn)
      expect(prediction.action.task).to eq("Write tests")
    end

    it "handles arrays of unions with _type" do
      class UnionTypeArrayUnionSignature < DSPy::Signature
        description "Test signature for arrays of union types"

        output do
          const :actions, T::Array[T.any(UnionTypeDeserializeSpawn, UnionTypeDeserializeComplete)]
        end
      end

      json_response = {
        actions: [
          { _type: "UnionTypeDeserializeSpawn", task: "Task 1" },
          { _type: "UnionTypeDeserializeComplete", task_id: "123" },
          { _type: "UnionTypeDeserializeSpawn", task: "Task 2" }
        ]
      }

      prediction = DSPy::Prediction.new(UnionTypeArrayUnionSignature.output_schema, **json_response)

      expect(prediction.actions.length).to eq(3)
      expect(prediction.actions[0]).to be_a(UnionTypeDeserializeSpawn)
      expect(prediction.actions[1]).to be_a(UnionTypeDeserializeComplete)
      expect(prediction.actions[2]).to be_a(UnionTypeDeserializeSpawn)
    end

    it "falls back to structural matching when _type field is missing" do
      json_response = {
        action: {
          task: "Missing type"
        }
      }

      # Without _type, it will try to match based on structure
      # UnionTypeDeserializeSpawn has a 'task' field, so it will match
      prediction = DSPy::Prediction.new(UnionTypeDeserializeSignature.output_schema, **json_response)

      expect(prediction.action).to be_a(UnionTypeDeserializeSpawn)
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
      prediction = DSPy::Prediction.new(UnionTypeDeserializeSignature.output_schema, **json_response)

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
        DSPy::Prediction.new(UnionTypeDeserializeSignature.output_schema, **json_response)
      }.to raise_error(DSPy::DeserializationError, /Unknown type: UnknownType/)
    end
  end
end