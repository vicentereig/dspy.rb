# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'module'
require_relative 'prompt'
require_relative 'utils/serialization'
require_relative 'mixins/struct_builder'
require_relative 'mixins/type_coercion'
require_relative 'error_formatter'

module DSPy
  # Exception raised when prediction fails validation
  class PredictionInvalidError < StandardError
    extend T::Sig

    sig { params(errors: T::Hash[T.untyped, T.untyped], context: T.nilable(String)).void }
    def initialize(errors, context: nil)
      @errors = errors
      @context = context
      
      # Format the error message using ErrorFormatter for better readability
      formatted_message = if errors.key?(:output) && errors[:output].is_a?(String)
        # This is likely a type validation error from Sorbet
        formatted = DSPy::ErrorFormatter.format_error(errors[:output], context)
        "Prediction validation failed:\n\n#{formatted}"
      elsif errors.key?(:input) && errors[:input].is_a?(String)
        # This is an input validation error
        formatted = DSPy::ErrorFormatter.format_error(errors[:input], context)
        "Input validation failed:\n\n#{formatted}"
      else
        # Fallback to original format for any other error structure
        "Prediction validation failed: #{errors}"
      end
      
      super(formatted_message)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :errors

    sig { returns(T.nilable(String)) }
    attr_reader :context
  end

  class Predict < DSPy::Module
    extend T::Sig
    include Mixins::StructBuilder
    include Mixins::TypeCoercion

    sig { returns(T.class_of(Signature)) }
    attr_reader :signature_class

    sig { returns(Prompt) }
    attr_reader :prompt

    # Mutable demos attribute for MIPROv2 compatibility
    sig { returns(T.nilable(T::Array[FewShotExample])) }
    attr_accessor :demos

    sig { params(signature_class: T.class_of(Signature)).void }
    def initialize(signature_class)
      super()
      @signature_class = signature_class

      # Get schema_format from configured LM, default to :json
      schema_format = if DSPy.config && DSPy.config.lm
        DSPy.config.lm.schema_format || :json
      else
        :json
      end

      @prompt = Prompt.from_signature(signature_class, schema_format: schema_format)
      @demos = nil
    end

    # Reconstruct program from serialized hash
    sig { params(data: T::Hash[Symbol, T.untyped]).returns(T.attached_class) }
    def self.from_h(data)
      state = data[:state]
      raise ArgumentError, "Missing state in serialized data" unless state

      signature_class_name = state[:signature_class]
      signature_class = Object.const_get(signature_class_name)
      program = new(signature_class)
      
      # Restore instruction if available
      if state[:instruction]
        program = program.with_instruction(state[:instruction])
      end
      
      # Restore examples if available
      few_shot_examples = state[:few_shot_examples]
      if few_shot_examples && !few_shot_examples.empty?
        # Convert hash examples back to FewShotExample objects
        examples = few_shot_examples.map do |ex|
          if ex.is_a?(Hash)
            DSPy::FewShotExample.new(
              input: ex[:input],
              output: ex[:output],
              reasoning: ex[:reasoning]
            )
          else
            ex
          end
        end
        program = program.with_examples(examples)
      end
      
      program
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

    # Remove forward override to let Module#forward handle span creation

    sig { params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      # Module#forward handles span creation, we just do the prediction logic
      
      # Apply type coercion to input values first
      input_props = @signature_class.input_struct_class.props
      coerced_input_values = coerce_output_attributes(input_values, input_props)
      
      # Store coerced input values for optimization
      @last_input_values = coerced_input_values.clone
      
      # Validate input with coerced values
      validate_input_struct(coerced_input_values)
      
      # Check if LM is configured
      current_lm = lm
      if current_lm.nil?
        raise DSPy::ConfigurationError.missing_lm(self.class.name)
      end
      
      # Call LM and process response with coerced input values
      output_attributes = current_lm.chat(self, coerced_input_values)
      processed_output = process_lm_output(output_attributes)
      
      # Create combined result struct with coerced input values
      prediction_result = create_prediction_result(coerced_input_values, processed_output)
      
      prediction_result
    end

    private

    # Validates input using signature struct (assumes input is already coerced)
    sig { params(input_values: T::Hash[Symbol, T.untyped]).void }
    def validate_input_struct(input_values)
      @signature_class.input_struct_class.new(**input_values)
    rescue ArgumentError => e
      DSPy.log('prediction.validation_error', **{
        'dspy.signature' => @signature_class.name,
        'prediction.validation_type' => 'input',
        'prediction.validation_errors' => { input: e.message }
      })
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
        
        # Preprocess nilable attributes before struct instantiation
        processed_attributes = preprocess_nilable_attributes(all_attributes, combined_struct)
        
        combined_struct.new(**processed_attributes)
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

    # Preprocesses attributes to handle nilable fields properly before struct instantiation
    sig { params(attributes: T::Hash[Symbol, T.untyped], struct_class: T.class_of(T::Struct)).returns(T::Hash[Symbol, T.untyped]) }
    def preprocess_nilable_attributes(attributes, struct_class)
      processed = attributes.dup
      struct_props = struct_class.props

      # Process each attribute based on its type in the struct
      processed.each do |key, value|
        prop_info = struct_props[key]
        next unless prop_info

        prop_type = prop_info[:type_object] || prop_info[:type]
        next unless prop_type

        # For nilable fields with nil values, ensure proper handling
        if value.nil? && is_nilable_type?(prop_type)
          # For nilable fields, nil is valid - keep it as is
          next
        elsif value.nil? && prop_info[:fully_optional]
          # For fully optional fields, nil is valid - keep it as is
          next
        elsif value.nil? && prop_info[:default]
          # Use default value if available
          default_value = prop_info[:default]
          processed[key] = default_value.is_a?(Proc) ? default_value.call : default_value
        end
      end

      processed
    end
  end
end
