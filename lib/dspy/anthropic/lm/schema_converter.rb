# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  module Anthropic
    module LM
      # Converts DSPy signatures to Anthropic Beta API structured output format
      module SchemaConverter
        extend T::Sig

        sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T::Hash[Symbol, T.untyped]) }
        def self.to_beta_format(signature_class)
          schema = signature_class.output_json_schema.except(:$schema)
          add_additional_properties_false(schema)
        end

        sig { params(schema: T.untyped).returns(T.untyped) }
        def self.add_additional_properties_false(schema)
          return schema unless schema.is_a?(Hash)

          result = schema.dup
          result[:additionalProperties] = false if result[:type] == "object"

          if result[:properties].is_a?(Hash)
            result[:properties] = result[:properties].transform_values do |v|
              add_additional_properties_false(v)
            end
          end

          if result[:items].is_a?(Hash)
            result[:items] = add_additional_properties_false(result[:items])
          end

          result
        end
      end
    end
  end
end
