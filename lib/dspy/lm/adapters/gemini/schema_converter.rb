# frozen_string_literal: true

require "sorbet-runtime"
require_relative "../../cache_manager"

module DSPy
  class LM
    module Adapters
      module Gemini
        # Converts DSPy signatures to Gemini structured output format
        class SchemaConverter
          extend T::Sig

          # Models that support structured outputs (JSON + Schema)
          # Based on official gemini-ai gem documentation table
          STRUCTURED_OUTPUT_MODELS = T.let([
            "gemini-1.5-pro",              # ✅ Full schema support
            "gemini-1.5-pro-preview-0514", # ✅ Full schema support  
            "gemini-1.5-pro-preview-0409"  # ✅ Full schema support
          ].freeze, T::Array[String])

          # Models that support JSON mode but NOT schema
          JSON_ONLY_MODELS = T.let([
            "gemini-pro",                   # 🟡 JSON only, no schema
            "gemini-1.5-flash",             # 🟡 JSON only, no schema
            "gemini-1.5-flash-preview-0514", # 🟡 JSON only, no schema
            "gemini-1.0-pro-002",           # 🟡 JSON only, no schema
            "gemini-1.0-pro"                # 🟡 JSON only, no schema
          ].freeze, T::Array[String])

          sig { params(signature_class: T.class_of(DSPy::Signature)).returns(T::Hash[Symbol, T.untyped]) }
          def self.to_gemini_format(signature_class)
            # Check cache first
            cache_manager = DSPy::LM.cache_manager
            cached_schema = cache_manager.get_schema(signature_class, "gemini", {})
            
            if cached_schema
              DSPy.logger.debug("Using cached schema for #{signature_class.name}")
              return cached_schema
            end
            
            # Get the output JSON schema from the signature class
            output_schema = signature_class.output_json_schema
            
            # Convert to Gemini format (OpenAPI 3.0 Schema subset - not related to OpenAI)
            gemini_schema = convert_dspy_schema_to_gemini(output_schema)
            
            # Cache the result
            cache_manager.cache_schema(signature_class, "gemini", gemini_schema, {})
            
            gemini_schema
          end

          sig { params(model: String).returns(T::Boolean) }
          def self.supports_structured_outputs?(model)
            # Check cache first
            cache_manager = DSPy::LM.cache_manager
            cached_result = cache_manager.get_capability(model, "structured_outputs")
            
            if !cached_result.nil?
              DSPy.logger.debug("Using cached capability check for #{model}")
              return cached_result
            end
            
            # Extract base model name without provider prefix
            base_model = model.sub(/^gemini\//, "")
            
            # Check if it's a supported model or a newer version
            result = STRUCTURED_OUTPUT_MODELS.any? { |supported| base_model.start_with?(supported) }
            
            # Cache the result
            cache_manager.cache_capability(model, "structured_outputs", result)
            
            result
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

          sig { params(dspy_schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
          def self.convert_dspy_schema_to_gemini(dspy_schema)
            # For Gemini's responseJsonSchema, we need pure JSON Schema format
            # Remove OpenAPI-specific fields like "$schema"
            result = {
              type: "object",
              properties: {},
              required: []
            }

            # Convert properties
            properties = dspy_schema[:properties] || {}
            properties.each do |prop_name, prop_schema|
              result[:properties][prop_name] = convert_property_to_gemini(prop_schema)
            end

            # Set required fields
            result[:required] = (dspy_schema[:required] || []).map(&:to_s)

            result
          end

          sig { params(property_schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
          def self.convert_property_to_gemini(property_schema)
            # Handle oneOf/anyOf schemas (union types) - Gemini supports these in responseJsonSchema
            if property_schema[:oneOf]
              return {
                oneOf: property_schema[:oneOf].map { |schema| convert_property_to_gemini(schema) },
                description: property_schema[:description]
              }.compact
            end
            
            if property_schema[:anyOf]
              return {
                anyOf: property_schema[:anyOf].map { |schema| convert_property_to_gemini(schema) },
                description: property_schema[:description]
              }.compact
            end
            
            case property_schema[:type]
            when "string"
              result = { type: "string" }
              result[:enum] = property_schema[:enum] if property_schema[:enum]
              result
            when "integer"
              { type: "integer" }
            when "number"
              { type: "number" }
            when "boolean"
              { type: "boolean" }
            when "array"
              {
                type: "array",
                items: convert_property_to_gemini(property_schema[:items] || { type: "string" })
              }
            when "object"
              result = { type: "object" }
              
              if property_schema[:properties]
                result[:properties] = {}
                property_schema[:properties].each do |nested_prop, nested_schema|
                  result[:properties][nested_prop] = convert_property_to_gemini(nested_schema)
                end
                
                # Set required fields for nested objects
                if property_schema[:required]
                  result[:required] = property_schema[:required].map(&:to_s)
                end
              end
              
              result
            else
              # Default to string for unknown types
              { type: "string" }
            end
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
end