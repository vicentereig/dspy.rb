---
layout: blog
title: "Under the Hood: How DSPy.rb Extracts JSON from Every LLM"
date: 2025-07-25
description: "A technical deep-dive into DSPy.rb's multi-strategy JSON extraction system, showing exactly how it handles OpenAI, Anthropic, and other providers"
author: "Vicente Reig"
draft: true
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/under-the-hood-json-extraction/"
---

DSPy.rb uses 4 different strategies to extract JSON from LLMs. Here's how each one works.

When you call `predict.forward()`, DSPy.rb picks the best strategy for your LLM provider. Each strategy is designed to get reliable JSON output from different models.

## How Strategy Selection Works

DSPy.rb ranks strategies by priority and picks the best one available:

```ruby
# From lib/dspy/lm/strategy_selector.rb
STRATEGIES = [
  Strategies::OpenAIStructuredOutputStrategy,     # Priority: 100
  Strategies::AnthropicToolUseStrategy,          # Priority: 95
  Strategies::AnthropicExtractionStrategy,       # Priority: 90
  Strategies::EnhancedPromptingStrategy          # Priority: 50
].freeze
```

The selector checks your LLM provider and model, then uses the highest-priority strategy that works:

```ruby
def select
  # Allow manual override via configuration
  if DSPy.config.structured_outputs.strategy
    # ... handle manual selection
  end

  # Select the highest priority available strategy
  available_strategies = @strategies.select(&:available?)
  selected = available_strategies.max_by(&:priority)
  
  DSPy.logger.debug("Selected JSON extraction strategy: #{selected.name}")
  selected
end
```

## OpenAI: Native Structured Outputs (Priority 100)

For OpenAI models that support structured outputs (GPT-4o, GPT-4o-mini), DSPy.rb uses OpenAI's built-in JSON feature:

```ruby
# What DSPy.rb sends to OpenAI
request_params[:response_format] = {
  type: "json_schema",
  json_schema: {
    name: "ProductExtractor",
    strict: true,
    schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        price: { type: "number" },
        in_stock: { type: "boolean" }
      },
      required: ["name", "price", "in_stock"],
      additionalProperties: false
    }
  }
}
```

This guarantees valid JSON - OpenAI's API won't return invalid JSON when using structured outputs. The schema converter handles complex Ruby types:

```ruby
# Converts T::Array[String] to JSON Schema
when T::Types::TypedArray
  {
    type: "array",
    items: type_to_json_schema(type_info.type)
  }
```

## Anthropic: Two Ways to Get JSON

### Tool Use Strategy (Priority 95)

DSPy.rb uses Anthropic's tool calling feature to get structured JSON:

```ruby
# From anthropic_tool_use_strategy.rb
def prepare_request(messages, request_params)
  # Convert signature to tool schema
  tool_schema = {
    name: "json_output",
    description: "Output the result in the required JSON format",
    input_schema: {
      type: "object",
      properties: build_properties_from_schema(output_schema),
      required: output_schema.keys.map(&:to_s)
    }
  }
  
  request_params[:tools] = [tool_schema]
  request_params[:tool_choice] = {
    type: "tool",
    name: "json_output"
  }
end
```

The response comes back with the JSON in a structured format:

```ruby
# Extract JSON from tool use response
if response.metadata[:tool_calls]
  first_call = response.metadata[:tool_calls].first
  if first_call[:name] == "json_output"
    return JSON.generate(first_call[:input])
  end
end
```

### 4-Pattern Extraction Strategy (Priority 90)

When tool use isn't available, DSPy.rb uses 4 patterns to extract JSON from Claude's responses:

```ruby
# From anthropic_adapter.rb
def extract_json_from_response(content)
  # Pattern 1: Look for ```json blocks
  if content.include?('```json')
    extracted = content[/```json\s*\n(.*?)\n```/m, 1]
    return extracted.strip if extracted
  end
  
  # Pattern 2: Look for ## Output values header
  if content.include?('## Output values')
    extracted = content.split('## Output values').last
                      .gsub(/```json\s*\n/, '')
                      .gsub(/\n```.*/, '')
                      .strip
    return extracted if extracted && !extracted.empty?
  end
  
  # Pattern 3: Check generic code blocks
  if content.include?('```')
    extracted = content[/```\s*\n(.*?)\n```/m, 1]
    return extracted.strip if extracted && looks_like_json?(extracted)
  end
  
  # Pattern 4: Already valid JSON
  content.strip
end
```

The adapter also adds special instructions for Claude:

```ruby
# Special instruction added to Claude prompts
json_instruction = "\n\nIMPORTANT: Respond with ONLY valid JSON. " \
                  "No markdown formatting, no code blocks, no explanations. " \
                  "Start your response with '{' and end with '}'."
```

## Enhanced Prompting: Works with Any Model (Priority 50)

For models without native JSON support, DSPy.rb adds clear instructions to the prompt:

```ruby
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
```

The extraction then tries multiple patterns:

```ruby
# Try markdown blocks first
if content.include?('```json')
  json_content = content.split('```json').last.split('```').first.strip
  return json_content if valid_json?(json_content)
end

# Check if entire response is JSON
return content if valid_json?(content)

# Look for JSON-like structures
json_match = content.match(/\{[\s\S]*\}|\[[\s\S]*\]/)
```

## Real Examples: What Each Provider Receives

Here's what happens when you use the same DSPy signature with different providers:

```ruby
class ProductExtractor < DSPy::Signature
  input { const :description, String }
  output do
    const :name, String
    const :price, Float
  end
end
```

### OpenAI Request:
```json
{
  "model": "gpt-4o-mini",
  "messages": [{"role": "user", "content": "Extract: iPhone 15 Pro - $999"}],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "ProductExtractor",
      "strict": true,
      "schema": { /* full schema */ }
    }
  }
}
```

### Anthropic with Tool Use:
```json
{
  "model": "claude-3-sonnet",
  "messages": [{"role": "user", "content": "Extract: iPhone 15 Pro - $999\n\nPlease use the json_output tool to provide your response."}],
  "tools": [{
    "name": "json_output",
    "input_schema": { /* schema */ }
  }],
  "tool_choice": {"type": "tool", "name": "json_output"}
}
```

### Anthropic with Extraction:
```json
{
  "model": "claude-3-haiku",
  "messages": [{
    "role": "user", 
    "content": "Extract: iPhone 15 Pro - $999\n\nIMPORTANT: Respond with ONLY valid JSON..."
  }]
}
```

## Behind the Scenes

### Retry Logic

DSPy.rb tries multiple times if JSON extraction fails:

```ruby
# From retry_handler.rb
def execute_with_retry
  @strategies.each do |strategy|
    @attempt = 0
    while @attempt < max_attempts
      @attempt += 1
      
      begin
        # Try the strategy
        result = execute_strategy(strategy)
        return result if result
      rescue => e
        # Handle specific errors
        if strategy.handle_error(e)
          # Strategy handled it, try next strategy
          break
        end
        # Otherwise retry with backoff
      end
    end
  end
end
```

### Performance Optimizations

DSPy.rb caches schemas and capability checks to speed things up:

```ruby
# Schema caching (1 hour TTL)
cache_manager = DSPy::LM.cache_manager
cached_schema = cache_manager.get_schema(signature_class, "openai", cache_params)

if cached_schema
  DSPy.logger.debug("Using cached schema for #{signature_class.name}")
  return cached_schema
end

# Capability caching (24 hour TTL) 
cached_result = cache_manager.get_capability(model, "structured_outputs")

if !cached_result.nil?
  DSPy.logger.debug("Using cached capability check for #{model}")
  return cached_result
end

# Check and cache the result
result = STRUCTURED_OUTPUT_MODELS.any? { |supported| base_model.start_with?(supported) }
cache_manager.cache_capability(model, "structured_outputs", result)
```

## Try It Yourself

Want to see which strategy your setup uses? Enable debug logging:

```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, level: :debug)
end

lm = DSPy::LM.new("openai/gpt-4o-mini", 
                  api_key: ENV["OPENAI_API_KEY"],
                  structured_outputs: true)

# Watch the logs to see:
# "Selected JSON extraction strategy: openai_structured_output"
```

Or inspect the strategy directly:

```ruby
strategy_selector = DSPy::LM::StrategySelector.new(lm.adapter, MySignature)
strategy = strategy_selector.select
puts "Using strategy: #{strategy.name} (priority: #{strategy.priority})"
```

## Key Takeaways

DSPy.rb's multi-strategy approach makes JSON extraction work reliably across all major LLMs. Understanding these details helps you:

- Pick the right model for JSON tasks
- Debug extraction problems faster
- Configure strategies for your needs
- Contribute improvements to the project

The best part? You don't need to worry about any of this complexity. Just define your signature and call `forward()` - DSPy.rb does the rest.

---

*Want to dive deeper? Check out the source code or join the discussion on GitHub.*