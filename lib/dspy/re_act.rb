module DSPy
  # Define the signature for ReAct reasoning
  class ReActThought < DSPy::Signature
    description "Generate a thought about what to do next to answer the question."

    input do
      required(:question).value(:string).meta(description: 'The question to answer')
      required(:history).value(:string).meta(description: 'Previous thoughts and actions')
      required(:available_tools).value(:string).meta(description: 'List of available tools and their descriptions')
    end

    output do
      required(:thought).value(:string).meta(description: 'Reasoning about what to do next')
      required(:action).value(:string).meta(description: 'The action to take: either a tool name or "finish"')
      required(:action_input).value(:string).meta(description: 'Input for the action. If action is "finish", this MUST be the final answer to the original question.')
    end
  end

  # Define the signature for observing tool results
  class ReActObservation < DSPy::Signature
    description "Process the observation from a tool and decide what to do next."

    input do
      required(:question).value(:string).meta(description: 'The original question')
      required(:history).value(:string).meta(description: 'Previous thoughts, actions, and observations')
      required(:observation).value(:string).meta(description: 'The result from the last action')
    end

    output do
      required(:interpretation).value(:string).meta(description: 'Interpretation of the observation')
      required(:next_step).value(:string).meta(description: 'What to do next: "continue" or "finish"')
    end
  end

  # ReAct Agent Module
  class ReAct < DSPy::Module
    attr_reader :signature_class, :tools, :max_iterations

    def initialize(signature_class, tools: [], max_iterations: 5)
      super()
      @signature_class = signature_class
      @thought_generator = DSPy::ChainOfThought.new(ReActThought)
      @observation_processor = DSPy::Predict.new(ReActObservation)
      @tools = tools.map { |tool| [tool.name.downcase, tool] }.to_h # Ensure tool names are stored lowercased for lookup
      @max_iterations = max_iterations
    end

    def forward(**input_values)
      # Validate input against the signature's input schema
      input_validation_result = @signature_class.input_schema.call(input_values)
      unless input_validation_result.success?
        raise DSPy::PredictionInvalidError.new(input_validation_result.errors)
      end

      # Assume the first input field is the primary question for the ReAct loop
      # This is a convention; a more robust solution might involve explicit mapping
      # or requiring a specific field name like 'question'.
      question_field_name = @signature_class.input_schema.key_map.first.name.to_sym
      question = input_values[question_field_name]

      history = ""
      available_tools_desc = @tools.map { |name, tool| "- #{name}: #{tool.description}" }.join("\n")

      final_answer = nil
      iterations_count = 0

      @max_iterations.times do |i|
        iterations_count = i + 1
        # Generate thought and action
        thought_result = @thought_generator.call(
          question: question,
          history: history,
          available_tools: available_tools_desc
        )

        thought = thought_result.thought
        action = thought_result.action
        action_input = thought_result.action_input

        # Add thought to history
        history += "\nThought #{i + 1}: #{thought}\n"
        history += "Action: #{action}\n"
        history += "Action Input: #{action_input}\n"

        # Check if we should finish
        if action.downcase == "finish"
          DSPy.logger.info(module: "ReAct", status: "Finishing directly after thought", action: action, action_input: action_input, question: question)
          final_answer = action_input
          break
        end

        # Execute the action
        observation = execute_action(action, action_input)
        history += "Observation: #{observation}\n"

        # Process the observation
        obs_result = @observation_processor.call(
          question: question,
          history: history,
          observation: observation
        )

        if obs_result.next_step.downcase == "finish"
          DSPy.logger.info(module: "ReAct", status: "Observation processor suggests finish. Generating final thought.", question: question, history_before_final_thought: history)
          # Generate final thought/answer if observation processor decides to finish
          final_thought_result = @thought_generator.call(
            question: question,
            history: history, # history now includes the last observation
            available_tools: available_tools_desc
          )
          DSPy.logger.info(module: "ReAct", status: "Finishing after observation and final thought", final_action: final_thought_result.action, final_action_input: final_thought_result.action_input, question: question)
          # Ensure this final thought is geared towards providing the answer
          # The prompt for ReActThought might need adjustment if it's not always producing a final answer in action_input
          # when action is 'finish'. For now, we assume action_input is the answer.
          final_answer = final_thought_result.action_input
          break
        end
      end

      final_answer ||= "Unable to find answer within #{@max_iterations} iterations"
      DSPy.logger.info(module: "ReAct", status: "Final answer determined", final_answer: final_answer, question: question) if final_answer.empty? || final_answer == "Unable to find answer within #{@max_iterations} iterations"

      # Prepare output based on signature_class.output_schema
      output_data = {}
      # Assuming the primary output field is named 'answer' or is the first one.
      # A more robust way would be to iterate through output_schema fields.
      output_field_name = @signature_class.output_schema.key_map.first.name.to_sym
      output_data[output_field_name] = final_answer

      # Include other potential fields if defined in the output schema and available
      # For example, if :history or :iterations are in output_schema
      if @signature_class.output_schema.key_map.any? { |k| k.name.to_sym == :history }
        output_data[:history] = history
      end
      if @signature_class.output_schema.key_map.any? { |k| k.name.to_sym == :iterations }
        output_data[:iterations] = iterations_count
      end

      # Validate and create PORO for the output
      output_validation_result = @signature_class.output_schema.call(output_data)
      unless output_validation_result.success?
        # This case should ideally be handled carefully, perhaps by logging
        # or attempting to coerce, as the agent itself is producing this data.
        # For now, we'll raise if the self-generated output doesn't match its own schema.
        raise DSPy::PredictionInvalidError.new(output_validation_result.errors)
      end

      poro_class = Data.define(*output_validation_result.to_h.keys)
      poro_class.new(**output_validation_result.to_h)
    end

    private

    def execute_action(action, action_input)
      tool = @tools[action.downcase] # Lookup with downcased action name

      if tool.nil?
        return "Error: Unknown tool '#{action}'. Available tools: #{@tools.keys.join(', ')}"
      end

      begin
        tool.call(action_input)
      rescue => e
        "Error executing #{action}: #{e.message}"
      end
    end
  end
end
