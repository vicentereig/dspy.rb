# frozen_string_literal: true

require 'sorbet-runtime'
require_relative 'sorbet_module'

module DSPy
  class SorbetPredict < DSPy::SorbetModule
    extend T::Sig

    sig { returns(T.class_of(SorbetSignature)) }
    attr_reader :signature_class

    sig { params(signature_class: T.class_of(SorbetSignature)).void }
    def initialize(signature_class)
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
      
      For example, based on the schemas above, a valid interaction would be:
      ## Input values
        ```json
          #{JSON.generate(generate_example_input)}
        ```
      ## Output values
        ```json
          #{JSON.generate(generate_example_output)}
        ```
      
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

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def generate_example_input
      example = {}
      @signature_class.input_struct_class.props.each do |name, prop|
        example[name] = case prop[:type]
        when T::Types::Simple
          case prop[:type].raw_type.to_s
          when "String" then "example text"
          when "Integer" then 42
          when "Float" then 3.14
          else "example"
          end
        else
          "example"
        end
      end
      example
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def generate_example_output
      example = {}
      @signature_class.output_struct_class.props.each do |name, prop|
        example[name] = case prop[:type]
        when T::Types::Simple
          if prop[:type].raw_type < T::Enum
            # Use the first enum value as example
            prop[:type].raw_type.values.first.serialize
          else
            case prop[:type].raw_type.to_s
            when "String" then "example result"
            when "Integer" then 1
            when "Float" then 0.95
            else "example"
            end
          end
        else
          "example"
        end
      end
      example
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

    sig { returns(DSPy::LM) }
    def lm
      DSPy.config.lm
    end

    sig { override.params(kwargs: T.untyped).returns(T.untyped) }
    def forward(**kwargs)
      # Store the input values to add to the result hash later
      @last_input_values = kwargs.clone

      # Call the untyped forward method
      result = forward_untyped(**kwargs)

      # Attach the input values to the result object for use in to_h
      if result.is_a?(T::Struct) && !result.instance_variable_defined?(:@input_values)
        result.instance_variable_set(:@input_values, kwargs)
      end

      # For type checking in client code
      T.cast(result, T.untyped)
    end

    sig { params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      DSPy.logger.info(module: self.class.to_s, **input_values)

      # Validate input using T::Struct
      begin
        _input_struct = @signature_class.input_struct_class.new(**input_values)
      rescue ArgumentError => e
        raise PredictionInvalidError.new({ input: e.message })
      end

      # Use the original input_values since input_struct.to_h may not be available
      # The input has already been validated through the struct instantiation
      output_attributes = lm.chat(self, input_values)

      # Debug: log what we got from LM
      DSPy.logger.info("LM returned: #{output_attributes.inspect}")
      DSPy.logger.info("Output attributes class: #{output_attributes.class}")

      # Convert string keys to symbols
      output_attributes = output_attributes.transform_keys(&:to_sym)

      # Handle enum deserialization
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
            # Deserialize enum value
            [key, enum_class.deserialize(value)]
          elsif prop_type == Float || (prop_type.is_a?(T::Types::Simple) && prop_type.raw_type == Float)
            # Coerce to Float
            [key, value.to_f]
          elsif prop_type == Integer || (prop_type.is_a?(T::Types::Simple) && prop_type.raw_type == Integer)
            # Coerce to Integer
            [key, value.to_i]
          else
            [key, value]
          end
        else
          [key, value]
        end
      end.to_h

      # Create output struct with validation
      begin
        output_struct = @signature_class.output_struct_class.new(**output_attributes)
        return output_struct
      rescue ArgumentError => e
        raise PredictionInvalidError.new({ output: e.message })
      rescue TypeError => e
        raise PredictionInvalidError.new({ output: e.message })
      end
    end
  end
end
