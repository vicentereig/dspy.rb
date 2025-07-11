# Improve Error Messages When LM is Not Configured

## Problem

When a DSPy module doesn't have an LM configured (either at the module level or globally), users get a confusing error:

```
NoMethodError: undefined method `model' for nil
```

This happens deep in the instrumentation helpers and doesn't clearly indicate what the actual problem is.

## Current Behavior

```ruby
module = MyModule.new
module.forward(input) # => NoMethodError in instrumentation_helpers.rb
```

The error occurs because `lm` returns nil when no LM is configured, and the instrumentation code tries to call `lm.model`.

## Proposed Solution

Add early validation in the module's forward method to check for LM configuration:

```ruby
def forward(...)
  raise DSPy::ConfigurationError, "No language model configured. Set one globally with DSPy.configure { |c| c.lm = ... } or on this module with module.configure { |c| c.lm = ... }" if lm.nil?
  
  # existing forward logic
end
```

## Benefits

1. **Clear error message** - Users immediately understand what's wrong
2. **Actionable advice** - The error tells them exactly how to fix it
3. **Early detection** - Fails fast before getting into instrumentation code
4. **Better developer experience** - Less debugging time

## Implementation Notes

- Add `DSPy::ConfigurationError` exception class
- Check in base `Module#forward` or in each module's forward method
- Consider adding similar checks in other methods that require LM
- Ensure the error message is helpful and includes examples

## Example Error Message

```
DSPy::ConfigurationError: No language model configured for SentimentAnalyzer module.

To fix this, configure a language model either globally:

  DSPy.configure do |config|
    config.lm = DSPy::LM.new("openai/gpt-4", api_key: ENV["OPENAI_API_KEY"])
  end

Or on the module instance:

  analyzer = SentimentAnalyzer.new
  analyzer.configure do |config|
    config.lm = DSPy::LM.new("anthropic/claude-3", api_key: ENV["ANTHROPIC_API_KEY"])
  end
```

This would significantly improve the developer experience when getting started with DSPy.rb.