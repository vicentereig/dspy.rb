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

          # Add additionalProperties: false to any object type
          result[:additionalProperties] = false if result[:type] == "object"

          # Process nested properties
          if result[:properties].is_a?(Hash)
            result[:properties] = result[:properties].transform_values do |v|
              add_additional_properties_false(v)
            end
          end

          # Process array items
          if result[:items].is_a?(Hash)
            result[:items] = add_additional_properties_false(result[:items])
          elsif result[:items].is_a?(Array)
            result[:items] = result[:items].map { |item| add_additional_properties_false(item) }
          end

          # Process oneOf, anyOf, allOf arrays
          [:oneOf, :anyOf, :allOf].each do |key|
            if result[key].is_a?(Array)
              result[key] = result[key].map { |item| add_additional_properties_false(item) }
            end
          end

          # Process definitions
          [:definitions, :$defs].each do |key|
            if result[key].is_a?(Hash)
              result[key] = result[key].transform_values { |v| add_additional_properties_false(v) }
            end
          end

          result
        end
      end
    end
  end
end
