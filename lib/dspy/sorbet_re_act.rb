# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'sorbet_predict'
require_relative 'sorbet_signature'
require_relative 'sorbet_chain_of_thought'

module DSPy
  # Define a simple struct for history entries with proper type annotations
  class HistoryEntry < T::Struct
    const :step, Integer
    prop :thought, T.nilable(String)
    prop :action, T.nilable(String)
    prop :action_input, T.nilable(T.any(String, Numeric, T::Hash[T.untyped, T.untyped], T::Array[T.untyped]))
    prop :observation, T.nilable(String)

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
  # Defines the signature for ReAct reasoning using Sorbet signatures
  class SorbetThought < DSPy::SorbetSignature
    description "Generate a thought about what to do next to answer the question."

    input do
      const :question, String,
        description: "The question to answer"
      const :history, T::Array[HistoryEntry],
        description: "Previous thoughts and actions, including observations from tools. The agent MUST use information from the history to inform its actions and final answer. Each entry is a hash representing a step in the reasoning process."
      const :available_tools, String,
        description: "List of available tools and their descriptions. The agent MUST choose an action from this list or use \"finish\"."
    end

    output do
      const :thought, String,
        description: "Reasoning about what to do next, considering the history and observations."
      const :action, String,
        description: "The action to take. MUST be one of the tool names listed in `available_tools` input, or the literal string \"finish\" to provide the final answer."
      const :action_input, String,
        description: "Input for the chosen action. If action is \"finish\", this field MUST contain the final answer to the original question. This answer MUST be directly taken from the relevant Observation in the history if available. For example, if an observation showed \"Observation: 100.0\", and you are finishing, this field MUST be \"100.0\". Do not leave empty if finishing with an observed answer."
    end
  end

  # ReAct Agent using Sorbet signatures
  class SorbetReAct < SorbetPredict
    extend T::Sig

    sig { returns(T.class_of(DSPy::SorbetSignature)) }
    attr_reader :original_signature_class

    sig { returns(T.class_of(T::Struct)) }
    attr_reader :enhanced_output_struct

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :tools

    sig { returns(Integer) }
    attr_reader :max_iterations


    sig { params(signature_class: T.class_of(DSPy::SorbetSignature), tools: T::Array[T.untyped], max_iterations: Integer).void }
    def initialize(signature_class, tools: [], max_iterations: 5)
      @original_signature_class = signature_class
      @tools = T.let({}, T::Hash[String, T.untyped])
      tools.each { |tool| @tools[tool.name.downcase] = tool }
      @max_iterations = max_iterations

      # Create thought generator using SorbetPredict to preserve field descriptions
      @thought_generator = T.let(DSPy::SorbetPredict.new(SorbetThought), DSPy::SorbetPredict)

      # Create enhanced output struct with ReAct fields
      @enhanced_output_struct = create_enhanced_output_struct(signature_class)
      enhanced_output_struct = @enhanced_output_struct

      # Create enhanced signature class
      enhanced_signature = Class.new(DSPy::SorbetSignature) do
        # Set the description
        description signature_class.description

        # Use the same input struct
        @input_struct_class = signature_class.input_struct_class

        # Use the enhanced output struct with ReAct fields
        @output_struct_class = enhanced_output_struct

        class << self
          attr_reader :input_struct_class, :output_struct_class
        end
      end

      # Call parent constructor with enhanced signature
      super(enhanced_signature)
    end

    sig { params(kwargs: T.untyped).returns(T.untyped) }
    def forward(**kwargs)
      # Validate input using Sorbet struct validation
      input_struct = @original_signature_class.input_struct_class.new(**kwargs)

      # Get the question (assume first field is the question for now)
      question = T.cast(input_struct.serialize.values.first, String)

      history = T.let([], T::Array[HistoryEntry])
      available_tools_desc = @tools.map { |name, tool| "- #{name}: #{tool.description}" }.join("\n")

      final_answer = T.let(nil, T.nilable(String))
      iterations_count = 0

      @max_iterations.times do |i|
        iterations_count = i + 1
        current_step_history = T.let({ step: iterations_count }, T::Hash[Symbol, T.untyped])

        # Generate thought and action
        thought_result = @thought_generator.forward(
          question: question,
          history: history,
          available_tools: available_tools_desc
        )

        thought = thought_result.thought
        action = thought_result.action
        current_action_input = thought_result.action_input

        current_step_history[:thought] = thought
        current_step_history[:action] = action

        if action.downcase == "finish"
          # If LM says 'finish' but gives empty input, try to use last observation
          if current_action_input.nil? || current_action_input.strip.empty?
            # Try to find the last observation in history
            last_entry_with_observation = history.reverse.find { |entry| entry.observation && !entry.observation.strip.empty? }

            if last_entry_with_observation
              last_observation_value = last_entry_with_observation.observation.strip
              current_action_input = last_observation_value
            end
          end
          final_answer = current_action_input
        end

        # Add thought to history
        current_step_history[:action_input] = current_action_input

        # Check if we should finish
        if action.downcase == "finish"
          history << HistoryEntry.new(**current_step_history)
          break
        end

        # Execute the action
        observation_text = execute_action(action, current_action_input)
        current_step_history[:observation] = observation_text
        history << HistoryEntry.new(**current_step_history)
      end

      # If we reached max iterations without finishing, try to use the last observation as the answer
      if final_answer.nil? && !history.empty?
        last_entry_with_observation = history.reverse.find { |entry| entry.observation && !entry.observation.strip.empty? }
        if last_entry_with_observation
          final_answer = last_entry_with_observation.observation.strip
        else
          final_answer = "Unable to determine answer within #{@max_iterations} iterations"
        end
      end

      # Create result with enhanced output struct
      output_data = {}

      # Add the final answer to the output data using the first output field name
      output_field_name = @original_signature_class.output_struct_class.props.keys.first
      output_data[output_field_name] = final_answer

      # Add ReAct-specific fields
      output_data[:history] = history.map(&:to_h)
      output_data[:iterations] = iterations_count

      result = @enhanced_output_struct.new(**output_data)
      validate_output_schema!(result)
      result
    end

    private

    sig { params(signature_class: T.class_of(DSPy::SorbetSignature)).returns(T.class_of(T::Struct)) }
    def create_enhanced_output_struct(signature_class)
      # Get original output props
      original_props = signature_class.output_struct_class.props

      # Create new struct class with ReAct fields added
      Class.new(T::Struct) do
        # Add all original fields
        original_props.each do |name, prop|
          # Extract the type and other options
          type = prop[:type]
          options = prop.except(:type, :type_object, :accessor_key, :sensitivity, :redaction)

          # Handle default values
          if options[:default]
            const name, type, default: options[:default]
          elsif options[:factory]
            const name, type, factory: options[:factory]
          else
            const name, type
          end
        end

        # Add ReAct-specific fields
        const :history, T::Array[T::Hash[Symbol, T.untyped]]
        const :iterations, Integer
      end
    end

    sig { params(action: String, action_input: String).returns(String) }
    def execute_action(action, action_input)
      tool = @tools[action.downcase]
      return "Tool '#{action}' not found. Available tools: #{@tools.keys.join(', ')}" unless tool

      begin
        result = if action_input.nil? || action_input.strip.empty?
          tool.call
        else
          tool.call(action_input)
        end
        result.to_s
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
      example
    end
  end
end
