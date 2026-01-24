# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'predict'
require_relative 'signature'
require_relative 'chain_of_thought'
require 'json'
require_relative 'mixins/struct_builder'

module DSPy
  # Type alias for tool input parameters - provides semantic meaning in schemas
  ToolInput = T.type_alias { T.nilable(T::Hash[String, T.untyped]) }

  # Define a simple struct for history entries with proper type annotations
  class HistoryEntry < T::Struct
    const :step, Integer
    prop :thought, T.nilable(String)
    prop :action, T.nilable(String)
    prop :tool_input, ToolInput
    prop :observation, T.untyped

    # Custom serialization to ensure compatibility with the rest of the code
    # Note: We don't use .compact here to ensure tool_input is always present as a key,
    # even when nil, for consistent history entry structure
    def to_h
      {
        step: step,
        thought: thought,
        action: action,
        tool_input: tool_input,
        observation: observation
      }
    end
  end

  class NextStep < T::Enum
    enums do
      Continue = new("continue")
      Finish = new("finish")
    end
  end

  # ReAct Agent using Sorbet signatures
  class ReAct < Predict
    extend T::Sig
    include Mixins::StructBuilder

    # Custom error classes
    class MaxIterationsError < StandardError; end
    class InvalidActionError < StandardError; end
    class TypeMismatchError < StandardError; end

    # AvailableTool struct for better type safety in ReAct agents
    # Schema is stored as a pre-serialized string (JSON or BAML) to avoid
    # T.untyped issues during schema format conversion
    class AvailableTool < T::Struct
      const :name, String
      const :description, String
      const :schema, String
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
      @data_format = T.let(DSPy.config.lm&.data_format || :json, Symbol)

      # Create dynamic ActionEnum class with tool names + finish
      @action_enum_class = create_action_enum_class

      # Create dynamic signature classes that include the original input fields
      thought_signature = create_thought_signature(signature_class, @data_format)
      observation_signature = create_observation_signature(signature_class, @data_format)

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

    sig { override.returns(T::Array[[String, DSPy::Module]]) }
    def named_predictors
      pairs = T.let([], T::Array[[String, DSPy::Module]])
      pairs << ["thought_generator", @thought_generator]
      pairs << ["observation_processor", @observation_processor]
      pairs
    end

    sig { override.returns(T::Array[DSPy::Module]) }
    def predictors
      named_predictors.map { |(_, predictor)| predictor }
    end

    sig { returns(DSPy::Prompt) }
    def prompt
      @thought_generator.prompt
    end

    sig { params(instruction: String).returns(ReAct).override }
    def with_instruction(instruction)
      clone = self.class.new(@original_signature_class, tools: @tools.values, max_iterations: @max_iterations)
      thought_generator = clone.instance_variable_get(:@thought_generator)
      clone.instance_variable_set(:@thought_generator, thought_generator.with_instruction(instruction))
      clone
    end

    sig { params(examples: T::Array[DSPy::FewShotExample]).returns(ReAct).override }
    def with_examples(examples)
      clone = self.class.new(@original_signature_class, tools: @tools.values, max_iterations: @max_iterations)
      thought_generator = clone.instance_variable_get(:@thought_generator)
      clone.instance_variable_set(:@thought_generator, thought_generator.with_examples(examples))
      clone
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
    sig { params(value: T.untyped).returns(T.untyped) }
    def serialize_for_llm(value)
      return value if value.nil?
      return value if value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)

      # For structured data, serialize to JSON-compatible format
      TypeSerializer.serialize(value)
    end

    # Serialize history for LLM consumption
    sig { params(history: T::Array[HistoryEntry]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialize_history_for_llm(history)
      history.map do |entry|
        {
          step: entry.step,
          thought: entry.thought,
          action: entry.action,
          tool_input: serialize_for_llm(entry.tool_input),
          observation: serialize_for_llm(entry.observation)
        }.compact
      end
    end

    sig { params(input_struct: T.untyped).returns(T.untyped) }
    def format_input_context(input_struct)
      return input_struct if toon_data_format?

      DSPy::TypeSerializer.serialize(input_struct).to_json
    end

    sig { params(history: T::Array[HistoryEntry]).returns(T.untyped) }
    def format_history(history)
      toon_data_format? ? history : serialize_history_for_llm(history)
    end

    sig { params(observation: T.untyped).returns(T.untyped) }
    def format_observation(observation)
      toon_data_format? ? observation : serialize_for_llm(observation)
    end

    sig { returns(T::Boolean) }
    def toon_data_format?
      @data_format == :toon
    end

    # Creates a dynamic ActionEnum class with tool names and "finish"
    sig { returns(T.class_of(T::Enum)) }
    def create_action_enum_class
      tool_names = @tools.keys
      all_actions = tool_names + [FINISH_ACTION]

      # Create a dynamic enum class using proper T::Enum pattern
      enum_class = Class.new(T::Enum)

      # Give the anonymous class a proper name for BAML schema rendering
      # This overrides the default behavior that returns #<Class:0x...>
      enum_class.define_singleton_method(:name) { 'ActionEnum' }

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
    sig { params(signature_class: T.class_of(DSPy::Signature), data_format: Symbol).returns(T.class_of(DSPy::Signature)) }
    def create_thought_signature(signature_class, data_format)
      action_enum_class = @action_enum_class
      input_context_type = if data_format == :toon
        signature_class.input_struct_class || String
      else
        String
      end

      # Get the output field type for the final_answer field
      output_field_name = signature_class.output_struct_class.props.keys.first
      output_field_type = signature_class.output_struct_class.props[output_field_name][:type_object]

      # Create new class that inherits from DSPy::Signature
      Class.new(DSPy::Signature) do
        # Set description
        description "Generate a thought about what to do next to process the given inputs."

        # Define input fields
        input do
          const :input_context, input_context_type,
            description: data_format == :toon ? "All original input fields with their typed values" : "Serialized representation of all input fields"
          const :history, T::Array[HistoryEntry],
            description: "Previous thoughts and actions, including observations from tools."
          const :available_tools, T::Array[AvailableTool],
            description: "Array of available tools with their JSON schemas."
        end

        # Define output fields with separate tool_input and final_answer
        output do
          const :thought, String,
            description: "Reasoning about what to do next, considering the history and observations."
          const :action, action_enum_class,
            description: "The action to take. MUST be one of the tool names listed in `available_tools` input, or the literal string \"finish\" to provide the final answer."
          const :tool_input, ToolInput,
            description: "Input for the chosen tool action. Required when action is a tool name. MUST be a JSON object matching the tool's parameter schema. Set to null when action is \"finish\"."
          const :final_answer, T.nilable(output_field_type),
            description: "The final answer to return. Required when action is \"finish\". Must match the expected output type. Set to null when action is a tool name."
        end
      end
    end

    # Creates a dynamic observation signature that includes the original input fields
    sig { params(signature_class: T.class_of(DSPy::Signature), data_format: Symbol).returns(T.class_of(DSPy::Signature)) }
    def create_observation_signature(signature_class, data_format)
      input_context_type = if data_format == :toon
        signature_class.input_struct_class || String
      else
        String
      end
      # Create new class that inherits from DSPy::Signature
      Class.new(DSPy::Signature) do
        # Set description
        description "Process the observation from a tool and decide what to do next."

        # Define input fields
        input do
          const :input_context, input_context_type,
            description: data_format == :toon ? "All original input fields with their typed values" : "Serialized representation of all input fields"
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
        AvailableTool.new(
          name: name,
          description: tool.description,
          schema: tool.schema
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
        final_answer: final_answer
      }
    end

    # Executes a single iteration of the ReAct loop
    sig { params(input_struct: T.untyped, history: T::Array[HistoryEntry], available_tools_desc: T::Array[AvailableTool], iteration: Integer, tools_used: T::Array[String], last_observation: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
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
          input_context: format_input_context(input_struct),
          history: format_history(history),
          available_tools: available_tools_desc
        )

        # Process thought result
        if finish_action?(thought_obj.action)
          final_answer = handle_finish_action(
            thought_obj.final_answer, last_observation, iteration,
            thought_obj.thought, thought_obj.action, history
          )
          return { should_finish: true, final_answer: final_answer }
        end

        # Execute tool action
        observation = execute_tool_with_instrumentation(
          thought_obj.action, thought_obj.tool_input, iteration
        )

        # Convert action enum to string for processing and storage
        action_str = thought_obj.action.respond_to?(:serialize) ? thought_obj.action.serialize : thought_obj.action.to_s

        # Track tools used
        tools_used << action_str.downcase if valid_tool?(thought_obj.action)

        # Add to history
        history << create_history_entry(
          iteration, thought_obj.thought, action_str,
          thought_obj.tool_input, observation
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
          thought_obj.tool_input, observation, tools_used
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

      # If final_answer is nil, max iterations was reached without completion
      if final_answer.nil?
        iterations = reasoning_result[:iterations]
        tools_used = reasoning_result[:tools_used]
        raise MaxIterationsError, "Agent reached maximum iterations (#{iterations}) without producing a final answer. Tools used: #{tools_used.join(', ')}"
      end

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

    # Find the most recent non-nil tool observation in history
    sig { params(history: T::Array[HistoryEntry]).returns(T.untyped) }
    def find_last_tool_observation(history)
      history.reverse.find { |entry| !entry.observation.nil? }&.observation
    end

    # Deserialize final answer to match expected output type
    # Routes to appropriate deserialization based on type classification
    sig { params(final_answer: T.untyped, output_field_type: T.untyped, history: T::Array[HistoryEntry]).returns(T.untyped) }
    def deserialize_final_answer(final_answer, output_field_type, history)
      if scalar_type?(output_field_type)
        deserialize_scalar(final_answer, output_field_type)
      elsif structured_type?(output_field_type)
        deserialize_structured(final_answer, output_field_type, history)
      else
        # Fallback for unknown types
        return final_answer if type_matches?(final_answer, output_field_type)
        convert_to_expected_type(final_answer, output_field_type)
      end
    end

    # Deserialize scalar types (String, Integer, Boolean, etc.)
    # Scalars: Trust LLM synthesis, minimal conversion
    sig { params(final_answer: T.untyped, output_field_type: T.untyped).returns(T.untyped) }
    def deserialize_scalar(final_answer, output_field_type)
      # If already matches, return as-is (even if empty string for String types)
      return final_answer if type_matches?(final_answer, output_field_type)

      # Try basic conversion
      converted = convert_to_expected_type(final_answer, output_field_type)
      return converted if type_matches?(converted, output_field_type)

      # Type mismatch - raise error with helpful message
      expected_type = type_name(output_field_type)
      actual_type = final_answer.class.name
      raise TypeMismatchError, "Cannot convert final answer from #{actual_type} to #{expected_type}. Value: #{final_answer.inspect}"
    end

    # Deserialize structured types (arrays, hashes, structs)
    # Structured: Prefer tool observation to preserve type information
    sig { params(final_answer: T.untyped, output_field_type: T.untyped, history: T::Array[HistoryEntry]).returns(T.untyped) }
    def deserialize_structured(final_answer, output_field_type, history)
      # First, try to use the last tool observation if it matches the expected type
      # This preserves type information that would be lost in LLM synthesis
      last_tool_observation = find_last_tool_observation(history)
      if last_tool_observation && type_matches?(last_tool_observation, output_field_type)
        return last_tool_observation
      end

      # If final_answer already matches, use it
      return final_answer if type_matches?(final_answer, output_field_type)

      # Try to convert based on expected type
      converted = convert_to_expected_type(final_answer, output_field_type)
      return converted if type_matches?(converted, output_field_type)

      # Type mismatch - raise error with helpful message
      expected_type = type_name(output_field_type)
      actual_type = final_answer.class.name
      raise TypeMismatchError, "Cannot convert final answer from #{actual_type} to #{expected_type}. Value: #{final_answer.inspect}"
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

    sig { params(action: T.nilable(T.any(String, T::Enum)), tool_input: ToolInput, iteration: Integer).returns(T.untyped) }
    def execute_tool_with_instrumentation(action, tool_input, iteration)
      raise InvalidActionError, "No action provided" unless action

      action_str = action.respond_to?(:serialize) ? action.serialize : action.to_s

      unless @tools[action_str.downcase]
        available = @tools.keys.join(', ')
        raise InvalidActionError, "Unknown action: #{action_str}. Available actions: #{available}, finish"
      end

      DSPy::Context.with_span(
        operation: 'react.tool_call',
        **DSPy::ObservationType::Tool.langfuse_attributes,
        'dspy.module' => 'ReAct',
        'react.iteration' => iteration,
        'tool.name' => action_str.downcase,
        'tool.input' => tool_input
      ) do
        execute_action(action_str, tool_input)
      end
    end

    sig { params(step: Integer, thought: String, action: String, tool_input: ToolInput, observation: T.untyped).returns(HistoryEntry) }
    def create_history_entry(step, thought, action, tool_input, observation)
      HistoryEntry.new(
        step: step,
        thought: thought,
        action: action,
        tool_input: tool_input,
        observation: observation
      )
    end

    sig { params(input_struct: T.untyped, history: T::Array[HistoryEntry], observation: T.untyped, available_tools_desc: T::Array[AvailableTool], iteration: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def process_observation_and_decide_next_step(input_struct, history, observation, available_tools_desc, iteration)
      observation_result = @observation_processor.forward(
        input_context: format_input_context(input_struct),
        history: format_history(history),
        observation: format_observation(observation)
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
        input_context: format_input_context(input_struct),
        history: format_history(history),
        available_tools: available_tools_desc
      )

      action_str = final_thought.action.respond_to?(:serialize) ? final_thought.action.serialize : final_thought.action.to_s
      if action_str.downcase != FINISH_ACTION
        # Use interpretation if available, otherwise use last observation
        forced_answer = if observation_result.interpretation && !observation_result.interpretation.empty?
                          observation_result.interpretation
                        elsif history.last&.observation
                          history.last.observation
                        else
                          raise MaxIterationsError, "Observation processor indicated finish but no answer is available"
                        end
        handle_finish_action(forced_answer, history.last&.observation, iteration + 1, final_thought.thought, FINISH_ACTION, history)
      else
        handle_finish_action(final_thought.final_answer, history.last&.observation, iteration + 1, final_thought.thought, final_thought.action, history)
      end
    end

    sig { params(iteration: Integer, thought: String, action: String, tool_input: ToolInput, observation: T.untyped, tools_used: T::Array[String]).void }
    def emit_iteration_complete_event(iteration, thought, action, tool_input, observation, tools_used)
      DSPy.event('react.iteration_complete', {
        'react.iteration' => iteration,
        'react.thought' => thought,
        'react.action' => action,
        'react.tool_input' => tool_input,
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

    # Tool execution method
    sig { params(action: String, tool_input: ToolInput).returns(T.untyped) }
    def execute_action(action, tool_input)
      tool_name = action.downcase
      tool = @tools[tool_name]

      # This should not happen since we check in execute_tool_with_instrumentation
      raise InvalidActionError, "Tool '#{action}' not found" unless tool

      # Execute tool - let errors propagate
      if tool_input.nil? || tool_input.empty?
        tool.dynamic_call({})
      else
        tool.dynamic_call(tool_input)
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
          tool_input: { "param" => "value" },
          observation: "result from tool"
        }
      ]
      example[:iterations] = 1
      example[:tools_used] = ["some_tool"]
      example
    end

    sig { params(final_answer_value: T.untyped, last_observation: T.untyped, step: Integer, thought: String, action: T.any(String, T::Enum), history: T::Array[HistoryEntry]).returns(T.untyped) }
    def handle_finish_action(final_answer_value, last_observation, step, thought, action, history)
      final_answer = final_answer_value

      # If final_answer is empty/nil but we have a last observation, use it
      if (final_answer.nil? || (final_answer.is_a?(String) && final_answer.empty?)) && last_observation
        final_answer = last_observation
      end

      # Convert action enum to string for storage in history
      action_str = action.respond_to?(:serialize) ? action.serialize : action.to_s

      # Always add the finish action to history (tool_input is nil for finish actions)
      history << HistoryEntry.new(
        step: step,
        thought: thought,
        action: action_str,
        tool_input: nil,
        observation: nil  # No observation for finish action
      )

      final_answer
    end
  end
end
