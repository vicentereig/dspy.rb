# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'
require_relative '../type_system/sorbet_json_schema'
require_relative '../mixins/type_coercion'

module DSPy
  module Tools
    # Base class for all Sorbet-based tools with DSL support
    class Base
      extend T::Sig
      extend T::Helpers
      include DSPy::Mixins::TypeCoercion

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
        def call_schema_object
          method_obj = instance_method(:call)
          sig_info = T::Utils.signature_for_method(method_obj)

          if sig_info.nil?
            # Fallback for methods without signatures
            return {
              type: "object",
              properties: {},
              required: []
            }
          end

          properties = {}
          required = []

          # Handle positional arguments
          sig_info.arg_types.each do |param_name, param_type|
            next if param_name == :block # Skip block parameters

            schema = DSPy::TypeSystem::SorbetJsonSchema.type_to_json_schema(param_type)
            properties[param_name] = schema.merge({ description: "Parameter #{param_name}" })

            # Check if parameter is required (not nilable)
            unless param_type.class.name.include?('Union') && param_type.name.include?('NilClass')
              required << param_name.to_s
            end
          end

          # Handle keyword arguments (more common in Ruby)
          sig_info.kwarg_types.each do |param_name, param_type|
            next if param_name == :block # Skip block parameters

            schema = DSPy::TypeSystem::SorbetJsonSchema.type_to_json_schema(param_type)
            properties[param_name] = schema.merge({ description: "Parameter #{param_name}" })

            # Check if parameter is required by looking at required kwarg names
            if sig_info.req_kwarg_names.include?(param_name)
              required << param_name.to_s
            else
              properties[param_name][:description] += " (optional)"
            end
          end

          {
            type: "object",
            properties: properties,
            required: required
          }
        end

        # Get the full tool schema for LLM tools format
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def call_schema
          {
            type: 'function',
            function: {
              name: 'call',
              description: "Call the #{self.name} tool",
              parameters: call_schema_object
            }
          }
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
        schema_obj = self.class.call_schema_object
        tool_info = {
          name: name,
          description: description,
          parameters: schema_obj
        }
        JSON.generate(tool_info)
      end

      # Get the full call schema compatible with LLM tools format
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def call_schema
        self.class.call_schema
      end

      # Dynamic call method for ReAct agent - parses JSON arguments and calls the typed method
      sig { params(args_json: T.untyped).returns(T.untyped) }
      def dynamic_call(args_json)
        # Parse arguments based on the call schema
        schema = self.class.call_schema_object

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
                  rescue JSON::ParserError => e
                    raise ArgumentError, "Invalid JSON input: #{e.message}"
                  end
                else
                  raise ArgumentError, "Expected Hash or JSON string, got #{args_json.class}"
                end

          # Convert string keys to symbols and validate types
          kwargs = {}
          
          # Get method signature for type information
          method_obj = self.class.instance_method(:call)
          sig_info = T::Utils.signature_for_method(method_obj)
          
          if sig_info
            # Handle kwargs using type signature information
            sig_info.kwarg_types.each do |param_name, param_type|
              next if param_name == :block
              
              key = param_name.to_s
              if args.key?(key)
                kwargs[param_name] = coerce_value_to_type(args[key], param_type)
              elsif schema[:required].include?(key)
                raise ArgumentError, "Missing required parameter: #{key}"
              end
            end
            
            # Handle positional args if any
            sig_info.arg_types.each do |param_name, param_type|
              next if param_name == :block
              
              key = param_name.to_s
              if args.key?(key)
                kwargs[param_name] = coerce_value_to_type(args[key], param_type)
              elsif schema[:required].include?(key)
                raise ArgumentError, "Missing required parameter: #{key}"
              end
            end
          end

          call(**kwargs)
        end
      end

      # Subclasses must implement their own call method with their own signature

    end
  end
end
