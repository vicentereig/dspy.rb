# frozen_string_literal: true

require "sorbet-runtime"

module DSPy
  module OpenAI
    module LM
      # Converts DSPy signatures to OpenAI structured output format
      class SchemaConverter
        extend T::Sig

        # Models that support structured outputs as of July 2025
        STRUCTURED_OUTPUT_MODELS = T.let([
          "gpt-4o-mini",
          "gpt-4o-2024-08-06",
          "gpt-4o",
          "gpt-4-turbo",
          "gpt-4-turbo-2024-04-09",
          "gpt-5",
          "gpt-5-pro",
          "gpt-5-mini",
          "gpt-5-nano",
          "gpt-5-2025-08-07"
        ].freeze, T::Array[String])

        sig { params(signature_class: T.class_of(DSPy::Signature), name: T.nilable(String), strict: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
        def self.to_openai_format(signature_class, name: nil, strict: true)
          # Get the output JSON schema from the signature class
          output_schema = signature_class.output_json_schema

          # Convert oneOf to anyOf where safe, or raise error for unsupported cases
          output_schema = convert_oneof_to_anyof_if_safe(output_schema)

          # Build the complete schema with OpenAI-specific modifications
          dspy_schema = {
            "$schema": "http://json-schema.org/draft-06/schema#",
            type: "object",
            properties: output_schema[:properties] || {},
            required: openai_required_fields(signature_class, output_schema)
          }

          # Generate a schema name if not provided
          schema_name = name || generate_schema_name(signature_class)

          # Remove the $schema field as OpenAI doesn't use it
          openai_schema = dspy_schema.except(:$schema)

          # Add additionalProperties: false for strict mode and fix nested struct schemas
          if strict
            openai_schema = add_additional_properties_recursively(openai_schema)
            openai_schema = fix_nested_struct_required_fields(openai_schema)
          end

          # Wrap in OpenAI's required format
          {
            type: "json_schema",
            json_schema: {
              name: schema_name,
              strict: strict,
              schema: openai_schema
            }
          }
        end

        # Convert oneOf to anyOf if safe (discriminated unions), otherwise raise error
        sig { params(schema: T.untyped).returns(T.untyped) }
        def self.convert_oneof_to_anyof_if_safe(schema)
          return schema unless schema.is_a?(Hash)

          result = schema.dup

          # Check if this schema has oneOf that we can safely convert
          if result[:oneOf]
            if all_have_discriminators?(result[:oneOf])
              # Safe to convert - discriminators ensure mutual exclusivity
              result[:anyOf] = result.delete(:oneOf).map { |s| convert_oneof_to_anyof_if_safe(s) }
            else
              # Unsafe conversion - raise error
              raise DSPy::UnsupportedSchemaError.new(
                "OpenAI structured outputs do not support oneOf schemas without discriminator fields. " \
                "The schema contains union types that cannot be safely converted to anyOf. " \
                "Please use enhanced_prompting strategy instead or add discriminator fields to union types."
              )
            end
          end

          # Recursively process nested schemas
          if result[:properties].is_a?(Hash)
            result[:properties] = result[:properties].transform_values { |v| convert_oneof_to_anyof_if_safe(v) }
          end

          if result[:items].is_a?(Hash)
            result[:items] = convert_oneof_to_anyof_if_safe(result[:items])
          end

          # Process arrays of schema items
          if result[:items].is_a?(Array)
            result[:items] = result[:items].map { |item| 
              item.is_a?(Hash) ? convert_oneof_to_anyof_if_safe(item) : item 
            }
          end

          # Process anyOf arrays (in case there are nested oneOf within anyOf)
          if result[:anyOf].is_a?(Array)
            result[:anyOf] = result[:anyOf].map { |item| 
              item.is_a?(Hash) ? convert_oneof_to_anyof_if_safe(item) : item 
            }
          end

          result
        end

        # Check if all schemas in a oneOf array have discriminator fields (const properties)
        sig { params(schemas: T::Array[T.untyped]).returns(T::Boolean) }
        def self.all_have_discriminators?(schemas)
          schemas.all? do |schema|
            next false unless schema.is_a?(Hash)
            next false unless schema[:properties].is_a?(Hash)

            # Check if any property has a const value (our discriminator pattern)
            schema[:properties].any? { |_, prop| prop.is_a?(Hash) && prop[:const] }
          end
        end

        sig { params(model: String).returns(T::Boolean) }
        def self.supports_structured_outputs?(model)
          # Extract base model name without provider prefix
          base_model = model.sub(/^openai\//, "")

          # Check if it's a supported model or a newer version
          STRUCTURED_OUTPUT_MODELS.any? { |supported| base_model.start_with?(supported) }
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

        # OpenAI structured outputs requires ALL properties to be in the required array
        # For T.nilable fields without defaults, we warn the user and mark as required
        sig { params(signature_class: T.class_of(DSPy::Signature), output_schema: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
        def self.openai_required_fields(signature_class, output_schema)
          all_properties = output_schema[:properties]&.keys || []
          original_required = output_schema[:required] || []

          # For OpenAI structured outputs, we need ALL properties to be required
          # but warn about T.nilable fields without defaults
          field_descriptors = signature_class.instance_variable_get(:@output_field_descriptors) || {}

          all_properties.each do |property_name|
            descriptor = field_descriptors[property_name.to_sym]

            # If field is not originally required and doesn't have a default
            if !original_required.include?(property_name.to_s) && descriptor && !descriptor.has_default
              DSPy.logger.warn(
                "OpenAI structured outputs: T.nilable field '#{property_name}' without default will be marked as required. " \
                "Consider adding a default value or using a different provider for optional fields."
              )
            end
          end

          # Return all properties as required (OpenAI requirement)
          all_properties.map(&:to_s)
        end

        # Fix nested struct schemas to include all properties in required array (OpenAI requirement)
        sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def self.fix_nested_struct_required_fields(schema)
          return schema unless schema.is_a?(Hash)

          result = schema.dup

          # If this is an object with properties, make all properties required
          if result[:type] == "object" && result[:properties].is_a?(Hash)
            all_property_names = result[:properties].keys.map(&:to_s)
            result[:required] = all_property_names unless result[:required] == all_property_names
          end

          # Process nested objects recursively
          if result[:properties].is_a?(Hash)
            result[:properties] = result[:properties].transform_values do |prop|
              if prop.is_a?(Hash)
                processed = fix_nested_struct_required_fields(prop)
                # Handle arrays with object items
                if processed[:type] == "array" && processed[:items].is_a?(Hash)
                  processed[:items] = fix_nested_struct_required_fields(processed[:items])
                end
                processed
              else
                prop
              end
            end
          end

          result
        end

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

          # Process anyOf/allOf (oneOf should be converted to anyOf by this point)
          [:anyOf, :allOf].each do |key|
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

          # Check anyOf/allOf (oneOf should be converted to anyOf by this point)
          [:anyOf, :allOf].each do |key|
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

          # Recursively check nested schemas (oneOf should be converted to anyOf by this point)
          [:properties, :items, :anyOf, :allOf].each do |key|
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

          # Recursively check nested schemas (oneOf should be converted to anyOf by this point) 
          [:properties, :items, :anyOf, :allOf].each do |key|
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
