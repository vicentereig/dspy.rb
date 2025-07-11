# frozen_string_literal: true

require "sorbet-runtime"
require_relative "../../cache_manager"

module DSPy
  class LM
    module Adapters
      module OpenAI
        # Converts DSPy signatures to OpenAI structured output format
        class SchemaConverter
          extend T::Sig

          # Models that support structured outputs as of July 2025
          STRUCTURED_OUTPUT_MODELS = T.let([
            "gpt-4o-mini",
            "gpt-4o-2024-08-06",
            "gpt-4o",
            "gpt-4-turbo",
            "gpt-4-turbo-2024-04-09"
          ].freeze, T::Array[String])

          sig { params(signature_class: T.class_of(DSPy::Signature), name: T.nilable(String), strict: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
          def self.to_openai_format(signature_class, name: nil, strict: true)
            # Build cache params from the method parameters
            cache_params = { strict: strict }
            cache_params[:name] = name if name
            
            # Check cache first
            cache_manager = DSPy::LM.cache_manager
            cached_schema = cache_manager.get_schema(signature_class, "openai", cache_params)
            
            if cached_schema
              DSPy.logger.debug("Using cached schema for #{signature_class.name}")
              return cached_schema
            end
            
            # Get the output JSON schema from the signature class
            output_schema = signature_class.output_json_schema
            
            # Build the complete schema
            dspy_schema = {
              "$schema": "http://json-schema.org/draft-06/schema#",
              type: "object",
              properties: output_schema[:properties] || {},
              required: output_schema[:required] || []
            }

            # Generate a schema name if not provided
            schema_name = name || generate_schema_name(signature_class)

            # Remove the $schema field as OpenAI doesn't use it
            openai_schema = dspy_schema.except(:$schema)

            # Add additionalProperties: false for strict mode
            if strict
              openai_schema = add_additional_properties_recursively(openai_schema)
            end

            # Wrap in OpenAI's required format
            result = {
              type: "json_schema",
              json_schema: {
                name: schema_name,
                strict: strict,
                schema: openai_schema
              }
            }
            
            # Cache the result with same params
            cache_manager.cache_schema(signature_class, "openai", result, cache_params)
            
            result
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
            base_model = model.sub(/^openai\//, "")
            
            # Check if it's a supported model or a newer version
            result = STRUCTURED_OUTPUT_MODELS.any? { |supported| base_model.start_with?(supported) }
            
            # Cache the result
            cache_manager.cache_capability(model, "structured_outputs", result)
            
            result
          end

          sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
          def self.validate_compatibility(schema)
            issues = []

            # Check for deeply nested objects (OpenAI has depth limits)
            depth = calculate_depth(schema)
            if depth > 5
              issues << "Schema depth (#{depth}) exceeds recommended limit of 5 levels"
            end

            # Check for unsupported JSON Schema features
            if contains_pattern_properties?(schema)
              issues << "Pattern properties are not supported in OpenAI structured outputs"
            end

            if contains_conditional_schemas?(schema)
              issues << "Conditional schemas (if/then/else) are not supported"
            end

            issues
          end

          private

          sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
          def self.add_additional_properties_recursively(schema)
            return schema unless schema.is_a?(Hash)
            
            result = schema.dup
            
            # Add additionalProperties: false if this is an object
            if result[:type] == "object"
              result[:additionalProperties] = false
            end
            
            # Process properties recursively
            if result[:properties].is_a?(Hash)
              result[:properties] = result[:properties].transform_values do |prop|
                if prop.is_a?(Hash)
                  processed = add_additional_properties_recursively(prop)
                  # Special handling for arrays - ensure their items have additionalProperties if they're objects
                  if processed[:type] == "array" && processed[:items].is_a?(Hash)
                    processed[:items] = add_additional_properties_recursively(processed[:items])
                  end
                  processed
                else
                  prop
                end
              end
            end
            
            # Process array items
            if result[:items].is_a?(Hash)
              processed_items = add_additional_properties_recursively(result[:items])
              # OpenAI requires additionalProperties on all objects, even in array items
              if processed_items.is_a?(Hash) && processed_items[:type] == "object" && !processed_items.key?(:additionalProperties)
                processed_items[:additionalProperties] = false
              end
              result[:items] = processed_items
            elsif result[:items].is_a?(Array)
              # Handle tuple validation
              result[:items] = result[:items].map do |item|
                processed = item.is_a?(Hash) ? add_additional_properties_recursively(item) : item
                if processed.is_a?(Hash) && processed[:type] == "object" && !processed.key?(:additionalProperties)
                  processed[:additionalProperties] = false
                end
                processed
              end
            end
            
            # Process oneOf/anyOf/allOf
            [:oneOf, :anyOf, :allOf].each do |key|
              if result[key].is_a?(Array)
                result[key] = result[key].map do |sub_schema|
                  sub_schema.is_a?(Hash) ? add_additional_properties_recursively(sub_schema) : sub_schema
                end
              end
            end
            
            result
          end

          sig { params(signature_class: T.class_of(DSPy::Signature)).returns(String) }
          def self.generate_schema_name(signature_class)
            # Use the signature class name
            class_name = signature_class.name&.split("::")&.last
            if class_name
              class_name.gsub(/[^a-zA-Z0-9_]/, "_").downcase
            else
              # Fallback to a generic name
              "dspy_output_#{Time.now.to_i}"
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

            # Check oneOf/anyOf/allOf
            [:oneOf, :anyOf, :allOf].each do |key|
              if schema[key].is_a?(Array)
                schema[key].each do |sub_schema|
                  if sub_schema.is_a?(Hash)
                    sub_depth = calculate_depth(sub_schema, current_depth + 1)
                    max_depth = [max_depth, sub_depth].max
                  end
                end
              end
            end

            max_depth
          end

          sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
          def self.contains_pattern_properties?(schema)
            return true if schema[:patternProperties]

            # Recursively check nested schemas
            [:properties, :items, :oneOf, :anyOf, :allOf].each do |key|
              value = schema[key]
              case value
              when Hash
                return true if contains_pattern_properties?(value)
              when Array
                return true if value.any? { |v| v.is_a?(Hash) && contains_pattern_properties?(v) }
              end
            end

            false
          end

          sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
          def self.contains_conditional_schemas?(schema)
            return true if schema[:if] || schema[:then] || schema[:else]

            # Recursively check nested schemas
            [:properties, :items, :oneOf, :anyOf, :allOf].each do |key|
              value = schema[key]
              case value
              when Hash
                return true if contains_conditional_schemas?(value)
              when Array
                return true if value.any? { |v| v.is_a?(Hash) && contains_conditional_schemas?(v) }
              end
            end

            false
          end
        end
      end
    end
  end
end