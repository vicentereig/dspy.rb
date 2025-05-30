module DSPy
  # class React < DSPy::Module
  #   def initialize(signature_class)
  #     react_schema = Dry::Schema.JSON do
  #       required(:trajectory).value(:array).each do
  #         required(:string)
  #       end.meta(description: 'train of thought during reasoning')
  #     end
  #
  #     @react_input_schema = signature_class.input_schema
  #     @react_output_schema = signature_class.output_schema = Dry::Schema.JSON(parent:
  #                                                         [
  #                                                           signature_class.output_schema,
  #                                                           react_schema
  #                                                         ])
  #   end
  #
  #   def forward(**input_values)
  #
  #   end
  # end

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
      required(:action_input).value(:string).meta(description: 'Input for the action, or final answer if action is "finish"')
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
  class ReActAgent < DSPy::Module
    attr_reader :tools, :max_iterations

    def initialize(tools: [], max_iterations: 5)
      super()
      @thought_generator = DSPy::ChainOfThought.new(ReActThought)
      @observation_processor = DSPy::Predict.new(ReActObservation)
      @tools = tools.map { |tool| [tool.name, tool] }.to_h
      @max_iterations = max_iterations
    end

    def forward(question)
      history = ""
      available_tools_desc = @tools.map { |name, tool| "- #{name}: #{tool.description}" }.join("\n")

      @max_iterations.times do |i|
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
          return {
            answer: action_input,
            history: history,
            iterations: i + 1
          }
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
          # Generate final answer
          final_thought = @thought_generator.call(
            question: question,
            history: history,
            available_tools: available_tools_desc
          )

          return {
            answer: final_thought.action_input,
            history: history,
            iterations: i + 1
          }
        end
      end

      # If we've exhausted iterations, return the last state
      {
        answer: "Unable to find answer within #{@max_iterations} iterations",
        history: history,
        iterations: @max_iterations
      }
    end

    private

    def execute_action(action, action_input)
      tool = @tools[action.downcase]

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
