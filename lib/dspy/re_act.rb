module DSPy
  # Define the signature for ReAct reasoning
  class Thought < DSPy::Signature
    description "Generate a thought about what to do next to answer the question."

    input do
      required(:question).value(:string).meta(description: 'The question to answer')
      required(:history).value(:array).meta(description: 'Previous thoughts and actions, including observations from tools. The agent MUST use information from the history to inform its actions and final answer. Each entry is a hash representing a step in the reasoning process.')
      required(:available_tools).value(:string).meta(description: 'List of available tools and their descriptions. The agent MUST choose an action from this list or use "finish".')
    end

    output do
      required(:thought).value(:string).meta(description: 'Reasoning about what to do next, considering the history and observations.')
      required(:action).value(:string).meta(description: 'The action to take. MUST be one of the tool names listed in `available_tools` input, or the literal string "finish" to provide the final answer.')
      required(:action_input).value(:string).meta(description: 'Input for the chosen action. If action is "finish", this field MUST contain the final answer to the original question. This answer MUST be directly taken from the relevant Observation in the history if available. For example, if an observation showed "Observation: 100.0", and you are finishing, this field MUST be "100.0". Do not leave empty if finishing with an observed answer.')
    end
  end

  # Define the signature for observing tool results
  class ReActObservation < DSPy::Signature
    description "Process the observation from a tool and decide what to do next."

    input do
      required(:question).value(:string).meta(description: 'The original question')
      required(:history).value(:array).meta(description: 'Previous thoughts, actions, and observations. Each entry is a hash representing a step in the reasoning process.')
      required(:observation).value(:string).meta(description: 'The result from the last action')
    end

    output do
      required(:interpretation).value(:string).meta(description: 'Interpretation of the observation')
      required(:next_step).value(:string).meta(description: 'What to do next: "continue" or "finish"')
    end
  end

  # ReAct Agent Module
  class ReAct < DSPy::Module
    attr_reader :signature_class, :internal_output_schema, :tools, :max_iterations

    # Defines the structure for each entry in the ReAct history
    HistoryEntry = Struct.new(:step, :thought, :action, :action_input, :observation, keyword_init: true) do
      def to_h
        {
          step: step,
          thought: thought,
          action: action,
          action_input: action_input,
          observation: observation
        }
      end
    end

    def initialize(signature_class, tools: [], max_iterations: 5)
      super()
      @signature_class = signature_class # User's original signature class
      @thought_generator = DSPy::ChainOfThought.new(Thought)
      @observation_processor = DSPy::Predict.new(ReActObservation)
      @tools = tools.map { |tool| [tool.name.downcase, tool] }.to_h # Ensure tool names are stored lowercased for lookup
      @max_iterations = max_iterations

      # Define the schema for fields automatically added by ReAct
      react_added_output_schema = Dry::Schema.JSON do
        optional(:history).array(:hash) do
          required(:step).value(:integer)
          optional(:thought).value(:string)
          optional(:action).value(:string)
          optional(:action_input).maybe(:string)
          optional(:observation).maybe(:string)
        end
        optional(:iterations).value(:integer).meta(description: 'Number of iterations taken by the ReAct agent.')
      end

      # Create the augmented internal output schema by combining user's output schema and ReAct's added fields
      @internal_output_schema = Dry::Schema.JSON(parent: [signature_class.output_schema, react_added_output_schema])
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

      history = [] # Initialize history as an array of HistoryEntry objects
      available_tools_desc = @tools.map { |name, tool| "- #{name}: #{tool.description}" }.join("\n")

      final_answer = nil
      iterations_count = 0

      @max_iterations.times do |i|
        iterations_count = i + 1
        current_step_history = { step: iterations_count }

        # Generate thought and action
        thought_result = @thought_generator.call(
          question: question,
          history: history.map(&:to_h),
          available_tools: available_tools_desc
        )

        thought = thought_result.thought
        action = thought_result.action
        current_action_input = thought_result.action_input # What LM provided

        current_step_history[:thought] = thought
        current_step_history[:action] = action

        if action.downcase == "finish"
          # If LM says 'finish' but gives empty input, try to use last observation
          if current_action_input.nil? || current_action_input.strip.empty?
            # Try to find the last observation in history
            last_entry_with_observation = history.reverse.find { |entry| entry.observation && !entry.observation.strip.empty? }
            
            if last_entry_with_observation
              last_observation_value = last_entry_with_observation.observation.strip
              DSPy.logger.info(
                module: "ReAct",
                status: "Finish action had empty input. Overriding with last observation.",
                original_input: current_action_input,
                derived_input: last_observation_value
              )
              current_action_input = last_observation_value # Override
            else
              DSPy.logger.warn(module: "ReAct", status: "Finish action had empty input, no prior Observation found in history.", original_input: current_action_input)
            end
          end
          final_answer = current_action_input # Set final answer from (potentially overridden) input
        end

        # Add thought to history using current_action_input, which might have been overridden for 'finish'
        current_step_history[:action_input] = current_action_input

        # Check if we should finish (using the original action from LM)
        if action.downcase == "finish"
          DSPy.logger.info(module: "ReAct", status: "Finishing loop after thought", action: action, final_answer: final_answer, question: question)
          history << HistoryEntry.new(**current_step_history) # Add final thought/action before breaking
          break
        end

        # Execute the action
        observation_text = execute_action(action, current_action_input) # current_action_input is original for non-finish
        current_step_history[:observation] = observation_text
        history << HistoryEntry.new(**current_step_history) # Add completed step to history

        # Process the observation
        obs_result = @observation_processor.call(
          question: question,
          history: history.map(&:to_h),
          observation: observation_text
        )

        if obs_result.next_step.downcase == "finish"
          DSPy.logger.info(module: "ReAct", status: "Observation processor suggests finish. Generating final thought.", question: question, history_before_final_thought: history.map(&:to_h))
          # Generate final thought/answer if observation processor decides to finish

          # Create a new history entry for this final thought sequence
          final_thought_step_history = { step: iterations_count + 1 } # This is like a sub-step or a new thought step

          final_thought_result = @thought_generator.call(
            question: question,
            history: history.map(&:to_h), # history now includes the last observation
            available_tools: available_tools_desc
          )
          DSPy.logger.info(module: "ReAct", status: "Finishing after observation and final thought", final_action: final_thought_result.action, final_action_input: final_thought_result.action_input, question: question)

          final_thought_action = final_thought_result.action
          final_thought_action_input_val = final_thought_result.action_input # LM provided

          final_thought_step_history[:thought] = final_thought_result.thought
          final_thought_step_history[:action] = final_thought_action

          if final_thought_action.downcase == "finish"
            if final_thought_action_input_val.nil? || final_thought_action_input_val.strip.empty?
              # Find the last observation in the history array
              last_entry_with_observation = history.reverse.find { |entry| entry.observation && !entry.observation.strip.empty? }
              
              if last_entry_with_observation
                last_observation_value_ft = last_entry_with_observation.observation.strip
                DSPy.logger.info(
                  module: "ReAct",
                  status: "Final thought 'finish' action had empty input. Overriding with last observation.",
                  original_input: final_thought_action_input_val,
                  derived_input: last_observation_value_ft
                )
                final_thought_action_input_val = last_observation_value_ft # Override
              else
                DSPy.logger.warn(module: "ReAct", status: "Final thought 'finish' action had empty input, last observation also empty/not found cleanly.", original_input: final_thought_action_input_val)
              end
            else
              # This case is if LM provides 'finish' but no observation to fall back on in history array (should be rare if history is populated correctly)
              DSPy.logger.warn(module: "ReAct", status: "Final thought 'finish' action had empty input, no prior Observation found in history array.", original_input: final_thought_action_input_val) if (history.empty? || !history.any? { |entry| entry.observation && !entry.observation.strip.empty? })
            end
          end

          final_thought_step_history[:action_input] = final_thought_action_input_val
          history << HistoryEntry.new(**final_thought_step_history) # Add this final step to history

          final_answer = final_thought_action_input_val # Use (potentially overridden) value
          iterations_count += 1 # Account for this extra thought step in iterations
          break
        end
      end

      final_answer ||= "Unable to find answer within #{@max_iterations} iterations"
      DSPy.logger.info(module: "ReAct", status: "Final answer determined", final_answer: final_answer, question: question) if final_answer.nil? || final_answer.empty? || final_answer == "Unable to find answer within #{@max_iterations} iterations"

      # Prepare output data
      output_data = {}

      # Populate the primary answer field from the user's original signature
      # This assumes the first defined output field in the user's signature is the main answer field.
      user_primary_output_field = @signature_class.output_schema.key_map.first.name.to_sym
      output_data[user_primary_output_field] = final_answer

      # Add ReAct-specific fields
      output_data[:history] = history.map(&:to_h) # Convert HistoryEntry objects to hashes for schema validation
      output_data[:iterations] = iterations_count

      # Validate and create PORO using the augmented internal_output_schema
      output_validation_result = @internal_output_schema.call(output_data)
      unless output_validation_result.success?
        DSPy.logger.error(module: "ReAct", status: "Internal output validation failed", errors: output_validation_result.errors.to_h, data: output_data)
        raise DSPy::PredictionInvalidError.new(output_validation_result.errors)
      end

      # Create PORO with all fields (user's + ReAct's)
      # Sorting keys for Data.define ensures a consistent order for the PORO attributes.
      poro_class = Data.define(*output_validation_result.to_h.keys.sort)
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
