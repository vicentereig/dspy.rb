# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'module'
require_relative 'instrumentation'
require_relative 'prompt'
require_relative 'mixins/struct_builder'
require_relative 'mixins/type_coercion'
require_relative 'mixins/instrumentation_helpers'

module DSPy
  # Exception raised when prediction fails validation
  class PredictionInvalidError < StandardError
    extend T::Sig

    sig { params(errors: T::Hash[T.untyped, T.untyped]).void }
    def initialize(errors)
      @errors = errors
      super("Prediction validation failed: #{errors}")
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :errors
  end

  class Predict < DSPy::Module
    extend T::Sig
    include Mixins::StructBuilder
    include Mixins::TypeCoercion
    include Mixins::InstrumentationHelpers

    sig { returns(T.class_of(Signature)) }
    attr_reader :signature_class

    sig { returns(Prompt) }
    attr_reader :prompt

    sig { params(signature_class: T.class_of(Signature)).void }
    def initialize(signature_class)
      super()
      @signature_class = signature_class
      @prompt = Prompt.from_signature(signature_class)
    end

    # Backward compatibility methods - delegate to prompt object
    sig { returns(String) }
    def system_signature
      @prompt.render_system_prompt
    end

    sig { params(input_values: T::Hash[Symbol, T.untyped]).returns(String) }
    def user_signature(input_values)
      @prompt.render_user_prompt(input_values)
    end

    # New prompt-based interface for optimization
    sig { params(new_prompt: Prompt).returns(Predict) }
    def with_prompt(new_prompt)
      # Create a new instance with the same signature but updated prompt
      instance = self.class.new(@signature_class)
      instance.instance_variable_set(:@prompt, new_prompt)
      instance
    end

    sig { params(instruction: String).returns(Predict) }
    def with_instruction(instruction)
      with_prompt(@prompt.with_instruction(instruction))
    end

    sig { params(examples: T::Array[FewShotExample]).returns(Predict) }
    def with_examples(examples)
      with_prompt(@prompt.with_examples(examples))
    end

    sig { params(examples: T::Array[FewShotExample]).returns(Predict) }
    def add_examples(examples)
      with_prompt(@prompt.add_examples(examples))
    end

    sig { override.params(kwargs: T.untyped).returns(T.type_parameter(:O)) }
    def forward(**kwargs)
      @last_input_values = kwargs.clone
      T.cast(forward_untyped(**kwargs), T.type_parameter(:O))
    end

    sig { params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      instrument_prediction('dspy.predict', @signature_class, input_values) do
        # Validate input
        validate_input_struct(input_values)
        
        # Call LM and process response
        output_attributes = lm.chat(self, input_values)
        processed_output = process_lm_output(output_attributes)
        
        # Create combined result struct
        create_prediction_result(input_values, processed_output)
      end
    end

    private

    # Validates input using signature struct
    sig { params(input_values: T::Hash[Symbol, T.untyped]).void }
    def validate_input_struct(input_values)
      @signature_class.input_struct_class.new(**input_values)
    rescue ArgumentError => e
      emit_validation_error(@signature_class, 'input', e.message)
      raise PredictionInvalidError.new({ input: e.message })
    end

    # Processes LM output with type coercion
    sig { params(output_attributes: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def process_lm_output(output_attributes)
      output_attributes = output_attributes.transform_keys(&:to_sym)
      output_props = @signature_class.output_struct_class.props
      
      # Apply defaults for missing fields
      output_attributes = apply_defaults_to_output(output_attributes)
      
      coerce_output_attributes(output_attributes, output_props)
    end

    # Creates the final prediction result struct
    sig { params(input_values: T::Hash[Symbol, T.untyped], output_attributes: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def create_prediction_result(input_values, output_attributes)
      begin
        combined_struct = create_combined_struct_class
        all_attributes = input_values.merge(output_attributes)
        combined_struct.new(**all_attributes)
      rescue ArgumentError => e
        raise PredictionInvalidError.new({ output: e.message })
      rescue TypeError => e
        raise PredictionInvalidError.new({ output: e.message })
      end
    end

    # Creates a combined struct class with input and output properties
    sig { returns(T.class_of(T::Struct)) }
    def create_combined_struct_class
      input_props = @signature_class.input_struct_class.props
      output_props = @signature_class.output_struct_class.props
      
      build_enhanced_struct({
        input: input_props,
        output: output_props
      })
    end

    # Applies default values to missing output fields
    sig { params(output_attributes: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def apply_defaults_to_output(output_attributes)
      return output_attributes unless @signature_class.respond_to?(:output_field_descriptors)
      
      field_descriptors = @signature_class.output_field_descriptors
      
      field_descriptors.each do |field_name, descriptor|
        # Only apply default if field is missing and has a default
        if !output_attributes.key?(field_name) && descriptor.has_default
          output_attributes[field_name] = descriptor.default_value
        end
      end
      
      output_attributes
    end
  end
end
