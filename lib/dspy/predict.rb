# frozen_string_literal: true

module DSPy
  class Predict < DSPy::Module
    def initialize(signature_class)
      @signature_class = signature_class
    end

    # TODO: split it in system and user message
    def signature(input_values)
      <<-PROMPT
      Your input fields are:
        ```json
         #{JSON.generate(@signature_class.input_schema.json_schema)}
        ```
      Your output fields are:
        ```json
          #{JSON.generate(@signature_class.output_schema.json_schema)}
        ````
      All interactions will be structured in the following way, with the appropriate values filled in.

      Input values:
        ```json
          #{JSON.generate(input_values)}
        ```  

      Respond exclusively with the output schema.
      
      In adhering to this structure, your objective is: #{@signature_class.description}

      PROMPT
    end

    def forward(**input_values)
      signature = @signature_class.new
      # validate inputs
      @signature_class.input_schema.call(input_values)
      # build prompt
      return signature(input_values)
      # invoke LM
      # validate ouputs
      # return them
    end
  end
end
