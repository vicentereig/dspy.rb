# Coffee Shop Agent Example

This example demonstrates DSPy.rb's single-field union types feature, showing how to build an AI agent that can take different actions based on customer requests.

## What it Shows

- **Single-field union types**: Using `T.any()` with automatic type detection
- **No discriminator fields needed**: DSPy automatically handles the `_type` field
- **Pattern matching on results**: Clean handling of different action types
- **Real-world agent pattern**: Making decisions based on context

## Running the Example

1. Set your API key:
   ```bash
   export ANTHROPIC_API_KEY=your-key-here
   # or
   export OPENAI_API_KEY=your-key-here
   ```

2. Run the agent:
   ```bash
   ruby coffee_shop_agent.rb
   ```

## How it Works

The agent demonstrates single-field union types by:

1. **Defining focused action structs** - Each action type (MakeDrink, RefundOrder, etc.) has only the fields it needs
2. **Using a single `T.any()` field** - The signature has one `action` field that can be any of the action types
3. **Automatic type detection** - DSPy adds the `_type` field during serialization and uses it for deserialization
4. **Pattern matching** - The result contains the properly typed action struct

## Key Benefits

- **No nil checks**: Each action struct only has the fields it needs
- **Type safety**: Pattern matching ensures you handle each action type correctly
- **Clean code**: No discriminator enums or manual type checking needed
- **Automatic conversion**: LLM JSON responses are automatically converted to the correct struct type

## Example Output

```
Welcome to the AI Coffee Shop! 🤖☕

🧠 Reasoning: The customer is asking for a specific coffee drink with customizations...

☕ Taking action...
Making a large iced latte
Customizations: oat milk, extra shot

💬 Response to customer: Coming right up! One large iced latte with oat milk and an extra shot. That'll be ready in about 3 minutes!

============================================================

🧠 Reasoning: The customer is upset about both the taste and wait time...

☕ Taking action...
📞 Calling manager about: Customer complaint about coffee quality and long wait time
Urgency: high

💬 Response to customer: I'm so sorry about that! Let me get my manager right away to help resolve this for you.

============================================================
```

## Learn More

- [Blog post about union types](https://dspy-rb.vicente.io/blog/union-types-agentic-workflows/)
- [Complex types documentation](https://dspy-rb.vicente.io/advanced/complex-types/)
- [DSPy.rb repository](https://github.com/vicentereig/dspy.rb)