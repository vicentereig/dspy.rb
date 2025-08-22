# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'predict'
require_relative 'signature'
require 'json'
require 'stringio'
require_relative 'mixins/struct_builder'
require_relative 'type_serializer'

module DSPy
  # Define a simple struct for CodeAct history entries with proper type annotations
  class CodeActHistoryEntry < T::Struct
    const :step, Integer
    prop :thought, T.nilable(String)
    prop :ruby_code, T.nilable(String)
    prop :execution_result, T.nilable(String)
    prop :error_message, String

    # Custom serialization to ensure compatibility with the rest of the code
    def to_h
      {
        step: step,
        thought: thought,
        ruby_code: ruby_code,
        execution_result: execution_result,
        error_message: error_message
      }.compact
    end
  end

  # Defines the signature for Ruby code generation
  class RubyCodeGeneration < DSPy::Signature
    description "Generate Ruby code to solve the given task."

    input do
      const :task, String,
        description: "JSON representation of all input fields for the task"
      const :context, String,
        description: "Available variables and previous results from code execution history"
      const :history, T::Array[CodeActHistoryEntry],
        description: "Previous thoughts and code executions with their results. Use this to understand what has been tried and what variables are available."
    end

    output do
      const :thought, String,
        description: "Reasoning about the approach to solve the task with Ruby code"
      const :ruby_code, String,
        description: "Ruby code to execute. This should be valid Ruby code that can be evaluated safely. Avoid system calls, file operations, or other potentially dangerous operations."
      const :explanation, String,
        description: "Brief explanation of what the code does and why this approach was chosen"
    end
  end

  class CodeActNextStep < T::Enum
    enums do
      Continue = new("continue")
      Finish = new("finish")
    end
  end

  # Defines the signature for processing code execution results
  class RubyCodeObservation < DSPy::Signature
    description "Process the result of Ruby code execution and decide what to do next."

    input do
      const :task, String,
        description: "JSON representation of all input fields for the task"
      const :history, T::Array[CodeActHistoryEntry],
        description: "Previous thoughts, code executions, and their results"
      const :execution_result, T.nilable(String),
        description: "The result from executing the Ruby code"
      const :error_message, String,
        description: "Error message if the code execution failed (empty string if no error)"
    end

    output do
      const :observation, String,
        description: "Analysis of the execution result and what it means for solving the task"
      const :next_step, CodeActNextStep,
        description: "What to do next: '#{CodeActNextStep::Continue}' to continue with more code or '#{CodeActNextStep::Finish}' if the task is complete"
      const :final_answer, T.nilable(String),
        description: "If next_step is 'finish', provide the final answer to the task based on the execution results"
    end
  end

  # CodeAct Agent using Think-Code-Observe pattern
  class CodeAct < Predict
    extend T::Sig
    include Mixins::StructBuilder

    sig { returns(T.class_of(DSPy::Signature)) }
    attr_reader :original_signature_class

    sig { returns(T.class_of(T::Struct)) }
    attr_reader :enhanced_output_struct

    sig { returns(Integer) }
    attr_reader :max_iterations

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :execution_context

    sig { params(signature_class: T.class_of(DSPy::Signature), max_iterations: Integer).void }
    def initialize(signature_class, max_iterations: 10)
      @original_signature_class = signature_class
      @max_iterations = max_iterations
      @execution_context = T.let({}, T::Hash[Symbol, T.untyped])

      # Create code generator using Predict to preserve field descriptions
      @code_generator = T.let(DSPy::Predict.new(RubyCodeGeneration), DSPy::Predict)

      # Create observation processor using Predict to preserve field descriptions
      @observation_processor = T.let(DSPy::Predict.new(RubyCodeObservation), DSPy::Predict)

      # Create enhanced output struct with CodeAct fields
      @enhanced_output_struct = create_enhanced_output_struct(signature_class)
      enhanced_output_struct = @enhanced_output_struct

      # Create enhanced signature class
      enhanced_signature = Class.new(DSPy::Signature) do
        # Set the description
        description signature_class.description

        # Use the same input struct
        @input_struct_class = signature_class.input_struct_class

        # Use the enhanced output struct with CodeAct fields
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
      # Validate input and serialize all fields as task context
      input_struct = @original_signature_class.input_struct_class.new(**kwargs)
      task = DSPy::TypeSerializer.serialize(input_struct).to_json

      # Execute CodeAct reasoning loop
      reasoning_result = execute_codeact_reasoning_loop(task)

      # Create enhanced output with all CodeAct data
      create_enhanced_result(kwargs, reasoning_result)
    end

    private

    # Executes the main CodeAct reasoning loop (Think-Code-Observe)
    sig { params(task: String).returns(T::Hash[Symbol, T.untyped]) }
    def execute_codeact_reasoning_loop(task)
      history = T.let([], T::Array[CodeActHistoryEntry])
      final_answer = T.let(nil, T.nilable(String))
      iterations_count = 0
      context = ""

      while should_continue_iteration?(iterations_count, final_answer)
        iterations_count += 1

        iteration_result = execute_single_iteration(
          task, history, context, iterations_count
        )

        if iteration_result[:should_finish]
          final_answer = iteration_result[:final_answer]
          break
        end

        history = iteration_result[:history]
        context = iteration_result[:context]
      end

      handle_max_iterations_if_needed(iterations_count, final_answer, history)

      {
        history: history,
        iterations: iterations_count,
        final_answer: final_answer || default_no_answer_message,
        execution_context: @execution_context
      }
    end

    # Executes a single iteration of the Think-Code-Observe loop
    sig { params(task: String, history: T::Array[CodeActHistoryEntry], context: String, iteration: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def execute_single_iteration(task, history, context, iteration)
      DSPy::Context.with_span(
        operation: 'codeact.iteration',
        'dspy.module' => 'CodeAct',
        'codeact.iteration' => iteration,
        'codeact.max_iterations' => @max_iterations,
        'codeact.history_length' => history.length
      ) do
        execution_state = execute_think_code_step(task, context, history, iteration)
        
        observation_decision = process_observation_and_decide_next_step(
          task, execution_state[:history], execution_state[:execution_result], 
          execution_state[:error_message], iteration
        )

        if observation_decision[:should_finish]
          return { should_finish: true, final_answer: observation_decision[:final_answer] }
        end

        finalize_iteration(execution_state, iteration)
      end
    end

    # Executes the Think-Code step: generates code and executes it
    sig { params(task: String, context: String, history: T::Array[CodeActHistoryEntry], iteration: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def execute_think_code_step(task, context, history, iteration)
      code_obj = @code_generator.forward(
        task: task,
        context: context.empty? ? "No previous context available." : context,
        history: history
      )

      execution_result, error_message = execute_ruby_code_with_instrumentation(
        code_obj.ruby_code, iteration
      )

      history << create_history_entry(
        iteration, code_obj.thought, code_obj.ruby_code,
        execution_result, error_message
      )

      {
        history: history,
        thought: code_obj.thought,
        ruby_code: code_obj.ruby_code,
        execution_result: execution_result,
        error_message: error_message
      }
    end

    # Finalizes iteration by updating context and emitting events
    sig { params(execution_state: T::Hash[Symbol, T.untyped], iteration: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def finalize_iteration(execution_state, iteration)
      new_context = build_context_from_history(execution_state[:history])

      emit_iteration_complete_event(
        iteration, execution_state[:thought], execution_state[:ruby_code],
        execution_state[:execution_result], execution_state[:error_message]
      )

      {
        should_finish: false,
        history: execution_state[:history],
        context: new_context
      }
    end

    # Creates enhanced output struct with CodeAct-specific fields
    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(T::Struct)) }
    def create_enhanced_output_struct(signature_class)
      input_props = signature_class.input_struct_class.props
      output_props = signature_class.output_struct_class.props

      build_enhanced_struct(
        { input: input_props, output: output_props },
        {
          history: [T::Array[T::Hash[Symbol, T.untyped]], "CodeAct execution history"],
          iterations: [Integer, "Number of iterations executed"],
          execution_context: [T::Hash[Symbol, T.untyped], "Variables and context from code execution"]
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
        execution_context: reasoning_result[:execution_context]
      })
      output_data[output_field_name] = reasoning_result[:final_answer]

      @enhanced_output_struct.new(**output_data)
    end

    # Helper methods for CodeAct logic
    sig { params(iterations_count: Integer, final_answer: T.nilable(String)).returns(T::Boolean) }
    def should_continue_iteration?(iterations_count, final_answer)
      final_answer.nil? && (@max_iterations.nil? || iterations_count < @max_iterations)
    end

    sig { params(ruby_code: String, iteration: Integer).returns([T.nilable(String), String]) }
    def execute_ruby_code_with_instrumentation(ruby_code, iteration)
      DSPy::Context.with_span(
        operation: 'codeact.code_execution',
        'dspy.module' => 'CodeAct',
        'codeact.iteration' => iteration,
        'code.length' => ruby_code.length
      ) do
        execute_ruby_code_safely(ruby_code)
      end
    end

    sig { params(step: Integer, thought: String, ruby_code: String, execution_result: T.nilable(String), error_message: String).returns(CodeActHistoryEntry) }
    def create_history_entry(step, thought, ruby_code, execution_result, error_message)
      CodeActHistoryEntry.new(
        step: step,
        thought: thought,
        ruby_code: ruby_code,
        execution_result: execution_result,
        error_message: error_message
      )
    end

    sig { params(task: String, history: T::Array[CodeActHistoryEntry], execution_result: T.nilable(String), error_message: String, iteration: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def process_observation_and_decide_next_step(task, history, execution_result, error_message, iteration)
      observation_result = @observation_processor.forward(
        task: task,
        history: history,
        execution_result: execution_result,
        error_message: error_message
      )

      return { should_finish: false } unless observation_result.next_step == CodeActNextStep::Finish

      final_answer = observation_result.final_answer || execution_result || "Task completed"

      { should_finish: true, final_answer: final_answer }
    end

    sig { params(history: T::Array[CodeActHistoryEntry]).returns(String) }
    def build_context_from_history(history)
      context_parts = []
      
      history.each do |entry|
        if entry.execution_result && !entry.execution_result.empty?
          context_parts << "Step #{entry.step} result: #{entry.execution_result}"
        end
      end

      context_parts.join("\n")
    end

    sig { params(iteration: Integer, thought: String, ruby_code: String, execution_result: T.nilable(String), error_message: T.nilable(String)).void }
    def emit_iteration_complete_event(iteration, thought, ruby_code, execution_result, error_message)
      DSPy.log('codeact.iteration_complete', **{
        'codeact.iteration' => iteration,
        'codeact.thought' => thought,
        'codeact.ruby_code' => ruby_code,
        'codeact.execution_result' => execution_result,
        'codeact.error_message' => error_message,
        'codeact.success' => error_message.nil?
      })
    end

    sig { params(iterations_count: Integer, final_answer: T.nilable(String), history: T::Array[CodeActHistoryEntry]).void }
    def handle_max_iterations_if_needed(iterations_count, final_answer, history)
      if iterations_count >= @max_iterations && final_answer.nil?
        DSPy.log('codeact.max_iterations', **{
          'codeact.iteration_count' => iterations_count,
          'codeact.max_iterations' => @max_iterations,
          'codeact.final_history_length' => history.length
        })
      end
    end

    sig { returns(String) }
    def default_no_answer_message
      "No solution reached within #{@max_iterations} iterations"
    end

    # Safe Ruby code execution method - placeholder for now
    sig { params(ruby_code: String).returns([T.nilable(String), String]) }
    def execute_ruby_code_safely(ruby_code)
      # TODO: Implement proper sandboxing in Phase 2
      # For now, use basic eval with error handling
      original_stdout = nil
      captured_output = nil
      
      begin
        # Capture stdout to get print/puts output
        original_stdout = $stdout
        captured_output = StringIO.new
        $stdout = captured_output

        result = eval(ruby_code, binding)
        
        # Get the captured output
        output = captured_output.string
        
        # If there's captured output, use it, otherwise use the eval result
        final_result = output.empty? ? result.to_s : output.chomp
        
        [final_result, ""]
      rescue SyntaxError => e
        [nil, "Error: #{e.message}"]
      rescue => e
        [nil, "Error: #{e.message}"]
      ensure
        $stdout = original_stdout if original_stdout
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

      # Validate CodeAct-specific fields
      unless output.respond_to?(:history) && output.history.is_a?(Array)
        raise "Missing or invalid history field"
      end

      unless output.respond_to?(:iterations) && output.iterations.is_a?(Integer)
        raise "Missing or invalid iterations field"
      end

      unless output.respond_to?(:execution_context) && output.execution_context.is_a?(Hash)
        raise "Missing or invalid execution_context field"
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def generate_example_output
      # Create a base example structure
      example = {}
      
      # Add CodeAct-specific example data
      example[:history] = [
        {
          step: 1,
          thought: "I need to write Ruby code to solve this task...",
          ruby_code: "result = 2 + 2",
          execution_result: "4",
          error_message: nil
        }
      ]
      example[:iterations] = 1
      example[:execution_context] = { result: 4 }
      example
    end
  end
end