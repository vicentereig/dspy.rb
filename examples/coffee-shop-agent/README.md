# Run the Coffee Shop Union-Type Example

This example sends four customer requests through a `DSPy::ChainOfThought` module. Each prediction returns one union-typed action, and Ruby pattern matching dispatches on the resulting `T::Struct`.

## Prerequisites

- a repository checkout with `bundle install` completed
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`; when both are present, the script uses Anthropic
- provider network access; the script makes four model calls

The script loads `.env` from the repository root. It also starts the configured New Relic and DSPy observability integrations, so review local telemetry configuration before running it.

## Run

From the repository root:

```bash
export OPENAI_API_KEY="your-key"
bundle exec ruby examples/coffee-shop-agent/coffee_shop_agent.rb
```

The command prints the prediction reasoning, the concrete action struct selected for each request, and a customer-facing response. Exact actions and wording vary by model.

## What the Type Boundary Does

The signature returns one of `MakeDrink`, `RefundOrder`, `CallManager`, or `Joke`. DSPy.rb uses the generated `_type` discriminator to reconstruct the declared struct, and Ruby handles each class explicitly.

This example does not execute real refunds, drinks, or manager calls. A union constrains result shape; an application must still authorize side effects, validate amounts and identifiers, and decide whether a model-selected action is appropriate.

## Failure Conditions

- The script exits when neither provider key is present.
- Provider, transport, structured-output, or validation errors can stop a request.
- The default Anthropic model can be overridden with `ANTHROPIC_MODEL`; choose a model available to the configured account.

See [Rich Types](https://oss.vicente.services/dspy.rb/advanced/complex-types/) for union schemas and [Custom Toolsets](https://oss.vicente.services/dspy.rb/advanced/custom-toolsets/) when an agent must invoke bounded operations.
