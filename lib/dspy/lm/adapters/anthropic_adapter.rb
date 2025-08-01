# frozen_string_literal: true

require 'anthropic'

module DSPy
  class LM
    class AnthropicAdapter < Adapter
      def initialize(model:, api_key:)
        super
        validate_api_key!(api_key, 'anthropic')
        @client = Anthropic::Client.new(api_key: api_key)
      end

      def chat(messages:, signature: nil, **extra_params, &block)
        # Anthropic requires system message to be separate from messages
        system_message, user_messages = extract_system_message(normalize_messages(messages))
        
        # Check if this is a tool use request
        has_tools = extra_params.key?(:tools) && !extra_params[:tools].empty?
        
        # Apply JSON prefilling if needed for better Claude JSON compliance (but not for tool use)
        unless has_tools
          user_messages = prepare_messages_for_json(user_messages, system_message)
        end
        
        request_params = {
          model: model,
          messages: user_messages,
          max_tokens: 4096, # Required for Anthropic
          temperature: 0.0 # DSPy default for deterministic responses
        }.merge(extra_params)

        # Add system message if present
        request_params[:system] = system_message if system_message

        # Add streaming if block provided
        if block_given?
          request_params[:stream] = true
        end

        begin
          if block_given?
            content = ""
            @client.messages.stream(**request_params) do |chunk|
              if chunk.respond_to?(:delta) && chunk.delta.respond_to?(:text)
                chunk_text = chunk.delta.text
                content += chunk_text
                block.call(chunk)
              end
            end
            
            # Create typed metadata for streaming response
            metadata = ResponseMetadataFactory.create('anthropic', {
              model: model,
              streaming: true
            })
            
            Response.new(
              content: content,
              usage: nil, # Usage not available in streaming
              metadata: metadata
            )
          else
            response = @client.messages.create(**request_params)
            
            if response.respond_to?(:error) && response.error
              raise AdapterError, "Anthropic API error: #{response.error}"
            end

            # Handle both text content and tool use
            content = ""
            tool_calls = []
            
            if response.content.is_a?(Array)
              response.content.each do |content_block|
                case content_block.type.to_s
                when "text"
                  content += content_block.text
                when "tool_use"
                  tool_calls << {
                    id: content_block.id,
                    name: content_block.name,
                    input: content_block.input
                  }
                end
              end
            end
            
            usage = response.usage

            # Convert usage data to typed struct
            usage_struct = UsageFactory.create('anthropic', usage)
            
            metadata = {
              provider: 'anthropic',
              model: model,
              response_id: response.id,
              role: response.role
            }
            
            # Add tool calls to metadata if present
            metadata[:tool_calls] = tool_calls unless tool_calls.empty?
            
            # Create typed metadata
            typed_metadata = ResponseMetadataFactory.create('anthropic', metadata)
            
            Response.new(
              content: content,
              usage: usage_struct,
              metadata: typed_metadata
            )
          end
        rescue => e
          raise AdapterError, "Anthropic adapter error: #{e.message}"
        end
      end

      private

      # Enhanced JSON extraction specifically for Claude models
      # Handles multiple patterns of markdown-wrapped JSON responses
      def extract_json_from_response(content)
        return content if content.nil? || content.empty?
        
        # Pattern 1: ```json blocks
        if content.include?('```json')
          extracted = content[/```json\s*\n(.*?)\n```/m, 1]
          return extracted.strip if extracted
        end
        
        # Pattern 2: ## Output values header
        if content.include?('## Output values')
          extracted = content.split('## Output values').last
                            .gsub(/```json\s*\n/, '')
                            .gsub(/\n```.*/, '')
                            .strip
          return extracted if extracted && !extracted.empty?
        end
        
        # Pattern 3: Generic code blocks (check if it looks like JSON)
        if content.include?('```')
          extracted = content[/```\s*\n(.*?)\n```/m, 1]
          return extracted.strip if extracted && looks_like_json?(extracted)
        end
        
        # Pattern 4: Already valid JSON or fallback
        content.strip
      end

      # Simple heuristic to check if content looks like JSON
      def looks_like_json?(str)
        return false if str.nil? || str.empty?
        trimmed = str.strip
        (trimmed.start_with?('{') && trimmed.end_with?('}')) ||
        (trimmed.start_with?('[') && trimmed.end_with?(']'))
      end

      # Prepare messages for JSON output by adding prefilling and strong instructions
      def prepare_messages_for_json(user_messages, system_message)
        return user_messages unless requires_json_output?(user_messages, system_message)
        return user_messages unless tends_to_wrap_json?
        
        # Add strong JSON instruction to the last user message if not already present
        enhanced_messages = enhance_json_instructions(user_messages)
        
        # Only add prefill for models that support it and temporarily disable for testing
        if false # supports_prefilling? - temporarily disabled
          add_json_prefill(enhanced_messages)
        else
          enhanced_messages
        end
      end

      # Detect if the conversation requires JSON output
      def requires_json_output?(user_messages, system_message)
        # Check for JSON-related keywords in messages
        all_content = [system_message] + user_messages.map { |m| m[:content] }
        all_content.compact.any? do |content|
          content.downcase.include?('json') || 
          content.include?('```') ||
          content.include?('{') ||
          content.include?('output')
        end
      end

      # Check if this is a Claude model that benefits from prefilling
      def supports_prefilling?
        # Claude models that work well with JSON prefilling
        model.downcase.include?('claude')
      end

      # Check if this is a Claude model that tends to wrap JSON in markdown
      def tends_to_wrap_json?
        # All Claude models have this tendency, especially Opus variants
        model.downcase.include?('claude')
      end

      # Enhance the last user message with strong JSON instructions
      def enhance_json_instructions(user_messages)
        return user_messages if user_messages.empty?
        
        enhanced_messages = user_messages.dup
        last_message = enhanced_messages.last
        
        # Only add instruction if not already present
        unless last_message[:content].include?('ONLY valid JSON')
          # Use smart default instruction for Claude models
          json_instruction = "\n\nIMPORTANT: Respond with ONLY valid JSON. No markdown formatting, no code blocks, no explanations. Start your response with '{' and end with '}'."
          
          last_message = last_message.dup
          last_message[:content] = last_message[:content] + json_instruction
          enhanced_messages[-1] = last_message
        end
        
        enhanced_messages
      end

      # Add assistant message prefill to guide Claude
      def add_json_prefill(user_messages)
        user_messages + [{ role: "assistant", content: "{" }]
      end

      def extract_system_message(messages)
        system_message = nil
        user_messages = []

        messages.each do |msg|
          if msg[:role] == 'system'
            system_message = msg[:content]
          else
            user_messages << msg
          end
        end

        [system_message, user_messages]
      end
    end
  end
end
