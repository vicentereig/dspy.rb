# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'predict'
require_relative 'utils/serialization'
require_relative 'signature'
require_relative 'mixins/struct_builder'

module DSPy
  # Enhances prediction by encouraging step-by-step reasoning
  # before providing a final answer using Sorbet signatures.
  class ChainOfThought < Predict
    extend T::Sig
    include Mixins::StructBuilder

    FieldDescriptor = DSPy::Signature::FieldDescriptor

    sig { params(signature_class: T.class_of(DSPy::Signature)).void }
    def initialize(signature_class)
      @original_signature = signature_class
      enhanced_signature = build_enhanced_signature(signature_class)
      
      # Call parent constructor with enhanced signature
      super(enhanced_signature)
      @signature_class = enhanced_signature
    end


    # Override prompt-based methods to maintain ChainOfThought behavior
    sig { override.params(new_prompt: Prompt).returns(ChainOfThought) }
    def with_prompt(new_prompt)
      # Create a new ChainOfThought with the same original signature
      instance = self.class.new(@original_signature)
      
      # Ensure the instruction includes "Think step by step" if not already present
      enhanced_instruction = if new_prompt.instruction.include?("Think step by step")
                               new_prompt.instruction
                             else
                               "#{new_prompt.instruction} Think step by step."
                             end
      
      # Create enhanced prompt with ChainOfThought-specific schemas
      enhanced_prompt = Prompt.new(
        instruction: enhanced_instruction,
        input_schema: @signature_class.input_json_schema,
        output_schema: @signature_class.output_json_schema,
        few_shot_examples: new_prompt.few_shot_examples,
        signature_class_name: @signature_class.name
      )
      
      instance.instance_variable_set(:@prompt, enhanced_prompt)
      instance
    end

    sig { override.params(instruction: String).returns(ChainOfThought) }
    def with_instruction(instruction)
      enhanced_instruction = ensure_chain_of_thought_instruction(instruction)
      super(enhanced_instruction)
    end

    sig { override.params(examples: T::Array[FewShotExample]).returns(ChainOfThought) }
    def with_examples(examples)
      # Convert examples to include reasoning if they don't have it
      enhanced_examples = examples.map do |example|
        if example.reasoning.nil? || example.reasoning.empty?
          # Try to extract reasoning from the output if it contains a reasoning field
          reasoning = example.output[:reasoning] || "Step by step reasoning for this example."
          DSPy::FewShotExample.new(
            input: example.input,
            output: example.output,
            reasoning: reasoning
          )
        else
          example
        end
      end
      
      super(enhanced_examples)
    end

    # Access to the original signature for optimization
    sig { returns(T.class_of(DSPy::Signature)) }
    attr_reader :original_signature

    # Override forward_untyped to add ChainOfThought-specific analysis
    # Let Module#forward handle the ChainOfThought span creation automatically
    sig { override.params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      # Create a Predict instance and call its forward method (which will create Predict span via Module#forward)
      # We can't call super.forward because that would go to Module#forward_untyped, not Module#forward
      
      # Create a temporary Predict instance with our enhanced signature to get the prediction
      predict_instance = DSPy::Predict.new(@signature_class)
      predict_instance.config.lm = self.lm  # Use the same LM configuration
      
      # Call predict's forward method, which will create the Predict span
      prediction_result = predict_instance.forward(**input_values)
      
      # Add ChainOfThought-specific analysis and events
      if DSPy::Observability.enabled? && prediction_result
        # Add reasoning metrics via events
        if prediction_result.respond_to?(:reasoning) && prediction_result.reasoning
          DSPy.event('chain_of_thought.reasoning_metrics', {
            'cot.reasoning_length' => prediction_result.reasoning.length,
            'cot.has_reasoning' => true,
            'cot.reasoning_steps' => count_reasoning_steps(prediction_result.reasoning),
            'dspy.module_type' => 'chain_of_thought',
            'dspy.signature' => @original_signature.name
          })
        end
      end
      
      # Analyze reasoning (emits events for backwards compatibility)
      analyze_reasoning(prediction_result)
      
      prediction_result
    end

    private

    # Builds enhanced signature with reasoning capabilities
    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(DSPy::Signature)) }
    def build_enhanced_signature(signature_class)
      enhanced_output_struct = create_enhanced_output_struct(signature_class)
      create_signature_class(signature_class, enhanced_output_struct)
    end

    # Creates signature class with enhanced description and reasoning field
    sig { params(signature_class: T.class_of(DSPy::Signature), enhanced_output_struct: T.class_of(T::Struct)).returns(T.class_of(DSPy::Signature)) }
    def create_signature_class(signature_class, enhanced_output_struct)
      original_name = signature_class.name
      
      Class.new(DSPy::Signature) do
        description "#{signature_class.description} Think step by step."

        # Use the same input struct and copy field descriptors
        @input_struct_class = signature_class.input_struct_class
        @input_field_descriptors = signature_class.instance_variable_get(:@input_field_descriptors) || {}

        # Use the enhanced output struct and create field descriptors for it
        @output_struct_class = enhanced_output_struct

        # Create field descriptors for the enhanced output struct
        @output_field_descriptors = {}

        # Copy original output field descriptors
        original_output_descriptors = signature_class.instance_variable_get(:@output_field_descriptors) || {}
        @output_field_descriptors.merge!(original_output_descriptors)

        # Add reasoning field descriptor (ChainOfThought always provides this)
        @output_field_descriptors[:reasoning] = FieldDescriptor.new(String, "Step by step reasoning process")

        # Store the original signature name for tracking/logging
        @original_signature_name = original_name

        class << self
          attr_reader :input_struct_class, :output_struct_class, :original_signature_name
          
          # Override name to return the original signature name for tracking
          def name
            @original_signature_name || super
          end
        end
      end
    end

    # Creates enhanced output struct with reasoning field
    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(T::Struct)) }
    def create_enhanced_output_struct(signature_class)
      output_props = signature_class.output_struct_class.props
      
      build_enhanced_struct(
        { output: output_props },
        { reasoning: [String, "Step by step reasoning process"] }
      )
    end

    # Ensures instruction includes chain of thought prompt
    sig { params(instruction: String).returns(String) }
    def ensure_chain_of_thought_instruction(instruction)
      instruction.include?("Think step by step") ? instruction : "#{instruction} Think step by step."
    end

    # Analyzes reasoning in prediction result and emits instrumentation events
    sig { params(prediction_result: T.untyped).void }
    def analyze_reasoning(prediction_result)
      return unless prediction_result.respond_to?(:reasoning) && prediction_result.reasoning
      
      reasoning_content = prediction_result.reasoning.to_s
      return if reasoning_content.empty?
      
      emit_reasoning_analysis(reasoning_content)
    end

    # Emits reasoning analysis instrumentation event
    sig { params(reasoning_content: String).void }
    def emit_reasoning_analysis(reasoning_content)
      DSPy.event('chain_of_thought.reasoning_complete', {
        'dspy.signature' => @original_signature.name,
        'cot.reasoning_steps' => count_reasoning_steps(reasoning_content),
        'cot.reasoning_length' => reasoning_content.length,
        'cot.has_reasoning' => true
      })
    end

    # Count reasoning steps by looking for step indicators
    sig { params(reasoning_text: String).returns(Integer) }
    def count_reasoning_steps(reasoning_text)
      return 0 if reasoning_text.nil? || reasoning_text.empty?
      
      # Look for common step patterns
      step_patterns = [
        /step \d+/i,
        /\d+\./,
        /first|second|third|then|next|finally/i,
        /\n\s*-/
      ]
      
      max_count = 0
      step_patterns.each do |pattern|
        count = reasoning_text.scan(pattern).length
        max_count = [max_count, count].max
      end
      
      # Fallback: count sentences if no clear steps
      max_count > 0 ? max_count : reasoning_text.split(/[.!?]+/).reject(&:empty?).length
    end
  end
end
