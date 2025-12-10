# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Tools
    # Represents a single parameter in a tool's schema
    # Maps to JSON Schema property definitions used by LLM tool calling
    class ToolParameterSchema < T::Struct
      const :type, String
      const :description, T.nilable(String), default: nil
      const :enum, T.nilable(T::Array[String]), default: nil
    end

    # Represents the complete schema for a tool's parameters
    # This is the "parameters" field in LLM tool definitions
    class ToolSchema < T::Struct
      const :type, String, default: 'object'
      const :properties, T::Hash[Symbol, ToolParameterSchema], default: {}
      const :required, T::Array[String], default: []

      # Convert to hash format for JSON serialization
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          type: type,
          properties: properties.transform_values do |param|
            h = { type: param.type }
            h[:description] = param.description if param.description
            h[:enum] = param.enum if param.enum
            h
          end,
          required: required
        }
      end
    end
  end
end
