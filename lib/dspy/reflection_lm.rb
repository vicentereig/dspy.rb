# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  # Lightweight wrapper for running reflection prompts without structured outputs.
  class ReflectionLM
    extend T::Sig

    sig { params(model_id: String, options: T::Hash[Symbol, T.untyped]).void }
    def initialize(model_id, **options)
      @lm = DSPy::LM.new(model_id, structured_outputs: false, schema_format: :json, **options)
    end

    sig { params(prompt: String).returns(String) }
    def call(prompt)
      response = @lm.raw_chat([{ role: 'user', content: prompt }])
      response.respond_to?(:content) ? response.content : response.to_s
    end

    sig { params(messages: T.nilable(T::Array[T::Hash[Symbol, String]]), block: T.nilable(T.proc.params(arg0: T.untyped).void)).returns(T.untyped) }
    def raw_chat(messages = nil, &block)
      @lm.raw_chat(messages, &block)
    end
  end
end
