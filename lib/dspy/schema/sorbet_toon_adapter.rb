# frozen_string_literal: true

require 'sorbet-runtime'
require 'sorbet/toon'

module DSPy
  module Schema
    module SorbetToonAdapter
      extend T::Sig

      module_function

      sig { params(signature_class: T.nilable(T.class_of(DSPy::Signature)), values: T::Hash[Symbol, T.untyped]).returns(String) }
      def render_input(signature_class, values)
        Sorbet::Toon.encode(
          values,
          signature: signature_class,
          role: :input
        )
      end

      sig { params(signature_class: T.nilable(T.class_of(DSPy::Signature)), values: T::Hash[Symbol, T.untyped]).returns(String) }
      def render_expected_output(signature_class, values)
        Sorbet::Toon.encode(
          values,
          signature: signature_class,
          role: :output
        )
      end

      sig { params(signature_class: T.nilable(T.class_of(DSPy::Signature)), toon_string: String).returns(T.untyped) }
      def parse_output(signature_class, toon_string)
        payload = strip_code_fences(toon_string)

        Sorbet::Toon.decode(
          payload,
          signature: signature_class,
          role: :output
        )
      end

      sig { params(text: T.nilable(String)).returns(String) }
      def strip_code_fences(text)
        return '' if text.nil?

        match = text.match(/```(?:toon)?\s*(.*?)```/m)
        return match[1].strip if match

        text.strip
      end

      sig { params(signature_class: T.nilable(T.class_of(DSPy::Signature)), role: Symbol).returns(String) }
      def field_guidance(signature_class, role)
        return '' unless signature_class

        Sorbet::Toon::SignatureFormatter.describe_signature(signature_class, role)
      end
    end
  end
end
