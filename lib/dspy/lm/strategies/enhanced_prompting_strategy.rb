# frozen_string_literal: true

require_relative "base_strategy"

module DSPy
  class LM
    module Strategies
      # Enhanced prompting strategy that works with any LLM
      # Adds explicit JSON formatting instructions to improve reliability
      class EnhancedPromptingStrategy < BaseStrategy
        extend T::Sig

        sig { override.returns(T::Boolean) }
        def available?
          # This strategy is always available as a fallback
          true
        end

        sig { override.returns(Integer) }
        def priority
          50 # Medium priority - use when native methods aren't available
        end

        sig { override.returns(String) }
        def name
          "enhanced_prompting"
        end

        sig { override.params(messages: T::Array[T::Hash[Symbol, String]], request_params: T::Hash[Symbol, T.untyped]).void }
        def prepare_request(messages, request_params)
          # Enhance the user message with explicit JSON instructions
          return if messages.empty?

          # Get the output schema
          output_schema = signature_class.output_json_schema
          
          # Find the last user message
          last_user_idx = messages.rindex { |msg| msg[:role] == "user" }
          return unless last_user_idx

          # Add JSON formatting instructions
          original_content = messages[last_user_idx][:content]
          enhanced_content = enhance_prompt_with_json_instructions(original_content, output_schema)
          messages[last_user_idx][:content] = enhanced_content

          # Add system instructions if no system message exists
          if messages.none? { |msg| msg[:role] == "system" }
            messages.unshift({
              role: "system",
              content: "You are a helpful assistant that always responds with valid JSON when requested."
            })
          end
        end

        sig { override.params(response: DSPy::LM::Response).returns(T.nilable(String)) }
        def extract_json(response)
          return nil if response.content.nil?

          content = response.content.strip

          # Try multiple extraction patterns
          # 1. Check for markdown code blocks
          if content.include?('```json')
            json_content = content.split('```json').last.split('```').first.strip
            return json_content if valid_json?(json_content)
          elsif content.include?('```')
            code_block = content.split('```')[1]
            if code_block
              json_content = code_block.strip
              return json_content if valid_json?(json_content)
            end
          end

          # 2. Check if the entire response is JSON
          return content if valid_json?(content)

          # 3. Look for JSON-like structures in the content
          json_match = content.match(/\{[\s\S]*\}|\[[\s\S]*\]/)
          if json_match
            json_content = json_match[0]
            return json_content if valid_json?(json_content)
          end

          nil
        end

        private

        sig { params(prompt: String, schema: T::Hash[Symbol, T.untyped]).returns(String) }
        def enhance_prompt_with_json_instructions(prompt, schema)
          json_example = generate_example_from_schema(schema)
          
          <<~ENHANCED
            #{prompt}

            IMPORTANT: You must respond with valid JSON that matches this structure:
            ```json
            #{JSON.pretty_generate(json_example)}
            ```

            Required fields: #{schema[:required]&.join(', ') || 'none'}
            
            Ensure your response:
            1. Is valid JSON (properly quoted strings, no trailing commas)
            2. Includes all required fields
            3. Uses the correct data types for each field
            4. Is wrapped in ```json``` markdown code blocks
          ENHANCED
        end

        sig { params(schema: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
        def generate_example_from_schema(schema)
          return {} unless schema[:properties]

          example = {}
          schema[:properties].each do |field_name, field_schema|
            example[field_name.to_s] = generate_example_value(field_schema)
          end
          example
        end

        sig { params(field_schema: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
        def generate_example_value(field_schema)
          case field_schema[:type]
          when "string"
            field_schema[:description] || "example string"
          when "integer"
            42
          when "number"
            3.14
          when "boolean"
            true
          when "array"
            if field_schema[:items]
              [generate_example_value(field_schema[:items])]
            else
              ["example item"]
            end
          when "object"
            if field_schema[:properties]
              # Generate proper nested object example
              nested_example = {}
              field_schema[:properties].each do |prop_name, prop_schema|
                nested_example[prop_name.to_s] = generate_example_value(prop_schema)
              end
              nested_example
            else
              { "nested" => "object" }
            end
          when Array
            # Handle union types like ["object", "null"]
            if field_schema[:type].include?("object") && field_schema[:properties]
              nested_example = {}
              field_schema[:properties].each do |prop_name, prop_schema|
                nested_example[prop_name.to_s] = generate_example_value(prop_schema)
              end
              nested_example
            elsif field_schema[:type].include?("string")
              "example string"
            else
              "example value"
            end
          else
            "example value"
          end
        end

        sig { params(content: String).returns(T::Boolean) }
        def valid_json?(content)
          JSON.parse(content)
          true
        rescue JSON::ParserError
          false
        end
      end
    end
  end
end