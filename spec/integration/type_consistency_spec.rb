# typed: false
# frozen_string_literal: true

require 'spec_helper'

# Test data types for comprehensive coverage - defined at module level
class TypeTypeTestPriority < T::Enum
    enums do
      Low = new('low')
      Medium = new('medium')
      High = new('high')
      Critical = new('critical')
    end
  end

class TypeTypeTestTaskStatus < T::Enum
    enums do
      Pending = new('pending')
      InProgress = new('in-progress')
      Completed = new('completed')
      Cancelled = new('cancelled')
    end
  end

RSpec.describe 'Type Consistency Across DSPy Components', :vcr do
  class TaskMetadata < T::Struct
    prop :id, String
    prop :priority, TypeTypeTestPriority
    prop :tags, T::Array[String]
    prop :estimated_hours, T.nilable(Float), default: nil
  end

  class TaskRequest < T::Struct
    prop :title, String
    prop :description, String
    prop :status, TypeTypeTestTaskStatus
    prop :metadata, TaskMetadata
    prop :assignees, T::Array[String]
    prop :due_date, T.nilable(String), default: nil
  end

  # Test Tool using comprehensive types
  class TaskManagerTool < DSPy::Tools::Base
    tool_name "task_manager"
    tool_description "Manages tasks with complex type validation"

    sig { params(
      task: TaskRequest,
      priority_threshold: TypeTypeTestPriority,
      active_statuses: T::Array[TypeTypeTestTaskStatus],
      config: T::Hash[String, T.any(String, Integer, Float)]
    ).returns(String) }
    def call(task:, priority_threshold:, active_statuses:, config:)
      result = []
      result << "Task: #{task.title} (#{task.status.serialize})"
      result << "TypeTestPriority: #{task.metadata.priority.serialize} (threshold: #{priority_threshold.serialize})"
      result << "Tags: #{task.metadata.tags.join(', ')}"
      result << "Active statuses: #{active_statuses.map(&:serialize).join(', ')}"
      result << "Config: #{config.inspect}"
      result.join("\n")
    end
  end

  # Test Toolset with same types
  class ProjectToolset < DSPy::Tools::Toolset
    toolset_name "project"

    tool :create_task

    sig { params(title: String, priority: TypeTypeTestPriority, tags: T::Array[String]).returns(String) }
    def create_task(title:, priority:, tags:)
      "Created task: #{title} with priority #{priority.serialize} and tags [#{tags.join(', ')}]"
    end

    tool :update_status

    sig { params(task_id: String, status: TypeTypeTestTaskStatus, reason: T.nilable(String)).returns(String) }
    def update_status(task_id:, status:, reason: nil)
      result = "Updated task #{task_id} to status #{status.serialize}"
      result += " (reason: #{reason})" if reason
      result
    end

    tool :bulk_update

    sig { params(
      task_ids: T::Array[String],
      updates: T::Hash[String, T.any(String, TypeTypeTestPriority, TypeTypeTestTaskStatus)],
      notify: T.nilable(T::Boolean)
    ).returns(String) }
    def bulk_update(task_ids:, updates:, notify: nil)
      "Bulk updated #{task_ids.length} tasks with #{updates.keys.join(', ')}" +
      (notify ? " with notifications" : "")
    end
  end


  describe 'Schema Generation Consistency' do
    it 'generates identical enum schemas across all components' do
      # Tool schema
      tool = TaskManagerTool.new
      tool_schema = tool.call_schema[:function][:parameters][:properties]
      priority_tool_schema = tool_schema[:priority_threshold]

      # Toolset schema
      toolset_schema = ProjectToolset.schema_for_method(:create_task)[:properties]
      priority_toolset_schema = toolset_schema[:priority]

      # All enum schemas should be identical between Tools and Toolsets
      expected_enum_schema = {
        type: "string",
        enum: ['low', 'medium', 'high', 'critical']
      }

      expect(priority_tool_schema).to include(expected_enum_schema)
      expect(priority_toolset_schema).to include(expected_enum_schema)
    end

    it 'generates identical struct schemas across all components' do
      # Tool schema for TaskRequest struct
      tool = TaskManagerTool.new
      tool_schema = tool.call_schema[:function][:parameters][:properties]
      task_schema = tool_schema[:task]

      # Should be object type with proper properties
      expect(task_schema[:type]).to eq("object")

      # Check key properties exist
      [:title, :description, :status, :metadata, :assignees].each do |prop|
        expect(task_schema[:properties]).to have_key(prop)
      end

      # Status should be an enum
      expect(task_schema[:properties][:status][:type]).to eq("string")
      expect(task_schema[:properties][:status][:enum]).to contain_exactly('pending', 'in-progress', 'completed', 'cancelled')
      
      # Nested metadata should also be properly structured
      metadata_schema = task_schema[:properties][:metadata]
      expect(metadata_schema[:type]).to eq("object")
      expect(metadata_schema[:properties][:priority][:type]).to eq("string")
      expect(metadata_schema[:properties][:priority][:enum]).to contain_exactly('low', 'medium', 'high', 'critical')
    end

    it 'generates identical array schemas across all components' do
      # Tool array schema
      tool = TaskManagerTool.new
      tool_schema = tool.call_schema[:function][:parameters][:properties]
      active_statuses_schema = tool_schema[:active_statuses]

      # Toolset array schema
      toolset_schema = ProjectToolset.schema_for_method(:create_task)[:properties]
      tags_schema = toolset_schema[:tags]

      # Both should be arrays
      expect(active_statuses_schema[:type]).to eq("array")
      expect(tags_schema[:type]).to eq("array")

      # Array of enums should have proper item schema
      expect(active_statuses_schema[:items][:type]).to eq("string")
      expect(active_statuses_schema[:items][:enum]).to contain_exactly('pending', 'in-progress', 'completed', 'cancelled')

      # Array of strings should have string items
      expect(tags_schema[:items][:type]).to eq("string")
    end

    it 'generates identical hash schemas across all components' do
      # Tool hash schema
      tool = TaskManagerTool.new
      tool_schema = tool.call_schema[:function][:parameters][:properties]
      config_schema = tool_schema[:config]

      # Toolset hash schema  
      toolset_schema = ProjectToolset.schema_for_method(:bulk_update)[:properties]
      updates_schema = toolset_schema[:updates]

      # All should be object types with additionalProperties
      expect(config_schema[:type]).to eq("object")
      expect(updates_schema[:type]).to eq("object") 

      # Should have additionalProperties defined
      expect(config_schema).to have_key(:additionalProperties)
      expect(updates_schema).to have_key(:additionalProperties)
    end

    it 'handles nilable types consistently' do
      # Tool nilable schema
      tool = TaskManagerTool.new
      tool_schema = tool.call_schema[:function][:parameters][:properties]

      # Should not have required nilable fields
      expect(tool_schema[:task][:properties][:due_date][:type]).to eq(['string', 'null'])

      # Toolset nilable schema
      toolset_schema = ProjectToolset.schema_for_method(:update_status)[:properties]
      expect(toolset_schema[:reason][:type]).to eq(['string', 'null'])
    end
  end

  describe 'Type Coercion Consistency' do
    it 'converts enums consistently across Tools and Toolsets' do
      # Test Tool enum conversion
      tool = TaskManagerTool.new
      
      task_data = {
        'task' => {
          'title' => 'Test Task',
          'description' => 'A test task',
          'status' => 'pending',
          'metadata' => {
            'id' => 'task-1',
            'priority' => 'high',
            'tags' => ['urgent', 'bug-fix']
          },
          'assignees' => ['alice', 'bob']
        },
        'priority_threshold' => 'medium',
        'active_statuses' => ['pending', 'in-progress'],
        'config' => { 'max_retries' => 3, 'timeout' => 30.0 }
      }

      result = tool.dynamic_call(task_data)
      expect(result).to include("TypeTestPriority: high (threshold: medium)")
      expect(result).to include("Active statuses: pending, in-progress")

      # Test Toolset enum conversion
      toolset = ProjectToolset.new
      create_tool = ProjectToolset.to_tools.find { |t| t.name.include?('create_task') }
      
      result2 = create_tool.dynamic_call({
        'title' => 'New Task',
        'priority' => 'critical',
        'tags' => ['feature', 'p1']
      })
      
      expect(result2).to eq("Created task: New Task with priority critical and tags [feature, p1]")
    end

    it 'converts structs consistently' do
      tool = TaskManagerTool.new
      
      task_data = {
        'task' => {
          'title' => 'Complex Task',
          'description' => 'A complex task with nested data',
          'status' => 'in-progress',
          'metadata' => {
            'id' => 'task-complex',
            'priority' => 'critical',
            'tags' => ['complex', 'nested'],
            'estimated_hours' => 8.5
          },
          'assignees' => ['charlie'],
          'due_date' => '2024-12-31'
        },
        'priority_threshold' => 'low',
        'active_statuses' => ['in-progress', 'completed'],
        'config' => { 'parallel' => true }
      }

      result = tool.dynamic_call(task_data)
      expect(result).to include("Task: Complex Task (in-progress)")
      expect(result).to include("TypeTestPriority: critical (threshold: low)")
      expect(result).to include("Tags: complex, nested")
    end

    it 'handles validation errors consistently' do
      tool = TaskManagerTool.new
      
      # Invalid enum value
      invalid_data = {
        'task' => {
          'title' => 'Invalid Task',
          'description' => 'Task with invalid status',
          'status' => 'invalid-status',
          'metadata' => {
            'id' => 'task-invalid',
            'priority' => 'high',
            'tags' => []
          },
          'assignees' => []
        },
        'priority_threshold' => 'medium',
        'active_statuses' => ['pending'],
        'config' => {}
      }

      result = tool.dynamic_call(invalid_data)
      expect(result).to match(/Error/)
    end
  end

  describe 'LLM Integration Consistency' do    
    it 'generates equivalent tool schemas for LLM consumption' do
      # Get tool schema for LLM
      tool = TaskManagerTool.new
      tool_schema = tool.call_schema

      # Get toolset schema for LLM
      toolset_tools = ProjectToolset.to_tools
      create_task_tool = toolset_tools.find { |t| t.name.include?('create_task') }
      
      # Both should have compatible structure for LLM tools
      expect(tool_schema[:type]).to eq('function')
      expect(tool_schema[:function]).to have_key(:name)
      expect(tool_schema[:function]).to have_key(:description)
      expect(tool_schema[:function]).to have_key(:parameters)
      
      # Toolset should also provide proper function structure
      expect(create_task_tool).not_to be_nil
      expect(create_task_tool.name).to include('create_task')
    end
  end
end