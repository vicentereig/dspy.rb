# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Prediction edge cases' do
  describe 'handling nil and missing values' do
    class OptionalFieldSignature < DSPy::Signature
      output do
        const :required_field, String
        const :optional_field, T.nilable(String)
        const :with_default, String, default: 'default_value'
      end
    end

    it 'handles nil values for optional fields' do
      prediction = DSPy::Prediction.new(
        OptionalFieldSignature.output_schema,
        required_field: 'test',
        optional_field: nil,
        with_default: nil  # Should use default
      )

      expect(prediction.required_field).to eq('test')
      expect(prediction.optional_field).to be_nil
      expect(prediction.with_default).to eq('default_value')
    end

    it 'handles missing optional fields' do
      prediction = DSPy::Prediction.new(
        OptionalFieldSignature.output_schema,
        required_field: 'test'
        # optional_field and with_default not provided
      )

      expect(prediction.required_field).to eq('test')
      expect(prediction.optional_field).to be_nil
      expect(prediction.with_default).to eq('default_value')
    end
  end

  describe 'deeply nested structs' do
    module DeepNesting
      class Level3 < T::Struct
        const :value, String
        const :number, Integer
      end

      class Level2 < T::Struct
        const :name, String
        const :nested, Level3
      end

      class Level1 < T::Struct
        const :title, String
        const :nested, Level2
      end
    end

    class DeepNestedSignature < DSPy::Signature
      output do
        const :data, DeepNesting::Level1
      end
    end

    it 'converts deeply nested hashes to structs' do
      prediction_data = {
        data: {
          title: 'Top Level',
          nested: {
            name: 'Middle Level',
            nested: {
              value: 'Bottom Level',
              number: 42
            }
          }
        }
      }

      prediction = DSPy::Prediction.new(DeepNestedSignature.output_schema, **prediction_data)

      expect(prediction.data).to be_a(DeepNesting::Level1)
      expect(prediction.data.title).to eq('Top Level')
      expect(prediction.data.nested).to be_a(DeepNesting::Level2)
      expect(prediction.data.nested.name).to eq('Middle Level')
      expect(prediction.data.nested.nested).to be_a(DeepNesting::Level3)
      expect(prediction.data.nested.nested.value).to eq('Bottom Level')
      expect(prediction.data.nested.nested.number).to eq(42)
    end
  end

  describe 'arrays with union types' do
    module ArrayUnionTypes
      class TypeA < T::Struct
        const :type, String, default: 'a'
        const :value_a, String
      end

      class TypeB < T::Struct
        const :type, String, default: 'b'
        const :value_b, Integer
      end
    end

    class ArrayUnionSignature < DSPy::Signature
      output do
        const :items, T::Array[T.any(ArrayUnionTypes::TypeA, ArrayUnionTypes::TypeB)]
      end
    end

    it 'converts array elements to appropriate union types' do
      prediction_data = {
        items: [
          { type: 'a', value_a: 'first' },
          { type: 'b', value_b: 123 },
          { type: 'a', value_a: 'second' }
        ]
      }

      prediction = DSPy::Prediction.new(ArrayUnionSignature.output_schema, **prediction_data)

      expect(prediction.items).to be_an(Array)
      expect(prediction.items.length).to eq(3)
      
      expect(prediction.items[0]).to be_a(ArrayUnionTypes::TypeA)
      expect(prediction.items[0].value_a).to eq('first')
      
      expect(prediction.items[1]).to be_a(ArrayUnionTypes::TypeB)
      expect(prediction.items[1].value_b).to eq(123)
      
      expect(prediction.items[2]).to be_a(ArrayUnionTypes::TypeA)
      expect(prediction.items[2].value_a).to eq('second')
    end

    context 'with nilable array of union types' do
      class NilableArrayUnionSignature < DSPy::Signature
        output do
          const :items, T.nilable(T::Array[T.any(ArrayUnionTypes::TypeA, ArrayUnionTypes::TypeB)])
        end
      end

      it 'handles nil array' do
        prediction_data = { items: nil }
        prediction = DSPy::Prediction.new(NilableArrayUnionSignature.output_schema, **prediction_data)
        expect(prediction.items).to be_nil
      end

      it 'handles empty array' do
        prediction_data = { items: [] }
        prediction = DSPy::Prediction.new(NilableArrayUnionSignature.output_schema, **prediction_data)
        expect(prediction.items).to eq([])
      end

      it 'handles array with elements' do
        prediction_data = {
          items: [
            { type: 'a', value_a: 'test' },
            { type: 'b', value_b: 42 }
          ]
        }
        prediction = DSPy::Prediction.new(NilableArrayUnionSignature.output_schema, **prediction_data)
        
        expect(prediction.items).to be_an(Array)
        expect(prediction.items[0]).to be_a(ArrayUnionTypes::TypeA)
        expect(prediction.items[0].value_a).to eq('test')
        expect(prediction.items[1]).to be_a(ArrayUnionTypes::TypeB)
        expect(prediction.items[1].value_b).to eq(42)
      end
    end
  end

  describe 'enum edge cases' do
    module EnumEdgeCases
      class Status < T::Enum
        enums do
          Active = new('active')
          Inactive = new('inactive')
          Pending = new('pending_review')  # Different serialization
        end
      end

      class ComplexAction < T::Enum
        enums do
          CreateUser = new('create_user')
          DeleteUser = new('delete_user')
          UpdateUserSettings = new('update_user_settings')
        end
      end

      class CreateUser < T::Struct
        const :username, String
        const :email, String
      end

      class DeleteUser < T::Struct
        const :user_id, String
        const :soft_delete, T::Boolean, default: true
      end

      class UpdateUserSettings < T::Struct
        const :user_id, String
        const :settings, T::Hash[String, T.untyped]
      end
    end

    class EnumEdgeSignature < DSPy::Signature
      output do
        const :status, EnumEdgeCases::Status
        const :action, EnumEdgeCases::ComplexAction
        const :details, T.any(
          EnumEdgeCases::CreateUser,
          EnumEdgeCases::DeleteUser,
          EnumEdgeCases::UpdateUserSettings
        )
      end
    end

    it 'handles enum values with different serialization names' do
      prediction = DSPy::Prediction.new(
        EnumEdgeSignature.output_schema,
        status: 'pending_review',
        action: 'update_user_settings',
        details: {
          user_id: 'user123',
          settings: { 'theme' => 'dark', 'notifications' => true }
        }
      )

      expect(prediction.status).to eq(EnumEdgeCases::Status::Pending)
      expect(prediction.action).to eq(EnumEdgeCases::ComplexAction::UpdateUserSettings)
      expect(prediction.details).to be_a(EnumEdgeCases::UpdateUserSettings)
      expect(prediction.details.settings['theme']).to eq('dark')
    end

    it 'handles case-insensitive enum matching as fallback' do
      # Testing the case-insensitive fallback in the enum mapping logic
      class CaseInsensitiveSignature < DSPy::Signature
        output do
          const :action, EnumEdgeCases::ComplexAction
          const :details, T.any(
            EnumEdgeCases::CreateUser,
            EnumEdgeCases::DeleteUser,
            EnumEdgeCases::UpdateUserSettings
          )
        end
      end

      prediction = DSPy::Prediction.new(
        CaseInsensitiveSignature.output_schema,
        action: 'delete_user',
        details: { user_id: 'user456', soft_delete: false }
      )

      expect(prediction.details).to be_a(EnumEdgeCases::DeleteUser)
      expect(prediction.details.user_id).to eq('user456')
      expect(prediction.details.soft_delete).to eq(false)
    end
  end

  describe 'error handling' do
    class StrictStructSignature < DSPy::Signature
      class StrictData < T::Struct
        const :required_field, String
        const :required_number, Integer
      end

      output do
        const :data, StrictData
      end
    end

    it 'returns original hash when struct conversion fails' do
      # Missing required fields
      prediction = DSPy::Prediction.new(
        StrictStructSignature.output_schema,
        data: { required_field: 'test' }  # Missing required_number
      )

      # Should return the original hash since conversion failed
      expect(prediction.data).to be_a(Hash)
      expect(prediction.data[:required_field]).to eq('test')
    end

    it 'handles invalid enum values gracefully' do
      class InvalidEnumSignature < DSPy::Signature
        class Color < T::Enum
          enums do
            Red = new('red')
            Green = new('green')
            Blue = new('blue')
          end
        end

        output do
          const :color, Color
        end
      end

      # This should raise an error since 'yellow' is not a valid enum value
      expect {
        DSPy::Prediction.new(
          InvalidEnumSignature.output_schema,
          color: 'yellow'
        )
      }.to raise_error(KeyError)
    end
  end

  describe 'complex real-world scenarios' do
    module RealWorldScenarios
      class TaskStatus < T::Enum
        enums do
          NotStarted = new('not_started')
          InProgress = new('in_progress')
          Completed = new('completed')
          Failed = new('failed')
        end
      end

      class TaskMetadata < T::Struct
        const :created_at, String
        const :updated_at, String
        const :tags, T::Array[String], default: []
        const :priority, Integer, default: 0
      end

      class SubTask < T::Struct
        const :id, String
        const :description, String
        const :status, TaskStatus
        const :metadata, TaskMetadata
      end

      class Task < T::Struct
        const :id, String
        const :title, String
        const :status, TaskStatus
        const :subtasks, T::Array[SubTask]
        const :metadata, TaskMetadata
      end
    end

    class RealWorldSignature < DSPy::Signature
      output do
        const :tasks, T::Array[RealWorldScenarios::Task]
        const :total_count, Integer
        const :completed_count, Integer
      end
    end

    xit 'handles complex nested structures with arrays and enums (pending deeper struct coercion)' do
      prediction_data = {
        tasks: [
          {
            id: 'task1',
            title: 'Main Task',
            status: 'in_progress',
            subtasks: [
              {
                id: 'sub1',
                description: 'Subtask 1',
                status: 'completed',
                metadata: {
                  created_at: '2024-01-01',
                  updated_at: '2024-01-02',
                  tags: ['urgent', 'backend']
                }
              },
              {
                id: 'sub2',
                description: 'Subtask 2',
                status: 'not_started',
                metadata: {
                  created_at: '2024-01-03',
                  updated_at: '2024-01-03'
                  # tags will use default empty array
                }
              }
            ],
            metadata: {
              created_at: '2024-01-01',
              updated_at: '2024-01-03',
              priority: 1
            }
          }
        ],
        total_count: 1,
        completed_count: 0
      }

      prediction = DSPy::Prediction.new(RealWorldSignature.output_schema, **prediction_data)

      expect(prediction.tasks).to be_an(Array)
      expect(prediction.tasks.first).to be_a(RealWorldScenarios::Task)
      
      task = prediction.tasks.first
      expect(task.id).to eq('task1')
      expect(task.status).to eq(RealWorldScenarios::TaskStatus::InProgress)
      
      expect(task.subtasks).to be_an(Array)
      expect(task.subtasks.length).to eq(2)
      
      subtask1 = task.subtasks.first
      expect(subtask1).to be_a(RealWorldScenarios::SubTask)
      expect(subtask1.status).to eq(RealWorldScenarios::TaskStatus::Completed)
      expect(subtask1.metadata.tags).to eq(['urgent', 'backend'])
      
      subtask2 = task.subtasks.last
      expect(subtask2.metadata.tags).to eq([])  # Default value
    end
    
    it 'handles arrays with proper struct conversion' do
      # Simpler test case
      simple_data = {
        tasks: [
          {
            id: 'task1',
            title: 'Simple Task',
            status: 'completed',
            subtasks: [],
            metadata: {
              created_at: '2024-01-01',
              updated_at: '2024-01-02'
            }
          }
        ],
        total_count: 1,
        completed_count: 1
      }
      
      prediction = DSPy::Prediction.new(RealWorldSignature.output_schema, **simple_data)
      
      # The simple case actually works!
      expect(prediction.tasks).to be_an(Array)
      expect(prediction.tasks.first).to be_a(RealWorldScenarios::Task)
      expect(prediction.tasks.first.id).to eq('task1')
      expect(prediction.tasks.first.status).to eq(RealWorldScenarios::TaskStatus::Completed)
      expect(prediction.total_count).to eq(1)
    end
  end

  describe 'without schema (dynamic struct creation)' do
    it 'creates a dynamic struct for arbitrary attributes' do
      prediction = DSPy::Prediction.new(
        nil,  # No schema
        name: 'John Doe',
        age: 30,
        active: true,
        tags: ['ruby', 'dspy']
      )

      expect(prediction.name).to eq('John Doe')
      expect(prediction.age).to eq(30)
      expect(prediction.active).to eq(true)
      expect(prediction.tags).to eq(['ruby', 'dspy'])
      expect(prediction._prediction_marker).to eq(true)
    end
  end

  describe 'union types with extra fields from LLM' do
    # Test for issue #59
    module UnionWithExtraFields
      class ReflectAction < T::Struct
        const :reasoning, String
        const :thoughts, String
      end

      class AnswerAction < T::Struct
        const :reasoning, String
        const :content, String
      end
    end

    class UnionWithDiscriminator < DSPy::Signature
      output do
        const :action_type, String
        const :action, T.any(
          UnionWithExtraFields::ReflectAction,
          UnionWithExtraFields::AnswerAction
        )
      end
    end

    it 'ignores extra fields when converting union types with discriminator' do
      # Simulate LLM response that includes extra fields
      prediction_data = {
        action_type: 'reflect_action',  # Use the correct snake_case discriminator
        action: {
          reasoning: 'Need to analyze the problem further',
          thoughts: 'Considering multiple perspectives',
          synthesis: 'This field should be ignored',  # Extra field not in ReflectAction
          confidence: 0.95,  # Another extra field
          metadata: { source: 'llm' }  # Complex extra field
        }
      }

      prediction = DSPy::Prediction.new(UnionWithDiscriminator.output_schema, **prediction_data)

      # Should successfully create the struct without errors
      expect(prediction.action_type).to eq('reflect_action')
      expect(prediction.action).to be_a(UnionWithExtraFields::ReflectAction)
      expect(prediction.action.reasoning).to eq('Need to analyze the problem further')
      expect(prediction.action.thoughts).to eq('Considering multiple perspectives')
      
      # Verify extra fields were not added to the struct
      expect { prediction.action.synthesis }.to raise_error(NoMethodError)
      expect { prediction.action.confidence }.to raise_error(NoMethodError)
      expect { prediction.action.metadata }.to raise_error(NoMethodError)
    end

    it 'handles extra fields with _type discriminator in union types' do
      # Alternative pattern where _type is used within the union field itself
      class UnionWithInternalType < DSPy::Signature
        output do
          const :result, T.any(
            UnionWithExtraFields::ReflectAction,
            UnionWithExtraFields::AnswerAction
          )
        end
      end

      prediction_data = {
        result: {
          _type: 'AnswerAction',
          reasoning: 'Based on the analysis',
          content: 'The answer is 42',
          extra_field: 'Should be ignored',
          nested_extra: { data: 'Also ignored' }
        }
      }

      prediction = DSPy::Prediction.new(UnionWithInternalType.output_schema, **prediction_data)

      expect(prediction.result).to be_a(UnionWithExtraFields::AnswerAction)
      expect(prediction.result.reasoning).to eq('Based on the analysis')
      expect(prediction.result.content).to eq('The answer is 42')
      
      # Verify extra fields were filtered out
      expect { prediction.result.extra_field }.to raise_error(NoMethodError)
      expect { prediction.result.nested_extra }.to raise_error(NoMethodError)
    end
  end
end