# frozen_string_literal: true

require 'spec_helper'

# Test structs for union type conversion
module TestActions
  class SpawnTask < T::Struct
    const :description, String
    const :priority, String
    prop :parent_id, T.nilable(String)
  end

  class CompleteTask < T::Struct
    const :task_id, String
    const :result, String
  end

  class Continue < T::Struct
    const :reason, String
  end
end

RSpec.describe 'Automatic Union Type Conversion' do
  describe 'T.any() with automatic discriminator detection' do
    class AutoConversionSignature < DSPy::Signature
      output do
        const :action_type, String
        const :action_details, T.any(
          TestActions::SpawnTask,
          TestActions::CompleteTask,
          TestActions::Continue
        )
      end
    end

    it 'automatically converts Hash to appropriate struct based on discriminator field' do
      # Test SpawnTask conversion
      prediction_data = {
        action_type: "spawn_task",
        action_details: {
          description: "Research AI safety",
          priority: "high",
          parent_id: nil
        }
      }

      prediction = DSPy::Prediction.new(AutoConversionSignature.output_schema, **prediction_data)
      
      expect(prediction.action_details).to be_a(TestActions::SpawnTask)
      expect(prediction.action_details.description).to eq("Research AI safety")
      expect(prediction.action_details.priority).to eq("high")
      expect(prediction.action_details.parent_id).to be_nil
    end

    it 'converts CompleteTask based on discriminator' do
      prediction_data = {
        action_type: "complete_task",
        action_details: {
          task_id: "task-123",
          result: "Successfully completed research"
        }
      }

      prediction = DSPy::Prediction.new(AutoConversionSignature.output_schema, **prediction_data)
      
      expect(prediction.action_details).to be_a(TestActions::CompleteTask)
      expect(prediction.action_details.task_id).to eq("task-123")
      expect(prediction.action_details.result).to eq("Successfully completed research")
    end

    it 'converts Continue based on discriminator' do
      prediction_data = {
        action_type: "continue",
        action_details: {
          reason: "Waiting for more data"
        }
      }

      prediction = DSPy::Prediction.new(AutoConversionSignature.output_schema, **prediction_data)
      
      expect(prediction.action_details).to be_a(TestActions::Continue)
      expect(prediction.action_details.reason).to eq("Waiting for more data")
    end
  end

  describe 'discriminator detection patterns' do
    it 'uses preceding String field as discriminator for T.any() field' do
      class MultiFieldSignature < DSPy::Signature
        output do
          const :status, String
          const :message, String
          const :next_action, String  # This should be the discriminator
          const :action_details, T.any(
            TestActions::SpawnTask,
            TestActions::CompleteTask
          )
          const :notes, String
        end
      end

      prediction_data = {
        status: "processing",
        message: "Task in progress",
        next_action: "spawn_task",
        action_details: {
          description: "Sub-task",
          priority: "medium"
        },
        notes: "Additional context"
      }

      prediction = DSPy::Prediction.new(MultiFieldSignature.output_schema, **prediction_data)
      
      expect(prediction.action_details).to be_a(TestActions::SpawnTask)
    end
  end

  describe 'nested struct conversion in arrays' do
    class ArrayConversionSignature < DSPy::Signature
      output do
        const :task_type, String
        const :tasks, T::Array[T.any(
          TestActions::SpawnTask,
          TestActions::CompleteTask
        )]
      end
    end

    it 'converts array of hashes to array of structs' do
      prediction_data = {
        task_type: "batch_processing",
        tasks: [
          {
            description: "Task 1",
            priority: "high"
          },
          {
            task_id: "task-456",
            result: "Completed"
          }
        ]
      }

      prediction = DSPy::Prediction.new(ArrayConversionSignature.output_schema, **prediction_data)
      
      expect(prediction.tasks).to be_an(Array)
      expect(prediction.tasks[0]).to be_a(TestActions::SpawnTask)
      expect(prediction.tasks[0].description).to eq("Task 1")
      expect(prediction.tasks[1]).to be_a(TestActions::CompleteTask)
      expect(prediction.tasks[1].task_id).to eq("task-456")
    end
  end

  describe 'edge cases' do
    it 'handles case where no discriminator field exists' do
      class NoDiscriminatorSignature < DSPy::Signature
        output do
          const :result, T.any(
            TestActions::SpawnTask,
            TestActions::CompleteTask
          )
        end
      end

      # Should fall back to examining the hash structure
      prediction_data = {
        result: {
          description: "New task",
          priority: "low"
        }
      }

      prediction = DSPy::Prediction.new(NoDiscriminatorSignature.output_schema, **prediction_data)
      
      # Should match based on field structure
      expect(prediction.result).to be_a(TestActions::SpawnTask)
    end

    it 'handles nil values in T.any(T.nilable(...))' do
      class NilableUnionSignature < DSPy::Signature
        output do
          const :optional_action, T.nilable(T.any(
            TestActions::SpawnTask,
            TestActions::CompleteTask
          ))
        end
      end

      prediction = DSPy::Prediction.new(NilableUnionSignature.output_schema, optional_action: nil)
      expect(prediction.optional_action).to be_nil
    end
  end
end