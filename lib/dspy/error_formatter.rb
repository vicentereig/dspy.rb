# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  # Utility class for formatting complex error messages into human-readable format
  class ErrorFormatter
    extend T::Sig

    # Main entry point for formatting errors
    sig { params(error_message: String, context: T.nilable(String)).returns(String) }
    def self.format_error(error_message, context = nil)
      # Try different error patterns in order of specificity
      if sorbet_type_error?(error_message)
        format_sorbet_type_error(error_message)
      elsif argument_error?(error_message)
        format_argument_error(error_message)
      else
        # Fallback to original message with minor cleanup
        clean_error_message(error_message)
      end
    end

    private

    # Check if this is a Sorbet runtime type validation error
    sig { params(message: String).returns(T::Boolean) }
    def self.sorbet_type_error?(message)
      message.match?(/Can't set \.(\w+) to .* \(instance of (\w+)\) - need a (.+)/)
    end

    # Check if this is an ArgumentError (missing required fields, etc.)
    sig { params(message: String).returns(T::Boolean) }
    def self.argument_error?(message)
      message.match?(/missing keyword/i) || message.match?(/unknown keyword/i)
    end

    # Format Sorbet type validation errors
    sig { params(message: String).returns(String) }
    def self.format_sorbet_type_error(message)
      # Parse the Sorbet error pattern
      match = message.match(/Can't set \.(\w+) to (.+?) \(instance of (\w+)\) - need a (.+?)(?:\n|$)/)
      return clean_error_message(message) unless match

      field_name = match[1]
      raw_value = match[2]
      actual_type = match[3]
      expected_type = match[4]

      # Extract sample data for display (truncate if too long)
      sample_data = if raw_value.length > 100
        "#{raw_value[0..100]}..."
      else
        raw_value
      end

      <<~ERROR.strip
        Type Mismatch in '#{field_name}'

        Expected: #{expected_type}
        Received: #{actual_type} (plain Ruby #{actual_type.downcase})

        #{generate_type_specific_explanation(actual_type, expected_type)}

        Suggestions:
        #{generate_suggestions(field_name, actual_type, expected_type)}

        Sample data received: #{sample_data}
      ERROR
    end

    # Format ArgumentError messages (missing/unknown keywords)
    sig { params(message: String).returns(String) }
    def self.format_argument_error(message)
      if message.match(/missing keyword: (.+)/i)
        missing_fields = $1.split(', ')
        format_missing_fields_error(missing_fields)
      elsif message.match(/unknown keyword: (.+)/i)
        unknown_fields = $1.split(', ')
        format_unknown_fields_error(unknown_fields)
      else
        clean_error_message(message)
      end
    end

    # Format missing required fields error
    sig { params(fields: T::Array[String]).returns(String) }
    def self.format_missing_fields_error(fields)
      field_list = fields.map { |f| "• #{f}" }.join("\n")
      
      <<~ERROR.strip
        Missing Required Fields

        The following required fields were not provided:
        #{field_list}

        Suggestions:
        • Check your signature definition - these fields should be marked as optional if they're not always provided
        • Ensure your LLM prompt asks for all required information
        • Consider providing default values in your signature

        This usually happens when the LLM response doesn't include all expected fields.
      ERROR
    end

    # Format unknown fields error
    sig { params(fields: T::Array[String]).returns(String) }
    def self.format_unknown_fields_error(fields)
      field_list = fields.map { |f| "• #{f}" }.join("\n")
      
      <<~ERROR.strip
        Unknown Fields in Response

        The LLM response included unexpected fields:
        #{field_list}

        Suggestions:
        • Check if these fields should be added to your signature definition
        • Review your prompt to ensure it only asks for expected fields
        • Consider if the LLM is hallucinating extra information

        Extra fields are ignored, but this might indicate a prompt or signature mismatch.
      ERROR
    end

    # Generate type-specific explanations
    sig { params(actual_type: String, expected_type: String).returns(String) }
    def self.generate_type_specific_explanation(actual_type, expected_type)
      case actual_type
      when 'Array'
        if expected_type.match(/T::Array\[(.+)\]/)
          struct_type = $1
          "The LLM returned a plain Ruby array with hash elements, but your signature requires an array of #{struct_type} struct objects."
        else
          "The LLM returned a #{actual_type}, but your signature requires #{expected_type}."
        end
      when 'Hash'
        if expected_type != 'Hash' && !expected_type.include?('T::Hash')
          "The LLM returned a plain Ruby hash, but your signature requires a #{expected_type} struct object."
        else
          "The LLM returned a #{actual_type}, but your signature requires #{expected_type}."
        end
      when 'String'
        if expected_type.include?('T::Enum')
          "The LLM returned a string, but your signature requires an enum value."
        else
          "The LLM returned a #{actual_type}, but your signature requires #{expected_type}."
        end
      else
        "The LLM returned a #{actual_type}, but your signature requires #{expected_type}."
      end
    end

    # Generate field and type-specific suggestions
    sig { params(field_name: String, actual_type: String, expected_type: String).returns(String) }
    def self.generate_suggestions(field_name, actual_type, expected_type)
      suggestions = []
      
      # Type-specific suggestions
      case actual_type
      when 'Array'
        if expected_type.match(/T::Array\[(.+)\]/)
          struct_type = $1
          suggestions << "Check your signature uses proper T::Array[#{struct_type}] typing"
          suggestions << "Verify the LLM response format matches your expected structure"
          suggestions << "Ensure your struct definitions are correct and accessible"
        else
          suggestions << "Check your signature definition for the '#{field_name}' field"
          suggestions << "Verify the LLM prompt asks for the correct data type"
        end
      when 'Hash'
        if expected_type != 'Hash' && !expected_type.include?('T::Hash')
          suggestions << "Check your signature uses proper #{expected_type} typing"
          suggestions << "Verify the LLM response contains the expected fields"
        else
          suggestions << "Check your signature definition for the '#{field_name}' field"
          suggestions << "Verify the LLM prompt asks for the correct data type"
        end
      when 'String'
        if expected_type.include?('T::Enum')
          suggestions << "Check your enum definition and available values"
          suggestions << "Ensure your prompt specifies valid enum options"
        else
          suggestions << "Check your signature definition for the '#{field_name}' field"
          suggestions << "Verify the LLM prompt asks for the correct data type"
        end
      else
        suggestions << "Check your signature definition for the '#{field_name}' field"
        suggestions << "Verify the LLM prompt asks for the correct data type"
      end
      
      # General suggestions
      suggestions << "Consider if your prompt needs clearer type instructions"
      suggestions << "Check if the LLM model supports structured output for complex types"
      
      suggestions.map { |s| "• #{s}" }.join("\n")
    end

    # Clean up error messages by removing internal stack traces and formatting
    sig { params(message: String).returns(String) }
    def self.clean_error_message(message)
      # Remove caller information that's not useful to end users
      cleaned = message.gsub(/\nCaller:.*$/m, '')
      
      # Remove excessive newlines and clean up formatting
      cleaned.gsub(/\n+/, "\n").strip
    end
  end
end