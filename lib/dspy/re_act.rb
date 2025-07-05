# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'predict'
require_relative 'signature'
require_relative 'chain_of_thought'
require 'json'
require_relative 'instrumentation'
require_relative 'mixins/struct_builder'
require_relative 'mixins/instrumentation_helpers'

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
  class Thought < DSPy::Signature
    description "Generate a thought about what to do next to answer the question."

    input do
      const :question, String,
        description: "The question to answer"
      const :history, T::Array[T::Hash[Symbol, T.untyped]],
        description: "Previous thoughts and actions, including observations from tools. The agent MUST use information from the history to inform its actions and final answer. Each entry is a hash representing a step in the reasoning process."
      const :available_tools, T::Array[T::Hash[String, T.untyped]],
        description: "Array of available tools with their JSON schemas. The agent MUST choose an action from the tool names in this list or use \"finish\". For each tool, use the name exactly as specified and provide action_input as a JSON object matching the tool's schema."
    end

    output do
      const :thought, String,
        description: "Reasoning about what to do next, considering the history and observations."
      const :action, String,
        description: "The action to take. MUST be one of the tool names listed in `available_tools` input, or the literal string \"finish\" to provide the final answer."
      const :action_input, T.any(String, T::Hash[T.untyped, T.untyped]),
        description: "Input for the chosen action. If action is a tool name, this MUST be a JSON object matching the tool's schema. If action is \"finish\", this field MUST contain the final answer to the original question. This answer MUST be directly taken from the relevant Observation in the history if available. For example, if an observation showed \"Observation: 100.0\", and you are finishing, this field MUST be \"100.0\". Do not leave empty if finishing with an observed answer."
    end
  end

  class NextStep < T::Enum
    enums do
      Continue = new("continue")
      Finish = new("finish")
    end
  end

  # Defines the signature for processing observations and deciding next steps
  class ReActObservation < DSPy::Signature
    description "Process the observation from a tool and decide what to do next."

    input do
      const :question, String,
        description: "The original question"
      const :history, T::Array[T::Hash[Symbol, T.untyped]],
        description: "Previous thoughts, actions, and observations. Each entry is a hash representing a step in the reasoning process."
      const :observation, String,
        description: "The result from the last action"
    end

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
    include Mixins::InstrumentationHelpers

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

      # Create thought generator using Predict to preserve field descriptions
      @thought_generator = T.let(DSPy::Predict.new(Thought), DSPy::Predict)

      # Create observation processor using Predict to preserve field descriptions
      @observation_processor = T.let(DSPy::Predict.new(ReActObservation), DSPy::Predict)

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

        class << self
          attr_reader :input_struct_class, :output_struct_class
        end
      end

      # Call parent constructor with enhanced signature
      super(enhanced_signature)
    end

    sig { params(kwargs: T.untyped).returns(T.untyped).override }
    def forward(**kwargs)
      lm = config.lm || DSPy.config.lm
      available_tools = @tools.keys

      # Instrument the entire ReAct agent lifecycle
      result = instrument_prediction('dspy.react', @original_signature_class, kwargs, {
        max_iterations: @max_iterations,
        available_tools: available_tools
      }) do
        # Validate input and extract question
        input_struct = @original_signature_class.input_struct_class.new(**kwargs)
        question = T.cast(input_struct.serialize.values.first, String)

        # Execute ReAct reasoning loop
        reasoning_result = execute_react_reasoning_loop(question)

        # Create enhanced output with all ReAct data
        create_enhanced_result(kwargs, reasoning_result)
      end

      result
    end

    private

    # Executes the main ReAct reasoning loop
    sig { params(question: String).returns(T::Hash[Symbol, T.untyped]) }
    def execute_react_reasoning_loop(question)
      history = T.let([], T::Array[HistoryEntry])
      available_tools_desc = @tools.map { |name, tool| JSON.parse(tool.schema) }
      final_answer = T.let(nil, T.nilable(String))
      iterations_count = 0
      last_observation = T.let(nil, T.nilable(String))
      tools_used = []

      while should_continue_iteration?(iterations_count, final_answer)
        iterations_count += 1

        iteration_result = execute_single_iteration(
          question, history, available_tools_desc, iterations_count, tools_used, last_observation
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
    sig { params(question: String, history: T::Array[HistoryEntry], available_tools_desc: T::Array[T::Hash[String, T.untyped]], iteration: Integer, tools_used: T::Array[String], last_observation: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
    def execute_single_iteration(question, history, available_tools_desc, iteration, tools_used, last_observation)
      # Instrument each iteration
      Instrumentation.instrument('dspy.react.iteration', {
        iteration: iteration,
        max_iterations: @max_iterations,
        history_length: history.length,
        tools_used_so_far: tools_used.uniq
      }) do
        # Generate thought and action
        thought_obj = @thought_generator.forward(
          question: question,
          history: history.map(&:to_h),
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

        # Track tools used
        tools_used << thought_obj.action.downcase if valid_tool?(thought_obj.action)

        # Add to history
        history << create_history_entry(
          iteration, thought_obj.thought, thought_obj.action,
          thought_obj.action_input, observation
        )

        # Process observation and decide next step
        observation_decision = process_observation_and_decide_next_step(
          question, history, observation, available_tools_desc, iteration
        )

        if observation_decision[:should_finish]
          return { should_finish: true, final_answer: observation_decision[:final_answer] }
        end

        emit_iteration_complete_event(
          iteration, thought_obj.thought, thought_obj.action,
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

      output_data = input_kwargs.merge({
        history: reasoning_result[:history].map(&:to_h),
        iterations: reasoning_result[:iterations],
        tools_used: reasoning_result[:tools_used]
      })
      output_data[output_field_name] = reasoning_result[:final_answer]

      @enhanced_output_struct.new(**output_data)
    end

    # Helper methods for ReAct logic
    sig { params(iterations_count: Integer, final_answer: T.nilable(String)).returns(T::Boolean) }
    def should_continue_iteration?(iterations_count, final_answer)
      final_answer.nil? && (@max_iterations.nil? || iterations_count < @max_iterations)
    end

    sig { params(action: T.nilable(String)).returns(T::Boolean) }
    def finish_action?(action)
      action&.downcase == FINISH_ACTION
    end

    sig { params(action: T.nilable(String)).returns(T::Boolean) }
    def valid_tool?(action)
      !!(action && @tools[action.downcase])
    end

    sig { params(action: T.nilable(String), action_input: T.untyped, iteration: Integer).returns(String) }
    def execute_tool_with_instrumentation(action, action_input, iteration)
      if action && @tools[action.downcase]
        Instrumentation.instrument('dspy.react.tool_call', {
          iteration: iteration,
          tool_name: action.downcase,
          tool_input: action_input
        }) do
          execute_action(action, action_input)
        end
      else
        "Unknown action: #{action}. Available actions: #{@tools.keys.join(', ')}, finish"
      end
    end

    sig { params(step: Integer, thought: String, action: String, action_input: T.untyped, observation: String).returns(HistoryEntry) }
    def create_history_entry(step, thought, action, action_input, observation)
      HistoryEntry.new(
        step: step,
        thought: thought,
        action: action,
        action_input: action_input,
        observation: observation
      )
    end

    sig { params(question: String, history: T::Array[HistoryEntry], observation: String, available_tools_desc: T::Array[T::Hash[String, T.untyped]], iteration: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def process_observation_and_decide_next_step(question, history, observation, available_tools_desc, iteration)
      return { should_finish: false } if observation.include?("Unknown action")

      observation_result = @observation_processor.forward(
        question: question,
        history: history.map(&:to_h),
        observation: observation
      )

      return { should_finish: false } unless observation_result.next_step == NextStep::Finish

      final_answer = generate_forced_final_answer(
        question, history, available_tools_desc, observation_result, iteration
      )

      { should_finish: true, final_answer: final_answer }
    end

    sig { params(question: String, history: T::Array[HistoryEntry], available_tools_desc: T::Array[T::Hash[String, T.untyped]], observation_result: T.untyped, iteration: Integer).returns(String) }
    def generate_forced_final_answer(question, history, available_tools_desc, observation_result, iteration)
      final_thought = @thought_generator.forward(
        question: question,
        history: history.map(&:to_h),
        available_tools: available_tools_desc
      )

      if final_thought.action&.downcase != FINISH_ACTION
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
      Instrumentation.emit('dspy.react.iteration_complete', {
        iteration: iteration,
        thought: thought,
        action: action,
        action_input: action_input,
        observation: observation,
        tools_used: tools_used.uniq
      })
    end

    sig { params(iterations_count: Integer, final_answer: T.nilable(String), tools_used: T::Array[String], history: T::Array[HistoryEntry]).void }
    def handle_max_iterations_if_needed(iterations_count, final_answer, tools_used, history)
      if iterations_count >= @max_iterations && final_answer.nil?
        Instrumentation.emit('dspy.react.max_iterations', {
          iteration_count: iterations_count,
          max_iterations: @max_iterations,
          tools_used: tools_used.uniq,
          final_history_length: history.length
        })
      end
    end

    sig { returns(String) }
    def default_no_answer_message
      "No answer reached within #{@max_iterations} iterations"
    end

    # Tool execution method
    sig { params(action: String, action_input: T.untyped).returns(String) }
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

    sig { params(action_input: T.untyped, last_observation: T.nilable(String), step: Integer, thought: String, action: String, history: T::Array[HistoryEntry]).returns(String) }
    def handle_finish_action(action_input, last_observation, step, thought, action, history)
      final_answer = action_input.to_s

      # If final_answer is empty but we have a last observation, use it
      if (final_answer.nil? || final_answer.empty?) && last_observation
        final_answer = last_observation
      end

      # Always add the finish action to history
      history << HistoryEntry.new(
        step: step,
        thought: thought,
        action: action,
        action_input: final_answer,
        observation: nil  # No observation for finish action
      )

      final_answer
    end
  end
end
