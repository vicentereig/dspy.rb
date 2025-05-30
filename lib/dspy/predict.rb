# frozen_string_literal: true

module DSPy
  class PredictionInvalidError < RuntimeError
    attr_accessor :errors
    def initialize(errors)
      @errors = errors
      super("Prediction invalid: #{errors.to_h}")
    end
  end
  class Predict < DSPy::Module
    attr_reader :signature_class

    def initialize(signature_class)
      @signature_class = signature_class
    end

    def system_signature
      <<-PROMPT
      Your input schema fields are:
        ```json
         #{JSON.generate(@signature_class.input_schema.json_schema)}
        ```
      Your output schema fields are:
        ```json
          #{JSON.generate(@signature_class.output_schema.json_schema)}
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

    def lm
      DSPy.config.lm
    end

    def forward(**input_values)
      DSPy.logger.info( module: self.class.to_s, **input_values)
      result = @signature_class.input_schema.call(input_values)
      if result.success?
        output_attributes = lm.chat(self, input_values)
        poro_class = Data.define(*output_attributes.keys)
        return poro_class.new(*output_attributes.values)
      end
      raise PredictionInvalidError.new(result.errors)
    end
  end
end
