# JSON Extraction Strategies

DSPy.rb automatically selects the best way to extract JSON from LLM responses based on what provider you're using. This helps avoid those annoying JSON parsing errors.

## What it does

- Picks the best JSON extraction method automatically
- Uses native features when available (like OpenAI's structured outputs)
- Falls back to enhanced prompting when needed
- Lets you override the selection if you want

## Available Strategies

### 1. OpenAI Structured Output Strategy
**When it's used:** OpenAI models that support structured outputs (gpt-4o, gpt-4o-mini, gpt-4-turbo)  
**What it does:** Uses OpenAI's native feature that guarantees valid JSON

```ruby
lm = DSPy::LM.new('openai/gpt-4o-mini', structured_outputs: true)
```

This is the most reliable option when available - OpenAI literally won't return invalid JSON.

### 2. Anthropic Extraction Strategy  
**When it's used:** Any Anthropic model  
**What it does:** Uses the JSON extraction patterns that work best with Claude

```ruby
lm = DSPy::LM.new('anthropic/claude-3-haiku-20240307')
# Automatically selected - no configuration needed
```

Works well because it uses the same extraction logic as the Anthropic adapter.

### 3. Enhanced Prompting Strategy
**When it's used:** Everything else (or when other strategies aren't available)  
**What it does:** Adds clear JSON instructions to the prompt and tries multiple extraction patterns

```ruby
# Used automatically for models without special support
lm = DSPy::LM.new('openai/gpt-3.5-turbo')
```

This is the fallback - it works with any model by being very explicit about wanting JSON.

## How it picks a strategy

The selection is pretty straightforward:

1. If you manually set a strategy, it uses that
2. If you're using OpenAI with structured outputs enabled, it uses the OpenAI strategy  
3. If you're using Anthropic, it uses the Anthropic strategy
4. Otherwise, it uses enhanced prompting

That's it. Nothing fancy.

## Configuration

### Enabling Structured Outputs

For OpenAI models that support it:
```ruby
# Just add structured_outputs: true
lm = DSPy::LM.new('openai/gpt-4o-mini', 
                   api_key: api_key, 
                   structured_outputs: true)
```

### Forcing a specific strategy

If you want to override the automatic selection:
```ruby
DSPy.configure do |config|
  config.structured_outputs.strategy = 'enhanced_prompting'
end
```

Available strategies:
- `'openai_structured_output'` 
- `'anthropic_extraction'`
- `'enhanced_prompting'`
- `nil` (back to auto-select)

## How it works under the hood

Each strategy implements these methods:
- `available?` - Can this strategy be used with the current model?
- `prepare_request` - Modify the request before sending (add instructions, parameters, etc.)
- `extract_json` - Pull JSON out of the response
- `priority` - Higher number = preferred strategy

The system picks the highest priority strategy that's available for your model.

## Tips

### Use structured outputs when you can
If you're using a supported OpenAI model, enable structured outputs:
```ruby
lm = DSPy::LM.new('openai/gpt-4o-mini', structured_outputs: true)
```

It's more reliable than parsing JSON from text.

### Check which strategy is being used
Enable debug logging to see what's happening:
```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, level: :debug)
end
# Look for: "Selected JSON extraction strategy: ..."
```

### The enhanced prompting strategy is pretty smart
It can extract JSON from:
- Markdown code blocks (```json)
- Plain JSON responses
- JSON mixed with text
- Generic code blocks

So even the fallback strategy works well most of the time.

## What the tests verify

The test suite verifies that:
- OpenAI structured output strategy is selected when `structured_outputs: true`
- Anthropic extraction strategy is selected for Anthropic models
- Enhanced prompting is used as fallback
- Manual strategy override works
- JSON extraction works correctly for each strategy

See `spec/dspy/lm/strategy_selector_spec.rb` and `spec/integration/strategy_selection_integration_spec.rb` for the actual tests.

## Troubleshooting

### If the wrong strategy is being used
1. Check if your model supports the strategy you expect
2. Make sure `structured_outputs: true` is set for OpenAI
3. Enable debug logging to see what's happening
4. Try manually setting the strategy

### If JSON parsing still fails
The enhanced prompting strategy is pretty good, but if you're still getting parsing errors:
- Check that your signature has valid JSON schema
- Look at the actual response in the error message
- Try a different model (some are better at JSON than others)