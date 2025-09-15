# frozen_string_literal: true

require 'sorbet-runtime'
require 'dry-configurable'
require_relative 'context'

module DSPy
  class Module
    extend T::Sig
    extend T::Generic
    include Dry::Configurable

    # Per-instance LM configuration
    setting :lm, default: nil

    # The main forward method that users will call is generic and type parameterized
    sig do
      type_parameters(:I, :O)
        .params(
          input_values: T.type_parameter(:I)
        )
        .returns(T.type_parameter(:O))
    end
    def forward(**input_values)
      # Create span for this module's execution
      observation_type = DSPy::ObservationType.for_module_class(self.class)
      DSPy::Context.with_span(
        operation: "#{self.class.name}.forward",
        **observation_type.langfuse_attributes,
        'langfuse.observation.input' => input_values.to_json,
        'dspy.module' => self.class.name
      ) do |span|
        result = forward_untyped(**input_values)
        
        # Add output to span
        if span && result
          output_json = result.respond_to?(:to_h) ? result.to_h.to_json : result.to_json rescue result.to_s
          span.set_attribute('langfuse.observation.output', output_json)
        end
        
        # Cast the result of forward_untyped to the expected output type
        T.cast(result, T.type_parameter(:O))
      end
    end

    # The implementation method that subclasses must override
    sig { params(input_values: T.untyped).returns(T.untyped) }
    def forward_untyped(**input_values)
      raise NotImplementedError, "Subclasses must implement forward_untyped method"
    end

    # The main call method that users will call is generic and type parameterized
    sig do
      type_parameters(:I, :O)
        .params(
          input_values: T.type_parameter(:I)
        )
        .returns(T.type_parameter(:O))
    end
    def call(**input_values)
      forward(**input_values)
    end

    # The implementation method for call
    sig { params(input_values: T.untyped).returns(T.untyped) }
    def call_untyped(**input_values)
      forward_untyped(**input_values)
    end

    # Get the configured LM for this instance, checking fiber-local context first
    sig { returns(T.untyped) }
    def lm
      config.lm || DSPy.current_lm
    end
  end
end