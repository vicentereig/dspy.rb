# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'predict'
require_relative 'signature'
require_relative 'chain_of_thought'
require 'json'
require_relative 'instrumentation'

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
      const :history, T::Array[HistoryEntry],
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
      const :history, T::Array[HistoryEntry],
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

    FINISH_ACTION = "finish"
    sig { returns(T.class_of(DSPy::Signature)) }
    attr_reader :original_signature_class

    sig { returns(T.class_of(T::Struct)) }
    attr_reader :enhanced_output_struct

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :tools

    sig { returns(Integer) }
    attr_reader :max_iterations


    sig { params(signature_class: T.class_of(DSPy::Signature), tools: T::Array[T.untyped], max_iterations: Integer).void }
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
      # Prepare instrumentation payload
      input_fields = kwargs.keys.map(&:to_s)
      available_tools = @tools.keys

      # Instrument the entire ReAct agent lifecycle
      result = Instrumentation.instrument('dspy.react', {
        signature_class: @original_signature_class.name,
        model: lm.model,
        provider: lm.provider,
        input_fields: input_fields,
        max_iterations: @max_iterations,
        available_tools: available_tools
      }) do
        # Validate input using Sorbet struct validation
        input_struct = @original_signature_class.input_struct_class.new(**kwargs)

        # Get the question (assume first field is the question for now)
        question = T.cast(input_struct.serialize.values.first, String)

        history = T.let([], T::Array[HistoryEntry])
        available_tools_desc = @tools.map { |name, tool| JSON.parse(tool.schema) }

        final_answer = T.let(nil, T.nilable(String))
        iterations_count = 0
        last_observation = T.let(nil, T.nilable(String))
        tools_used = []

        while @max_iterations.nil? || iterations_count < @max_iterations
          iterations_count += 1

          # Instrument each iteration
          iteration_result = Instrumentation.instrument('dspy.react.iteration', {
            iteration: iterations_count,
            max_iterations: @max_iterations,
            history_length: history.length,
            tools_used_so_far: tools_used.uniq
          }) do
            # Get next thought from LM
            thought_obj = @thought_generator.forward(
              question: question,
              history: history,
              available_tools: available_tools_desc
            )
            step = iterations_count
            thought = thought_obj.thought
            action = thought_obj.action
            action_input = thought_obj.action_input

            DSPy.logger.info("#{step}. Thought: #{thought}")
            DSPy.logger.info("#{step}. Action: #{action}")
            DSPy.logger.info("#{step}. Action Input: #{action_input}")

            # Handle finish action
            if action&.downcase == 'finish'
              final_answer = handle_finish_action(action_input, last_observation, step, thought, action, history)
              break
            end

            # Execute action and instrument tool calls
            observation = if action && @tools[action.downcase]
                            tool = @tools[action.downcase]
                            tools_used << action.downcase

                            # Instrument tool call
                            Instrumentation.instrument('dspy.react.tool_call', {
                              iteration: iterations_count,
                              tool_name: action.downcase,
                              tool_input: action_input,
                              available_tools: available_tools
                            }) do
                              execute_action(action, action_input)
                            end
                          else
                            "Unknown action: #{action}. Available actions: #{@tools.keys.join(', ')}, finish"
                          end

            DSPy.logger.info("#{step}. Observation: #{observation}")
            last_observation = observation

            # Add to history
            history << HistoryEntry.new(
              step: step,
              thought: thought,
              action: action,
              action_input: action_input,
              observation: observation
            )

            # Process observation to decide next step
            if observation && !observation.include?("Unknown action")
              observation_result = @observation_processor.forward(
                question: question,
                history: history,
                observation: observation
              )

              DSPy.logger.info("#{step}. Observation Analysis: #{observation_result.interpretation}")
              DSPy.logger.info("#{step}. Next Step: #{observation_result.next_step}")

              # If observation processor suggests finishing, generate final thought
              if observation_result.next_step == NextStep::Finish
                final_thought = @thought_generator.forward(
                  question: question,
                  history: history,
                  available_tools: available_tools_desc
                )

                # Force finish action if observation processor suggests it
                if final_thought.action&.downcase != 'finish'
                  DSPy.logger.info("#{step}. Overriding action to 'finish' based on observation analysis")
                  forced_answer = if observation_result.interpretation && !observation_result.interpretation.empty?
                                    observation_result.interpretation
                                  else
                                    observation
                                  end
                  final_answer = handle_finish_action(forced_answer, last_observation, step + 1, final_thought.thought, 'finish', history)
                else
                  final_answer = handle_finish_action(final_thought.action_input, last_observation, step + 1, final_thought.thought, final_thought.action, history)
                end
                break
              end
            end

            # Emit iteration complete event
            Instrumentation.emit('dspy.react.iteration_complete', {
              iteration: iterations_count,
              thought: thought,
              action: action,
              action_input: action_input,
              observation: observation,
              tools_used: tools_used.uniq
            })
          end

          # Check if max iterations reached
          if iterations_count >= @max_iterations && final_answer.nil?
            Instrumentation.emit('dspy.react.max_iterations', {
              iteration_count: iterations_count,
              max_iterations: @max_iterations,
              tools_used: tools_used.uniq,
              final_history_length: history.length
            })
          end
        end

        # Create enhanced output with all ReAct data
        output_field_name = @original_signature_class.output_struct_class.props.keys.first
        output_data = kwargs.merge({
          history: history.map(&:to_h),
          iterations: iterations_count,
          tools_used: tools_used.uniq
        })
        output_data[output_field_name] = final_answer || "No answer reached within #{@max_iterations} iterations"
        enhanced_output = @enhanced_output_struct.new(**output_data)

        enhanced_output
      end
      
      result
    end

    private

    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(T::Struct)) }
    def create_enhanced_output_struct(signature_class)
      # Get original input and output props
      input_props = signature_class.input_struct_class.props
      output_props = signature_class.output_struct_class.props

      # Create new struct class with input, output, and ReAct fields
      Class.new(T::Struct) do
        # Add all input fields
        input_props.each do |name, prop|
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

        # Add all output fields
        output_props.each do |name, prop|
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
        prop :history, T::Array[T::Hash[Symbol, T.untyped]]
        prop :iterations, Integer
        prop :tools_used, T::Array[String]
      end
    end

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
