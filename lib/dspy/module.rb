# frozen_string_literal: true

require 'sorbet-runtime'
require 'dry-configurable'

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
      # Cast the result of forward_untyped to the expected output type
      T.cast(forward_untyped(**input_values), T.type_parameter(:O))
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