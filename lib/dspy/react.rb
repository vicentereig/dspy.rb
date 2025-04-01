module DSPy
  class React < DSPy::Module
    def initialize(signature_class)
      react_schema = Dry::Schema.JSON do
        required(:trajectory).value(:array).each do
          required(:string)
        end.meta(description: 'train of thought during reasoning')
      end

      @react_input_schema = signature_class.input_schema
      @react_output_schema = signature_class.output_schema = Dry::Schema.JSON(parent:
                                                          [
                                                            signature_class.output_schema,
                                                            react_schema
                                                          ])
    end

    def forward(**input_values)

    end
  end
end
