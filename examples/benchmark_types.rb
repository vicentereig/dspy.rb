# frozen_string_literal: true

require 'sorbet-runtime'

# Enum definitions for TodoListManagementSignature
class TodoStatus < T::Enum
  enums do
    Pending = new('pending')
    InProgress = new('in_progress')
    Completed = new('completed')
    Failed = new('failed')
  end
end

class UserRole < T::Enum
  enums do
    Admin = new('admin')
    Manager = new('manager')
    Member = new('member')
  end
end

# Struct definitions for complex nested types
class UserProfile < T::Struct
  const :user_id, String
  const :role, UserRole
  const :timezone, String, default: 'UTC'
end

class ProjectContext < T::Struct
  const :project_id, String
  const :active_lists, T::Array[String]
  const :available_tags, T::Array[String], default: []
end

class TodoItem < T::Struct
  const :id, String
  const :title, String
  const :description, String
  const :status, TodoStatus
  const :tags, T::Array[String], default: []
  const :priority, String, default: 'medium'
end

# TodoSummary simplified for OpenAI compatibility
class TodoSummary < T::Struct
  const :total_todos, Integer, default: 0
  const :upcoming_due, Integer, default: 0
end

# Action struct definitions for union types
class CreateTodoAction < T::Struct
  const :title, String

  const :priority, String, default: 'medium'
  const :tags, T::Array[String], default: []
end

class UpdateTodoAction < T::Struct
  const :todo_id, String
  const :updates, String
  const :reason, String
end

class DeleteTodoAction < T::Struct
  const :todo_id, String
  const :reason, String
end

class AssignTodoAction < T::Struct
  const :todo_id, String
  const :assignee, String
  const :notify, T::Boolean, default: true
end

# Main signature for todo list management
class TodoListManagementSignature < DSPy::Signature
  description "AI-powered todo list management system with complex nested types"

  input do
    const :query, String,
      description: "Natural language command or request about todos"
    const :context, ProjectContext,
      description: "Current project state including active lists, sprint information"
    const :user_profile, UserProfile,
      description: "User information including role, permissions, timezone"
  end

  output do
    const :action, T.any(
      CreateTodoAction,
      UpdateTodoAction,
      DeleteTodoAction,
      AssignTodoAction
    ), description: "Primary action to execute - automatically discriminated by _type field"

    const :affected_todos, T::Array[TodoItem],
      description: "List of todo items that will be created, modified, or impacted"

    const :summary, TodoSummary,
      description: "Updated state summary showing total counts, status breakdown"

    const :related_actions, T::Array[T.any(
      CreateTodoAction,
      UpdateTodoAction,
      DeleteTodoAction,
      AssignTodoAction
    )], description: "Additional actions to execute in batch"
  end
end
