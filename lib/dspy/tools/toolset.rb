# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'

module DSPy
  module Tools
    # Base class for multi-method tool classes where each method can be exposed as an individual tool
    # Similar to Rails controllers where each action is exposed as an endpoint
    class Toolset
      extend T::Sig
      extend T::Helpers

      class << self
        extend T::Sig

        sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
        attr_reader :exposed_tools

        # DSL method to expose a method as a tool
        sig { params(method_name: Symbol, tool_name: T.nilable(String), description: T.nilable(String)).void }
        def expose_tool(method_name, tool_name: nil, description: nil)
          @exposed_tools ||= {}
          @exposed_tools[method_name] = {
            tool_name: tool_name || "#{toolset_name}_#{method_name}",
            description: description || "#{method_name.to_s.tr('_', ' ').capitalize} operation"
          }
        end

        # DSL method to set the toolset name prefix
        sig { params(name: T.nilable(String)).returns(String) }
        def toolset_name(name = nil)
          if name
            @toolset_name = name
          else
            @toolset_name || self.name.split('::').last.gsub(/Toolset$/, '').downcase
          end
        end

        # Get all exposed tools as individual tool instances
        sig { returns(T::Array[ToolProxy]) }
        def to_tools
          instance = new
          (@exposed_tools || {}).map do |method_name, config|
            ToolProxy.new(instance, method_name, config[:tool_name], config[:description])
          end
        end

        # Generate schema for a specific method using Sorbet signatures
        sig { params(method_name: Symbol).returns(T::Hash[Symbol, T.untyped]) }
        def schema_for_method(method_name)
          method_obj = instance_method(method_name)
          sig_info = T::Utils.signature_for_method(method_obj)

          if sig_info.nil?
            # Fallback for methods without signatures
            return {
              type: :object,
              properties: {},
              required: []
            }
          end

          # Reuse the schema generation logic from Base
          properties = {}
          required = []

          # Handle keyword arguments (most common in Ruby)
          sig_info.kwarg_types.each do |param_name, param_type|
            next if param_name == :block

            properties[param_name] = {
              type: sorbet_type_to_json_schema(param_type)[:type],
              description: "Parameter #{param_name}"
            }

            # Check if parameter is required
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

        # Convert Sorbet types to JSON Schema types (extracted from Base)
        sig { params(sorbet_type: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def sorbet_type_to_json_schema(sorbet_type)
          if sorbet_type.is_a?(T::Types::Simple)
            raw_type = sorbet_type.raw_type

            case raw_type
            when String
              { type: :string }
            when Integer
              { type: :integer }
            when Float, Numeric
              { type: :number }
            when TrueClass, FalseClass, T::Boolean
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

      # Inner class that wraps a method as a tool, compatible with DSPy::Tools::Base interface
      class ToolProxy < Base
        extend T::Sig

        sig { params(instance: Toolset, method_name: Symbol, tool_name: String, description: String).void }
        def initialize(instance, method_name, tool_name, description)
          @instance = instance
          @method_name = method_name
          @tool_name_override = tool_name
          @description_override = description
        end

        sig { override.returns(String) }
        def name
          @tool_name_override
        end

        sig { override.returns(String) }
        def description
          @description_override
        end

        sig { override.returns(String) }
        def schema
          schema_obj = @instance.class.schema_for_method(@method_name)
          tool_info = {
            name: name,
            description: description,
            parameters: schema_obj
          }
          JSON.generate(tool_info)
        end

        # The main call method that tools must implement
        sig { params(kwargs: T.untyped).returns(T.untyped) }
        def call(**kwargs)
          @instance.send(@method_name, **kwargs)
        end

        sig { override.params(args_json: T.untyped).returns(T.untyped) }
        def dynamic_call(args_json)
          schema = @instance.class.schema_for_method(@method_name)

          if schema[:properties].empty?
            @instance.send(@method_name)
          else
            # Parse arguments
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

            @instance.send(@method_name, **kwargs)
          end
        rescue => e
          "Error: #{e.message}"
        end
      end
    end
  end
end