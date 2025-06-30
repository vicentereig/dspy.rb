# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'predict'
require_relative 'signature'
require_relative 'instrumentation'

module DSPy
  # Enhances prediction by encouraging step-by-step reasoning
  # before providing a final answer using Sorbet signatures.
  class ChainOfThought < Predict
    extend T::Sig

    FieldDescriptor = DSPy::Signature::FieldDescriptor

    sig { params(signature_class: T.class_of(DSPy::Signature)).void }
    def initialize(signature_class)
      @original_signature = signature_class

      # Create enhanced output struct with reasoning
      enhanced_output_struct = create_enhanced_output_struct(signature_class)

      # Create enhanced signature class
      enhanced_signature = Class.new(DSPy::Signature) do
        # Set the description
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

        class << self
          attr_reader :input_struct_class, :output_struct_class
        end
      end

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
      # Ensure ChainOfThought behavior is preserved
      cot_instruction = instruction.include?("Think step by step") ? instruction : "#{instruction} Think step by step."
      super(cot_instruction)
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

    # Override forward_untyped to add ChainOfThought-specific instrumentation
    sig { override.params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      # Prepare instrumentation payload
      input_fields = input_values.keys.map(&:to_s)
      
      # Instrument ChainOfThought lifecycle
      result = Instrumentation.instrument('dspy.chain_of_thought', {
        signature_class: @original_signature.name,
        model: lm.model,
        provider: lm.provider,
        input_fields: input_fields
      }) do
        # Call parent prediction logic
        prediction_result = super(**input_values)
        
        # Analyze reasoning if present
        if prediction_result.respond_to?(:reasoning) && prediction_result.reasoning
          reasoning_content = prediction_result.reasoning.to_s
          reasoning_length = reasoning_content.length
          reasoning_steps = count_reasoning_steps(reasoning_content)
          
          # Emit reasoning analysis event
          Instrumentation.emit('dspy.chain_of_thought.reasoning_complete', {
            signature_class: @original_signature.name,
            reasoning_steps: reasoning_steps,
            reasoning_length: reasoning_length,
            has_reasoning: !reasoning_content.empty?
          })
        end
        
        prediction_result
      end
      
      result
    end

    private

    # Count reasoning steps by looking for step indicators
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

    sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T.class_of(T::Struct)) }
    def create_enhanced_output_struct(signature_class)
      # Get original output props
      original_props = signature_class.output_struct_class.props

      # Create new struct class with reasoning added
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

        # Add reasoning field (ChainOfThought always provides this)
        const :reasoning, String

        # Add to_h method to serialize the struct to a hash
        define_method :to_h do
          hash = {}

          # Start with input values if available
          if self.instance_variable_defined?(:@input_values)
            hash.merge!(self.instance_variable_get(:@input_values))
          end

          # Then add output properties
          self.class.props.keys.each do |key|
            hash[key] = self.send(key)
          end

          hash
        end
      end
    end
  end
end
