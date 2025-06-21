# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'

module DSPy
  module Tools
    # Base class for all Sorbet-based tools with DSL support
    class Base
      extend T::Sig
      extend T::Helpers

      class << self
        extend T::Sig

        sig { returns(T.nilable(String)) }
        attr_reader :tool_name_value, :tool_description_value

        # DSL method to set tool name
        sig { params(name: String).void }
        def tool_name(name)
          @tool_name_value = name
        end

        # DSL method to set tool description
        sig { params(description: String).void }
        def tool_description(description)
          @tool_description_value = description
        end

        # Get the JSON schema for the call method based on its Sorbet signature
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def call_schema
          method_obj = instance_method(:call)
          sig_info = T::Utils.signature_for_method(method_obj)

          if sig_info.nil?
            # Fallback for methods without signatures
            return {
              type: :object,
              properties: {},
              required: []
            }
          end

          properties = {}
          required = []

          # Handle positional arguments
          sig_info.arg_types.each do |param_name, param_type|
            next if param_name == :block # Skip block parameters

            properties[param_name] = {
              type: sorbet_type_to_json_schema(param_type)[:type],
              description: "Parameter #{param_name}"
            }

            # Check if parameter is required (not nilable)
            unless param_type.class.name.include?('Union') && param_type.name.include?('NilClass')
              required << param_name.to_s
            end
          end

          # Handle keyword arguments (more common in Ruby)
          sig_info.kwarg_types.each do |param_name, param_type|
            next if param_name == :block # Skip block parameters

            properties[param_name] = {
              type: sorbet_type_to_json_schema(param_type)[:type],
              description: "Parameter #{param_name}"
            }

            # Check if parameter is required by looking at required kwarg names
            if sig_info.req_kwarg_names.include?(param_name)
              required << param_name.to_s
            else
              properties[param_name][:description] += " (optional)"
            end
          end

          {
            type: :object,
            properties: properties,
            required: required
          }
        end

        private

        # Convert Sorbet types to JSON Schema types
        sig { params(sorbet_type: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def sorbet_type_to_json_schema(sorbet_type)
          if sorbet_type.is_a?(T::Types::Simple)
            raw_type = sorbet_type.raw_type

            if raw_type == String
              { type: :string }
            elsif raw_type == Integer
              { type: :integer }
            elsif raw_type == Float
              { type: :number }
            elsif raw_type == Numeric
              { type: :number }
            elsif raw_type == TrueClass || raw_type == FalseClass
              { type: :boolean }
            elsif raw_type == T::Boolean
              { type: :boolean }
            else
              { type: :string, description: "#{raw_type} (converted to string)" }
            end
          elsif sorbet_type.is_a?(T::Types::Union)
            # Handle nilable types
            non_nil_types = sorbet_type.types.reject { |t| t == T::Utils.coerce(NilClass) }
            if non_nil_types.length == 1
              result = sorbet_type_to_json_schema(non_nil_types.first)
              result[:description] = "#{result[:description] || ''} (optional)".strip
              result
            else
              { type: :string, description: "Union type (converted to string)" }
            end
          elsif sorbet_type.is_a?(T::Types::TypedArray)
            {
              type: :array,
              items: sorbet_type_to_json_schema(sorbet_type.type)
            }
          else
            { type: :string, description: "#{sorbet_type} (converted to string)" }
          end
        end
      end

      # Instance methods that tools can use
      sig { returns(String) }
      def name
        self.class.tool_name_value || self.class.name&.split('::')&.last&.downcase || 'unknown_tool'
      end

      sig { returns(String) }
      def description
        self.class.tool_description_value || "Tool: #{name}"
      end

      # Get the JSON schema string for the tool, formatted for LLM consumption
      sig { returns(String) }
      def schema
        schema_obj = self.class.call_schema
        tool_info = {
          name: name,
          description: description,
          parameters: schema_obj
        }
        JSON.pretty_generate(tool_info)
      end

      # Dynamic call method for ReAct agent - parses JSON arguments and calls the typed method
      sig { params(args_json: T.untyped).returns(T.untyped) }
      def dynamic_call(args_json)
        # Parse arguments based on the call schema
        schema = self.class.call_schema

        if schema[:properties].empty?
          # No parameters - call without arguments
          call
        else
          # Parse arguments and call with keyword arguments
          args = case args_json
                when Hash
                  args_json
                when String
                  begin
                    JSON.parse(args_json)
                  rescue JSON::ParserError
                    return "Error: Invalid JSON input"
                  end
                else
                  return "Error: Expected Hash or JSON string"
                end

          # Convert string keys to symbols and validate types
          kwargs = {}
          schema[:properties].each do |param_name, param_schema|
            key = param_name.to_s
            if args.key?(key)
              kwargs[param_name] = convert_argument_type(args[key], param_schema)
            elsif schema[:required].include?(key)
              return "Error: Missing required parameter: #{key}"
            end
          end

          call(**kwargs)
        end
      rescue => e
        "Error: #{e.message}"
      end

      # Subclasses must implement their own call method with their own signature

      private

      # Convert argument to the expected type based on JSON schema
      sig { params(value: T.untyped, schema: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def convert_argument_type(value, schema)
        case schema[:type]
        when :integer
          value.is_a?(Integer) ? value : value.to_i
        when :number
          # Always convert to Float for :number types to ensure compatibility with strict Float signatures
          value.to_f
        when :boolean
          case value
          when true, false
            value
          when "true", "1", 1
            true
          when "false", "0", 0
            false
          else
            !!value
          end
        else
          value.to_s
        end
      end
    end
  end
end
