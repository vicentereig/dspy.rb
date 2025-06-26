# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'module'
require_relative 'instrumentation'

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

    sig { returns(T.class_of(Signature)) }
    attr_reader :signature_class

    sig { params(signature_class: T.class_of(Signature)).void }
    def initialize(signature_class)
      super()
      @signature_class = signature_class
    end

    sig { returns(String) }
    def system_signature
      <<-PROMPT
      Your input schema fields are:
        ```json
         #{JSON.generate(@signature_class.input_json_schema)}
        ```
      Your output schema fields are:
        ```json
          #{JSON.generate(@signature_class.output_json_schema)}
        ````
      
      All interactions will be structured in the following way, with the appropriate values filled in.

      ## Input values
        ```json
         {input_values}
        ```  
      ## Output values
      Respond exclusively with the output schema fields in the json block below.
        ```json
          {output_values}
        ```
      
      In adhering to this structure, your objective is: #{@signature_class.description}

      PROMPT
    end

    sig { params(input_values: T::Hash[Symbol, T.untyped]).returns(String) }
    def user_signature(input_values)
      <<-PROMPT
        ## Input Values
        ```json
        #{JSON.generate(input_values)}
        ```     
        
        Respond with the corresponding output schema fields wrapped in a ```json ``` block, 
         starting with the heading `## Output values`.
      PROMPT
    end

    sig { override.params(kwargs: T.untyped).returns(T.type_parameter(:O)) }
    def forward(**kwargs)
      @last_input_values = kwargs.clone

      result = forward_untyped(**kwargs)

      if result.is_a?(T::Struct) && !result.instance_variable_defined?(:@input_values)
        result.instance_variable_set(:@input_values, kwargs)
      end

      T.cast(result, T.type_parameter(:O))
    end

    sig { params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      # Prepare instrumentation payload
      input_fields = input_values.keys.map(&:to_s)
      
      # Instrument the entire prediction lifecycle
      result = Instrumentation.instrument('dspy.predict', {
        signature_class: @signature_class.name,
        model: lm.model,
        provider: lm.provider,
        input_fields: input_fields
      }) do
        DSPy.logger.info(module: self.class.to_s, **input_values)

        # Validate input
        begin
          _input_struct = @signature_class.input_struct_class.new(**input_values)
        rescue ArgumentError => e
          # Emit validation error event
          Instrumentation.emit('dspy.predict.validation_error', {
            signature_class: @signature_class.name,
            validation_type: 'input',
            validation_errors: { input: e.message }
          })
          raise PredictionInvalidError.new({ input: e.message })
        end

        # Call LM
        output_attributes = lm.chat(self, input_values)

        DSPy.logger.info("LM returned: #{output_attributes.inspect}")
        DSPy.logger.info("Output attributes class: #{output_attributes.class}")

        output_attributes = output_attributes.transform_keys(&:to_sym)

        output_props = @signature_class.output_struct_class.props
        output_attributes = output_attributes.map do |key, value|
          prop_type = output_props[key][:type] if output_props[key]
          if prop_type
            # Check if it's an enum (can be raw Class or T::Types::Simple)
            enum_class = if prop_type.is_a?(Class) && prop_type < T::Enum
                           prop_type
                         elsif prop_type.is_a?(T::Types::Simple) && prop_type.raw_type < T::Enum
                           prop_type.raw_type
                         end

            if enum_class
              [key, enum_class.deserialize(value)]
            elsif prop_type == Float || (prop_type.is_a?(T::Types::Simple) && prop_type.raw_type == Float)
              [key, value.to_f]
            elsif prop_type == Integer || (prop_type.is_a?(T::Types::Simple) && prop_type.raw_type == Integer)
              [key, value.to_i]
            else
              [key, value]
            end
          else
            [key, value]
          end
        end.to_h

        # Create combined struct with both input and output values
        begin
          combined_struct = create_combined_struct_class
          all_attributes = input_values.merge(output_attributes)
          return combined_struct.new(**all_attributes)
        rescue ArgumentError => e
          raise PredictionInvalidError.new({ output: e.message })
        rescue TypeError => e
          raise PredictionInvalidError.new({ output: e.message })
        end
      end
    end

    private

    sig { returns(T.class_of(T::Struct)) }
    def create_combined_struct_class
      input_props = @signature_class.input_struct_class.props
      output_props = @signature_class.output_struct_class.props
      
      # Create a new struct class that combines input and output fields
      Class.new(T::Struct) do
        extend T::Sig
        
        # Add input fields
        input_props.each do |name, prop_info|
          if prop_info[:rules]&.any? { |rule| rule.is_a?(T::Props::NilableRules) }
            prop name, prop_info[:type], default: prop_info[:default]
          else
            const name, prop_info[:type], default: prop_info[:default]
          end
        end
        
        # Add output fields  
        output_props.each do |name, prop_info|
          if prop_info[:rules]&.any? { |rule| rule.is_a?(T::Props::NilableRules) }
            prop name, prop_info[:type], default: prop_info[:default]
          else
            const name, prop_info[:type], default: prop_info[:default]
          end
        end
        
        # Add to_h method to serialize the struct to a hash
        define_method :to_h do
          hash = {}
          
          # Add all properties
          self.class.props.keys.each do |key|
            hash[key] = self.send(key)
          end
          
          hash
        end
      end
    end
  end
end
