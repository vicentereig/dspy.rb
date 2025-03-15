# frozen_string_literal: true
require 'ruby_llm'

module DSPy
  class LM
    attr_reader :model_id, :api_key, :model, :provider
    
    def initialize(model_id, api_key: nil)
      @model_id = model_id
      @api_key = api_key
      # Configure RubyLLM with the API key if provided
      if model_id.start_with?('openai/')
        RubyLLM.configure do |config|
          config.openai_api_key = api_key
        end
        @provider = :openai
        @model = model_id.split('/').last
      elsif model_id.start_with?('anthropic/')
        RubyLLM.configure do |config|
          config.anthropic_api_key = api_key
        end
        @provider = :anthropic
        @model = model_id.split('/').last
      else
        raise ArgumentError, "Unsupported model provider: #{model_id}"
      end
    end
    
    def generate(prompt, signature)
      chat = RubyLLM.chat(model: model)
      
      # Generate a system message that explains the task
      system_message = generate_system_prompt(signature)
      chat.ask(system_message)
      
      # Send the user prompt
      chat.ask(generate_user_prompt(prompt, signature))

      # Parse the response into the expected structure
      parse_response(chat.messages.last, signature)
    end
    
    private
    
    def generate_system_prompt(signature)
      instructions = signature.class.description
      
      # Add chain-of-thought specific instructions if needed
      if defined?(DSPy::ChainOfThought) && caller_locations.any? { |loc| loc.path.include?('chain_of_thought.rb') }
        instructions = "#{instructions}\n\nThink step by step to solve this problem. Break it down into parts, solve each part, and then combine the results to get the final answer."
      end
      
      output_fields_desc = signature.class.output_fields.map do |name, field|
        type_desc = field.type.is_a?(Array) ? field.type.join(', ') : field.type
        "#{name}: #{type_desc}"
      end.join("\n")
      
      <<~PROMPT
        You are an AI assistant that responds in JSON format.
        
        #{instructions}
        
        Format your response as a valid JSON object with these fields:
        #{output_fields_desc}
        
        If one of the fields is 'answer', make sure it contains the precise, concise final answer.
      PROMPT
    end
    
    def generate_user_prompt(input_values, signature)
      # Format the input values as a message
      input_desc = input_values.map { |k, v| "#{k}: #{v}" }.join("\n")
      
      <<~PROMPT
        Please analyze the following:
        
        #{input_desc}
        
        Respond with JSON only.
      PROMPT
    end
    
    def parse_response(response, signature)
      # Try to parse the response as JSON
      content = response.content
      
      # Extract JSON if it's in a code block
      if content.include?('```json')
        content = content.split('```json').last.split('```').first.strip
      elsif content.include?('```')
        content = content.split('```').last.split('```').first.strip
      end
      
      begin
        parsed = JSON.parse(content)
        
        # Convert keys to symbols
        parsed = parsed.transform_keys(&:to_sym)
        
        # Type conversion for specific output fields
        signature.class.output_fields.each do |name, field|
          if field.type == Float && parsed[name].is_a?(String)
            parsed[name] = parsed[name].to_f
          elsif field.type.is_a?(Array) && parsed[name].is_a?(String)
            parsed[name] = parsed[name].downcase.to_sym
          end
        end
        
        # Create a new instance with the parsed values
        signature.class.new_from_hash(parsed)
      rescue JSON::ParserError
        raise "Failed to parse LLM response as JSON: #{content}"
      end
    end
  end
end 