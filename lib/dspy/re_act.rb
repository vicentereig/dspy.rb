# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'predict'
require_relative 'signature'
require_relative 'chain_of_thought'
require 'json'
require_relative 'mixins/struct_builder'

module DSPy
  # Define a simple struct for history entries with proper type annotations
  class HistoryEntry < T::Struct
    const :step, Integer
    prop :thought, T.nilable(String)
    prop :action, T.nilable(String)
    prop :action_input, T.nilable(T.any(String, Numeric, T::Hash[T.untyped, T.untyped], T::Array[T.untyped]))
    prop :observation, T.untyped

    # Custom serialization to ensure compatibility with the rest of the code
    def to_h
      {
        step: step,
        thought: thought,
        action: action,
        action_input: action_input,
        observation: observation
      }.compact
    end
  end
  # Base class for ReAct thought generation - will be customized per input type
  class ThoughtBase < DSPy::Signature
    description "Generate a thought about what to do next to process the given inputs."

    output do
      const :thought, String,
        description: "Reasoning about what to do next, considering the history and observations."
      const :action, String,
        description: "The action to take. MUST be one of the tool names listed in `available_tools` input, or the literal string \"finish\" to provide the final answer."
      const :action_input, T.untyped,
        description: "Input for the chosen action. If action is a tool name, this MUST be a JSON object matching the tool's schema. If action is \"finish\", this field MUST contain the final result based on processing the input data. This result MUST be directly taken from the relevant Observation in the history if available."
    end
  end

  class NextStep < T::Enum
    enums do
      Continue = new("continue")
      Finish = new("finish")
    end
  end

  # Base class for observation processing - will be customized per input type
  class ReActObservationBase < DSPy::Signature
    description "Process the observation from a tool and decide what to do next."

    output do
      const :interpretation, String,
        description: "Interpretation of the observation"
      const :next_step, NextStep,
        description: "What to do next: '#{NextStep::Continue}' or '#{NextStep::Finish}'"
    end
  end

  # ReAct Agent using Sorbet signatures
  class ReAct < Predict
    extend T::Sig
    include Mixins::StructBuilder

    # AvailableTool struct for better type safety in ReAct agents
    class AvailableTool < T::Struct
      const :name, String
      const :description, String
      const :schema, T::Hash[Symbol, T.untyped]
    end

    FINISH_ACTION = "finish"
    sig { returns(T.class_of(DSPy::Signature)) }
    attr_reader :original_signature_class

    sig { returns(T.class_of(T::Struct)) }
    attr_reader :enhanced_output_struct

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :tools

    sig { returns(Integer) }
    attr_reader :max_iterations


    sig { params(signature_class: T.class_of(DSPy::Signature), tools: T::Array[DSPy::Tools::Base], max_iterations: Integer).void }
    def initialize(signature_class, tools: [], max_iterations: 5)
      @original_signature_class = signature_class
      @tools = T.let({}, T::Hash[String, T.untyped])
      tools.each { |tool| @tools[tool.name.downcase] = tool }
      @max_iterations = max_iterations

      # Create dynamic ActionEnum class with tool names + finish
      @action_enum_class = create_action_enum_class

      # Create dynamic signature classes that include the original input fields
      thought_signature = create_thought_signature(signature_class)
      observation_signature = create_observation_signature(signature_class)

      # Create thought generator using Predict to preserve field descriptions
      @thought_generator = T.let(DSPy::Predict.new(thought_signature), DSPy::Predict)

      # Create observation processor using Predict to preserve field descriptions
      @observation_processor = T.let(DSPy::Predict.new(observation_signature), DSPy::Predict)

      # Create enhanced output struct with ReAct fields
      @enhanced_output_struct = create_enhanced_output_struct(signature_class)
      enhanced_output_struct = @enhanced_output_struct

      # Create enhanced signature class
      enhanced_signature = Class.new(DSPy::Signature) do
        # Set the description
        description signature_class.description

        # Use the same input struct
        @input_struct_class = signature_class.input_struct_class

        # Use the enhanced output struct with ReAct fields
        @output_struct_class = enhanced_output_struct

        # Store original signature name
        @original_signature_name = signature_class.name

        class << self
          attr_reader :input_struct_class, :output_struct_class, :original_signature_name
          
          # Override name to return the original signature name
          def name
            @original_signature_name || super
          end
        end
      end

      # Call parent constructor with enhanced signature
      super(enhanced_signature)
    end

    sig { params(kwargs: T.untyped).returns(T.untyped).override }
    def forward(**kwargs)
      # Validate input
      input_struct = @original_signature_class.input_struct_class.new(**kwargs)

      # Execute ReAct reasoning loop
      reasoning_result = execute_react_reasoning_loop(input_struct)

      # Create enhanced output with all ReAct data
      create_enhanced_result(kwargs, reasoning_result)
    end

    private

    # Serialize value for LLM display
    sig { params(value: T.untyped).returns(T.any(String, T::Hash[T.untyped, T.untyped], T::Array[T.untyped])) }
    def serialize_for_llm(value)
      return value if value.nil?
      return value if value.is_a?(String)

      # For structured data, serialize to JSON-compatible format
      begin
        TypeSerializer.serialize(value)
      rescue
        # Fallback to string representation if serialization fails
        value.to_s
      end
    end

    # Serialize history for LLM consumption
    sig { params(history: T::Array[HistoryEntry]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialize_history_for_llm(history)
      history.map do |entry|
        {
          step: entry.step,
          thought: entry.thought,
          action: entry.action,
          action_input: serialize_for_llm(entry.action_input),
          observation: serialize_for_llm(entry.observation)
        }.compact
      end
    end

    # Creates a dynamic ActionEnum class with tool names and "finish"
    sig { returns(T.class_of(T::Enum)) }
    def create_action_enum_class
      tool_names = @tools.keys
      all_actions = tool_names + [FINISH_ACTION]
      
      # Create a dynamic enum class using proper T::Enum pattern
      enum_class = Class.new(T::Enum)
      
      # Build the enums block code dynamically
      enum_definitions = all_actions.map do |action_name|
        const_name = action_name.upcase.gsub(/[^A-Z0-9_]/, '_')
        "#{const_name} = new(#{action_name.inspect})"
      end.join("\n        ")
      
      enum_class.class_eval <<~RUBY
        enums do
          #{enum_definitions}
        end
      RUBY
      
      enum_class
    end

    # Creates a dynamic Thought signature that includes the original input fields
    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(DSPy::Signature)) }
    def create_thought_signature(signature_class)
      action_enum_class = @action_enum_class
      # Create new class that inherits from DSPy::Signature
      Class.new(DSPy::Signature) do
        # Set description
        description "Generate a thought about what to do next to process the given inputs."

        # Define input fields
        input do
          const :input_context, String,
            description: "Serialized representation of all input fields"
          const :history, T::Array[HistoryEntry],
            description: "Previous thoughts and actions, including observations from tools."
          const :available_tools, T::Array[AvailableTool],
            description: "Array of available tools with their JSON schemas."
        end

        # Define output fields (same as ThoughtBase)
        output do
          const :thought, String,
            description: "Reasoning about what to do next, considering the history and observations."
          const :action, action_enum_class,
            description: "The action to take. MUST be one of the tool names listed in `available_tools` input, or the literal string \"finish\" to provide the final answer."
          const :action_input, T.untyped,
            description: "Input for the chosen action. If action is a tool name, this MUST be a JSON object matching the tool's schema. If action is \"finish\", this field MUST contain the final result based on processing the input data."
        end
      end
    end

    # Creates a dynamic observation signature that includes the original input fields
    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(DSPy::Signature)) }
    def create_observation_signature(signature_class)
      # Create new class that inherits from DSPy::Signature
      Class.new(DSPy::Signature) do
        # Set description
        description "Process the observation from a tool and decide what to do next."

        # Define input fields
        input do
          const :input_context, String,
            description: "Serialized representation of all input fields"
          const :history, T::Array[HistoryEntry],
            description: "Previous thoughts, actions, and observations."
          const :observation, T.untyped,
            description: "The result from the last action"
        end

        # Define output fields (same as ReActObservationBase)
        output do
          const :interpretation, String,
            description: "Interpretation of the observation"
          const :next_step, NextStep,
            description: "What to do next: '#{NextStep::Continue}' or '#{NextStep::Finish}'"
        end
      end
    end

    # Executes the main ReAct reasoning loop
    sig { params(input_struct: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def execute_react_reasoning_loop(input_struct)
      history = T.let([], T::Array[HistoryEntry])
      available_tools_desc = @tools.map { |name, tool|
        schema = JSON.parse(tool.schema)
        AvailableTool.new(
          name: name,
          description: tool.description,
          schema: schema.transform_keys(&:to_sym)
        )
      }
      final_answer = T.let(nil, T.untyped)
      iterations_count = 0
      last_observation = T.let(nil, T.untyped)
      tools_used = []

      while should_continue_iteration?(iterations_count, final_answer)
        iterations_count += 1

        iteration_result = execute_single_iteration(
          input_struct, history, available_tools_desc, iterations_count, tools_used, last_observation
        )

        if iteration_result[:should_finish]
          final_answer = iteration_result[:final_answer]
          break
        end

        history = iteration_result[:history]
        tools_used = iteration_result[:tools_used]
        last_observation = iteration_result[:last_observation]
      end

      handle_max_iterations_if_needed(iterations_count, final_answer, tools_used, history)

      {
        history: history,
        iterations: iterations_count,
        tools_used: tools_used.uniq,
        final_answer: final_answer || default_no_answer_message
      }
    end

    # Executes a single iteration of the ReAct loop
    sig { params(input_struct: T.untyped, history: T::Array[HistoryEntry], available_tools_desc: T::Array[AvailableTool], iteration: Integer, tools_used: T::Array[String], last_observation: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def execute_single_iteration(input_struct, history, available_tools_desc, iteration, tools_used, last_observation)
      # Track each iteration with agent span
      DSPy::Context.with_span(
        operation: 'react.iteration',
        **DSPy::ObservationType::Agent.langfuse_attributes,
        'dspy.module' => 'ReAct',
        'react.iteration' => iteration,
        'react.max_iterations' => @max_iterations,
        'react.history_length' => history.length,
        'react.tools_used' => tools_used.uniq
      ) do
        # Generate thought and action
        thought_obj = @thought_generator.forward(
          input_context: DSPy::TypeSerializer.serialize(input_struct).to_json,
          history: serialize_history_for_llm(history),
          available_tools: available_tools_desc
        )

        # Process thought result
        if finish_action?(thought_obj.action)
          final_answer = handle_finish_action(
            thought_obj.action_input, last_observation, iteration,
            thought_obj.thought, thought_obj.action, history
          )
          return { should_finish: true, final_answer: final_answer }
        end

        # Execute tool action
        observation = execute_tool_with_instrumentation(
          thought_obj.action, thought_obj.action_input, iteration
        )

        # Convert action enum to string for processing and storage
        action_str = thought_obj.action.respond_to?(:serialize) ? thought_obj.action.serialize : thought_obj.action.to_s
        
        # Track tools used
        tools_used << action_str.downcase if valid_tool?(thought_obj.action)

        # Add to history
        history << create_history_entry(
          iteration, thought_obj.thought, action_str,
          thought_obj.action_input, observation
        )

        # Process observation and decide next step
        observation_decision = process_observation_and_decide_next_step(
          input_struct, history, observation, available_tools_desc, iteration
        )

        if observation_decision[:should_finish]
          return { should_finish: true, final_answer: observation_decision[:final_answer] }
        end

        emit_iteration_complete_event(
          iteration, thought_obj.thought, action_str,
          thought_obj.action_input, observation, tools_used
        )

        {
          should_finish: false,
          history: history,
          tools_used: tools_used,
          last_observation: observation
        }
      end
    end

    # Creates enhanced output struct with ReAct-specific fields
    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(T::Struct)) }
    def create_enhanced_output_struct(signature_class)
      input_props = signature_class.input_struct_class.props
      output_props = signature_class.output_struct_class.props

      build_enhanced_struct(
        { input: input_props, output: output_props },
        {
          history: [T::Array[T::Hash[Symbol, T.untyped]], "ReAct execution history"],
          iterations: [Integer, "Number of iterations executed"],
          tools_used: [T::Array[String], "List of tools used during execution"]
        }
      )
    end

    # Creates enhanced result struct
    sig { params(input_kwargs: T::Hash[Symbol, T.untyped], reasoning_result: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def create_enhanced_result(input_kwargs, reasoning_result)
      output_field_name = @original_signature_class.output_struct_class.props.keys.first
      final_answer = reasoning_result[:final_answer]

      output_data = input_kwargs.merge({
        history: reasoning_result[:history].map(&:to_h),
        iterations: reasoning_result[:iterations],
        tools_used: reasoning_result[:tools_used]
      })

      # Get the expected output type
      output_field_type = @original_signature_class.output_struct_class.props[output_field_name][:type_object]

      # Try to deserialize final_answer to match the expected output type
      deserialized_value = deserialize_final_answer(final_answer, output_field_type, reasoning_result[:history])

      output_data[output_field_name] = deserialized_value

      @enhanced_output_struct.new(**output_data)
    end

    # Deserialize final answer to match expected output type
    sig { params(final_answer: T.untyped, output_field_type: T.untyped, history: T::Array[HistoryEntry]).returns(T.untyped) }
    def deserialize_final_answer(final_answer, output_field_type, history)
      # When finish is called, check if the last tool observation matches the expected type
      # If so, use it directly - the LLM calling "finish" is just a signal we're done
      last_tool_observation = history.reverse.find { |entry| !entry.observation.nil? }&.observation
      if last_tool_observation && type_matches?(last_tool_observation, output_field_type)
        return last_tool_observation
      end

      # If final_answer already matches the expected type, use it
      return final_answer if type_matches?(final_answer, output_field_type)

      # Try to convert based on expected type
      converted = convert_to_expected_type(final_answer, output_field_type)
      return converted if type_matches?(converted, output_field_type)

      # If conversion failed and we have a nil final_answer, return default
      return default_value_for_type(output_field_type) if final_answer.nil?

      # Return final_answer as-is and let validation catch any type mismatch
      final_answer
    end

    # Convert value to expected type
    sig { params(value: T.untyped, type_object: T.untyped).returns(T.untyped) }
    def convert_to_expected_type(value, type_object)
      case type_object
      when T::Types::TypedArray
        return value unless value.is_a?(Array)
        element_type = type_object.type
        value.map { |item| convert_to_expected_type(item, element_type) }
      when T::Types::Simple
        struct_class = type_object.raw_type
        if struct_class < T::Struct && value.is_a?(Hash)
          # Convert string keys to symbol keys
          symbolized = value.transform_keys(&:to_sym)
          struct_class.new(**symbolized)
        else
          value
        end
      else
        value
      end
    end

    # Check if a value matches the expected type
    sig { params(value: T.untyped, type_object: T.untyped).returns(T::Boolean) }
    def type_matches?(value, type_object)
      case type_object
      when T::Types::TypedArray
        value.is_a?(Array) && (value.empty? || value.first.is_a?(T::Struct))
      when T::Types::TypedHash
        value.is_a?(Hash)
      when T::Types::Simple
        value.is_a?(type_object.raw_type)
      when T::Types::Union
        # For union types, check if value matches any of the types
        type_object.types.any? { |t| type_matches?(value, t) }
      else
        false
      end
    end

    # Helper methods for ReAct logic
    sig { params(iterations_count: Integer, final_answer: T.untyped).returns(T::Boolean) }
    def should_continue_iteration?(iterations_count, final_answer)
      final_answer.nil? && (@max_iterations.nil? || iterations_count < @max_iterations)
    end

    sig { params(action: T.nilable(T.any(String, T::Enum))).returns(T::Boolean) }
    def finish_action?(action)
      return false unless action
      action_str = action.respond_to?(:serialize) ? action.serialize : action.to_s
      action_str.downcase == FINISH_ACTION
    end

    sig { params(action: T.nilable(T.any(String, T::Enum))).returns(T::Boolean) }
    def valid_tool?(action)
      return false unless action
      action_str = action.respond_to?(:serialize) ? action.serialize : action.to_s
      !!@tools[action_str.downcase]
    end

    sig { params(action: T.nilable(T.any(String, T::Enum)), action_input: T.untyped, iteration: Integer).returns(T.untyped) }
    def execute_tool_with_instrumentation(action, action_input, iteration)
      return "Unknown action: #{action}. Available actions: #{@tools.keys.join(', ')}, finish" unless action

      action_str = action.respond_to?(:serialize) ? action.serialize : action.to_s

      if @tools[action_str.downcase]
        DSPy::Context.with_span(
          operation: 'react.tool_call',
          **DSPy::ObservationType::Tool.langfuse_attributes,
          'dspy.module' => 'ReAct',
          'react.iteration' => iteration,
          'tool.name' => action_str.downcase,
          'tool.input' => action_input
        ) do
          execute_action(action_str, action_input)
        end
      else
        "Unknown action: #{action_str}. Available actions: #{@tools.keys.join(', ')}, finish"
      end
    end

    sig { params(step: Integer, thought: String, action: String, action_input: T.untyped, observation: T.untyped).returns(HistoryEntry) }
    def create_history_entry(step, thought, action, action_input, observation)
      HistoryEntry.new(
        step: step,
        thought: thought,
        action: action,
        action_input: action_input,
        observation: observation
      )
    end

    sig { params(input_struct: T.untyped, history: T::Array[HistoryEntry], observation: T.untyped, available_tools_desc: T::Array[AvailableTool], iteration: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def process_observation_and_decide_next_step(input_struct, history, observation, available_tools_desc, iteration)
      return { should_finish: false } if observation.is_a?(String) && observation.include?("Unknown action")

      observation_result = @observation_processor.forward(
        input_context: DSPy::TypeSerializer.serialize(input_struct).to_json,
        history: serialize_history_for_llm(history),
        observation: serialize_for_llm(observation)
      )

      return { should_finish: false } unless observation_result.next_step == NextStep::Finish

      final_answer = generate_forced_final_answer(
        input_struct, history, available_tools_desc, observation_result, iteration
      )

      { should_finish: true, final_answer: final_answer }
    end

    sig { params(input_struct: T.untyped, history: T::Array[HistoryEntry], available_tools_desc: T::Array[AvailableTool], observation_result: T.untyped, iteration: Integer).returns(T.untyped) }
    def generate_forced_final_answer(input_struct, history, available_tools_desc, observation_result, iteration)
      final_thought = @thought_generator.forward(
        input_context: DSPy::TypeSerializer.serialize(input_struct).to_json,
        history: serialize_history_for_llm(history),
        available_tools: available_tools_desc
      )

      action_str = final_thought.action.respond_to?(:serialize) ? final_thought.action.serialize : final_thought.action.to_s
      if action_str.downcase != FINISH_ACTION
        forced_answer = if observation_result.interpretation && !observation_result.interpretation.empty?
                          observation_result.interpretation
                        else
                          history.last&.observation || "No answer available"
                        end
        handle_finish_action(forced_answer, history.last&.observation, iteration + 1, final_thought.thought, FINISH_ACTION, history)
      else
        handle_finish_action(final_thought.action_input, history.last&.observation, iteration + 1, final_thought.thought, final_thought.action, history)
      end
    end

    sig { params(iteration: Integer, thought: String, action: String, action_input: T.untyped, observation: String, tools_used: T::Array[String]).void }
    def emit_iteration_complete_event(iteration, thought, action, action_input, observation, tools_used)
      DSPy.event('react.iteration_complete', {
        'react.iteration' => iteration,
        'react.thought' => thought,
        'react.action' => action,
        'react.action_input' => action_input,
        'react.observation' => observation,
        'react.tools_used' => tools_used.uniq
      })
    end

    sig { params(iterations_count: Integer, final_answer: T.untyped, tools_used: T::Array[String], history: T::Array[HistoryEntry]).void }
    def handle_max_iterations_if_needed(iterations_count, final_answer, tools_used, history)
      if iterations_count >= @max_iterations && final_answer.nil?
        DSPy.event('react.max_iterations', {
          'react.iteration_count' => iterations_count,
          'react.max_iterations' => @max_iterations,
          'react.tools_used' => tools_used.uniq,
          'react.final_history_length' => history.length
        })
      end
    end

    sig { returns(String) }
    def default_no_answer_message
      "No answer reached within #{@max_iterations} iterations"
    end

    # Checks if a type is String or compatible with String (e.g., T.any(String, ...) or T.nilable(String))
    sig { params(type_object: T.untyped).returns(T::Boolean) }
    def string_compatible_type?(type_object)
      case type_object
      when T::Types::Simple
        type_object.raw_type == String
      when T::Types::Union
        # Check if any of the union types is String
        type_object.types.any? { |t| t.is_a?(T::Types::Simple) && t.raw_type == String }
      else
        false
      end
    end

    # Returns an appropriate default value for a given Sorbet type
    # This is used when max iterations is reached without a successful completion
    sig { params(type_object: T.untyped).returns(T.untyped) }
    def default_value_for_type(type_object)
      # Handle TypedArray (T::Array[...])
      if type_object.is_a?(T::Types::TypedArray)
        return []
      end

      # Handle TypedHash (T::Hash[...])
      if type_object.is_a?(T::Types::TypedHash)
        return {}
      end

      # Handle simple types
      case type_object
      when T::Types::Simple
        raw_type = type_object.raw_type
        case raw_type.to_s
        when 'String' then ''
        when 'Integer' then 0
        when 'Float' then 0.0
        when 'TrueClass', 'FalseClass' then false
        else
          # For T::Struct types, return nil as fallback
          nil
        end
      when T::Types::Union
        # For unions, return nil (assuming it's nilable) or first non-nil default
        nil
      else
        # Default fallback for unknown types
        nil
      end
    end

    # Tool execution method
    sig { params(action: String, action_input: T.untyped).returns(T.untyped) }
    def execute_action(action, action_input)
      tool_name = action.downcase
      tool = @tools[tool_name]
      return "Tool '#{action}' not found. Available tools: #{@tools.keys.join(', ')}" unless tool

      begin
        result = if action_input.nil? ||
                   (action_input.is_a?(String) && action_input.strip.empty?)
          # No input provided
          tool.dynamic_call({})
        else
          # Pass the action_input directly to dynamic_call, which can handle
          # either a Hash or a JSON string
          tool.dynamic_call(action_input)
        end
        result  # Return raw result, preserving type information
      rescue => e
        "Error executing tool '#{action}': #{e.message}"
      end
    end

    sig { params(output: T.untyped).void }
    def validate_output_schema!(output)
      # Validate that output is an instance of the enhanced output struct
      unless output.is_a?(@enhanced_output_struct)
        raise "Output must be an instance of #{@enhanced_output_struct}, got #{output.class}"
      end

      # Validate original signature output fields are present
      @original_signature_class.output_struct_class.props.each do |field_name, _prop|
        unless output.respond_to?(field_name)
          raise "Missing required field: #{field_name}"
        end
      end

      # Validate ReAct-specific fields
      unless output.respond_to?(:history) && output.history.is_a?(Array)
        raise "Missing or invalid history field"
      end

      unless output.respond_to?(:iterations) && output.iterations.is_a?(Integer)
        raise "Missing or invalid iterations field"
      end

      unless output.respond_to?(:tools_used) && output.tools_used.is_a?(Array)
        raise "Missing or invalid tools_used field"
      end
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def generate_example_output
      example = super
      example[:history] = [
        {
          step: 1,
          thought: "I need to think about this question...",
          action: "some_tool",
          action_input: "input for tool",
          observation: "result from tool"
        }
      ]
      example[:iterations] = 1
      example[:tools_used] = ["some_tool"]
      example
    end

    sig { params(action_input: T.untyped, last_observation: T.untyped, step: Integer, thought: String, action: T.any(String, T::Enum), history: T::Array[HistoryEntry]).returns(T.untyped) }
    def handle_finish_action(action_input, last_observation, step, thought, action, history)
      final_answer = action_input

      # If final_answer is empty/nil but we have a last observation, use it
      if (final_answer.nil? || (final_answer.is_a?(String) && final_answer.empty?)) && last_observation
        final_answer = last_observation
      end

      # Convert action enum to string for storage in history
      action_str = action.respond_to?(:serialize) ? action.serialize : action.to_s

      # Always add the finish action to history
      history << HistoryEntry.new(
        step: step,
        thought: thought,
        action: action_str,
        action_input: final_answer,
        observation: nil  # No observation for finish action
      )

      final_answer
    end
  end
end
