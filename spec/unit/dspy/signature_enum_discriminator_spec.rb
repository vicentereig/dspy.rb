# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Enum-based Discriminator for Union Types' do
  # Define action types as an enum (namespaced to avoid conflicts)
  module EnumDiscriminatorTest
    class ActionType < T::Enum
      enums do
        SpawnSubtask = new('spawn_subtask')
        MarkComplete = new('mark_complete') 
        Continue = new('continue')
      end
    end
  end

  # Define the action structs
  module CoordinationActions
    class SpawnSubtask < T::Struct
      const :description, String
      const :priority, String, default: 'medium'
      prop :parent_task_id, T.nilable(String)
    end
    
    class MarkComplete < T::Struct
      const :task_id, String
      const :completion_reason, String
    end
    
    class Continue < T::Struct
      const :reason, String
      prop :wait_time_seconds, T.nilable(Integer)
    end
  end

  # Signature using enum as discriminator
  class ResearchCoordinationSignature < DSPy::Signature
    output do
      const :next_action, EnumDiscriminatorTest::ActionType  # Enum discriminator
      const :action_details, T.any(
        CoordinationActions::SpawnSubtask,
        CoordinationActions::MarkComplete,
        CoordinationActions::Continue
      )
    end
  end

  describe 'automatic conversion with enum discriminator' do
    it 'converts Hash to SpawnSubtask struct when next_action is spawn_subtask' do
      prediction_data = {
        next_action: 'spawn_subtask',  # String that will be deserialized to enum
        action_details: {
          description: 'Research quantum computing applications',
          priority: 'high',
          parent_task_id: 'task-001'
        }
      }

      prediction = DSPy::Prediction.new(ResearchCoordinationSignature.output_schema, **prediction_data)
      
      expect(prediction.next_action).to eq(EnumDiscriminatorTest::ActionType::SpawnSubtask)
      expect(prediction.action_details).to be_a(CoordinationActions::SpawnSubtask)
      expect(prediction.action_details.description).to eq('Research quantum computing applications')
      expect(prediction.action_details.priority).to eq('high')
      expect(prediction.action_details.parent_task_id).to eq('task-001')
    end

    it 'converts Hash to MarkComplete struct when next_action is mark_complete' do
      prediction_data = {
        next_action: 'mark_complete',
        action_details: {
          task_id: 'task-001',
          completion_reason: 'All research objectives achieved'
        }
      }

      prediction = DSPy::Prediction.new(ResearchCoordinationSignature.output_schema, **prediction_data)
      
      expect(prediction.next_action).to eq(EnumDiscriminatorTest::ActionType::MarkComplete)
      expect(prediction.action_details).to be_a(CoordinationActions::MarkComplete)
      expect(prediction.action_details.task_id).to eq('task-001')
      expect(prediction.action_details.completion_reason).to eq('All research objectives achieved')
    end

    it 'converts Hash to Continue struct when next_action is continue' do
      prediction_data = {
        next_action: 'continue',
        action_details: {
          reason: 'Waiting for external API response',
          wait_time_seconds: 30
        }
      }

      prediction = DSPy::Prediction.new(ResearchCoordinationSignature.output_schema, **prediction_data)
      
      expect(prediction.next_action).to eq(EnumDiscriminatorTest::ActionType::Continue)
      expect(prediction.action_details).to be_a(CoordinationActions::Continue)
      expect(prediction.action_details.reason).to eq('Waiting for external API response')
      expect(prediction.action_details.wait_time_seconds).to eq(30)
    end

    it 'handles enum instances passed directly' do
      prediction_data = {
        next_action: EnumDiscriminatorTest::ActionType::SpawnSubtask,  # Enum instance
        action_details: {
          description: 'Direct enum test',
          priority: 'low'
        }
      }

      prediction = DSPy::Prediction.new(ResearchCoordinationSignature.output_schema, **prediction_data)
      
      expect(prediction.next_action).to eq(EnumDiscriminatorTest::ActionType::SpawnSubtask)
      expect(prediction.action_details).to be_a(CoordinationActions::SpawnSubtask)
    end

    it 'uses default values when not provided' do
      prediction_data = {
        next_action: 'spawn_subtask',
        action_details: {
          description: 'Test default values'
          # priority not provided, should use default
        }
      }

      prediction = DSPy::Prediction.new(ResearchCoordinationSignature.output_schema, **prediction_data)
      
      expect(prediction.action_details.priority).to eq('medium')  # default value
    end
  end

  describe 'enum-struct mapping conventions' do
    it 'maps enum values to struct types based on naming convention' do
      # The mapping should work as:
      # EnumDiscriminatorTest::ActionType::SpawnSubtask ('spawn_subtask') -> CoordinationActions::SpawnSubtask
      # EnumDiscriminatorTest::ActionType::MarkComplete ('mark_complete') -> CoordinationActions::MarkComplete
      # EnumDiscriminatorTest::ActionType::Continue ('continue') -> CoordinationActions::Continue
      
      # This is tested implicitly in the above tests, but let's be explicit
      class MappingTestSignature < DSPy::Signature
        output do
          const :action, EnumDiscriminatorTest::ActionType
          const :details, T.any(
            CoordinationActions::SpawnSubtask,
            CoordinationActions::MarkComplete,
            CoordinationActions::Continue
          )
        end
      end

      # Test all mappings
      test_cases = {
        'spawn_subtask' => [
          CoordinationActions::SpawnSubtask,
          { description: 'Research task', priority: 'high' }
        ],
        'mark_complete' => [
          CoordinationActions::MarkComplete,
          { task_id: 'task-123', completion_reason: 'Task completed successfully' }
        ],
        'continue' => [
          CoordinationActions::Continue,
          { reason: 'Waiting for more data' }
        ]
      }
      
      test_cases.each do |enum_value, (expected_struct, details)|
        prediction = DSPy::Prediction.new(
          MappingTestSignature.output_schema,
          action: enum_value,
          details: details
        )
        
        expect(prediction.details).to be_a(expected_struct)
      end
    end
  end
end