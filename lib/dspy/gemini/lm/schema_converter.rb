# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  module Gemini
    module LM
      # Converts DSPy signatures to Gemini structured output format
      class SchemaConverter
        extend T::Sig

        # Models that support structured outputs (JSON + Schema)
        # Based on official Google documentation: https://ai.google.dev/gemini-api/docs/models/gemini
        # Last updated: Feb 2026
        # Note: Gemini 1.5 series deprecated Oct 2025
        STRUCTURED_OUTPUT_MODELS = T.let([
          # Gemini 2.0 series
          "gemini-2.0-flash",
          "gemini-2.0-flash-lite",
          # Gemini 2.5 series (current)
          "gemini-2.5-pro",
          "gemini-2.5-flash",
          "gemini-2.5-flash-lite",
          "gemini-2.5-flash-image",
          # Gemini 3.0 series
          "gemini-3-flash-preview"
        ].freeze, T::Array[String])

        # Models that do not support structured outputs or are deprecated
        UNSUPPORTED_MODELS = T.let([
          # Legacy Gemini 1.0 series
          "gemini-pro",
          "gemini-1.0-pro-002",
          "gemini-1.0-pro",
          # Deprecated Gemini 1.5 series (removed Oct 2025)
          "gemini-1.5-pro",
          "gemini-1.5-pro-preview-0514",
          "gemini-1.5-pro-preview-0409",
          "gemini-1.5-flash",
          "gemini-1.5-flash-8b"
        ].freeze, T::Array[String])

        sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T::Hash[Symbol, T.untyped]) }
        def self.to_gemini_format(signature_class)
          # Get the output JSON schema from the signature class
          output_schema = signature_class.output_json_schema

          # response_json_schema accepts JSON Schema, including nullable type arrays.
          convert_property_to_gemini(output_schema)
        end

        sig { params(model: String).returns(T::Boolean) }
        def self.supports_structured_outputs?(model)
          # Extract base model name without provider prefix
          base_model = model.sub(/^gemini\//, "")

          # Check if it's a supported model or a newer version
          STRUCTURED_OUTPUT_MODELS.any? { |supported| base_model.start_with?(supported) }
        end

        sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
        def self.validate_compatibility(schema)
          issues = []

          # Check for deeply nested objects (Gemini has depth limits)
          depth = calculate_depth(schema)
          if depth > 5
            issues << "Schema depth (#{depth}) exceeds recommended limit of 5 levels"
          end

          issues
        end

        private

        sig { params(property_schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def self.convert_property_to_gemini(property_schema)
          # Preserve types and constraints instead of rebuilding nodes from scalar
          # type names: Sorbet represents nilable fields as type: [type, "null"].
          result = property_schema.reject { |key, _| key == :"$schema" || key == :const }

          # Keep the existing const-to-enum conversion, including false/null values.
          result[:enum] = [property_schema[:const]] if property_schema.key?(:const)

          [:properties, :"$defs", :definitions].each do |key|
            if property_schema[key].is_a?(Hash)
              result[key] = property_schema[key].transform_values { |schema| convert_property_to_gemini(schema) }
            end
          end

          [:items, :additionalProperties].each do |key|
            if property_schema[key].is_a?(Hash)
              result[key] = convert_property_to_gemini(property_schema[key])
            end
          end

          [:oneOf, :anyOf, :allOf, :prefixItems].each do |key|
            if property_schema[key].is_a?(Array)
              result[key] = property_schema[key].map { |schema| convert_property_to_gemini(schema) }
            end
          end

          result
        end

        sig { params(schema: T::Hash[Symbol, T.untyped], current_depth: Integer).returns(Integer) }
        def self.calculate_depth(schema, current_depth = 0)
          return current_depth unless schema.is_a?(Hash)

          max_depth = current_depth

          # Check properties
          if schema[:properties].is_a?(Hash)
            schema[:properties].each_value do |prop|
              if prop.is_a?(Hash)
                prop_depth = calculate_depth(prop, current_depth + 1)
                max_depth = [max_depth, prop_depth].max
              end
            end
          end

          # Check array items
          if schema[:items].is_a?(Hash)
            items_depth = calculate_depth(schema[:items], current_depth + 1)
            max_depth = [max_depth, items_depth].max
          end

          max_depth
        end
      end
    end
  end
end
