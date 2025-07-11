# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  class LM
    module Strategies
      # Base class for JSON extraction strategies
      class BaseStrategy
        extend T::Sig
        extend T::Helpers
        abstract!

        sig { params(adapter: DSPy::LM::Adapter, signature_class: T.class_of(DSPy::Signature)).void }
        def initialize(adapter, signature_class)
          @adapter = adapter
          @signature_class = signature_class
        end

        # Check if this strategy is available for the given adapter/model
        sig { abstract.returns(T::Boolean) }
        def available?; end

        # Priority for this strategy (higher = preferred)
        sig { abstract.returns(Integer) }
        def priority; end

        # Name of the strategy for logging/debugging
        sig { abstract.returns(String) }
        def name; end

        # Prepare the request for JSON extraction
        sig { abstract.params(messages: T::Array[T::Hash[Symbol, String]], request_params: T::Hash[Symbol, T.untyped]).void }
        def prepare_request(messages, request_params); end

        # Extract JSON from the response
        sig { abstract.params(response: DSPy::LM::Response).returns(T.nilable(String)) }
        def extract_json(response); end

        # Handle errors specific to this strategy
        sig { params(error: StandardError).returns(T::Boolean) }
        def handle_error(error)
          # By default, don't handle errors - let them propagate
          false
        end

        protected

        attr_reader :adapter, :signature_class
      end
    end
  end
end