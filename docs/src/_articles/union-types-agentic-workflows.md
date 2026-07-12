---
layout: blog
title: "Typed Action Results with Sorbet Union Types"
date: 2025-08-02
author: "Vicente Reig Rincon de Arellano"
description: "Use a single union-typed output when an LM must choose among several structured actions."
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/union-types-agentic-workflows/"
image: /images/og/union-types-agentic-workflows.png
---

An agent or router often needs to return one action from a closed set. Modeling every possible field as nilable moves the decision into application code and permits contradictory states. A union-typed output makes the alternatives explicit.

```ruby
module CoffeeShopActions
  class TakeOrder < T::Struct
    const :drink, String
    const :size, String
  end

  class HandleComplaint < T::Struct
    const :summary, String
    const :severity, Integer
  end

  class TellJoke < T::Struct
    const :topic, String
  end
end

class CoffeeShopSignature < DSPy::Signature
  description "Choose the next response for a coffee-shop request"

  input do
    const :request, String
  end

  output do
    const :action, T.any(
      CoffeeShopActions::TakeOrder,
      CoffeeShopActions::HandleComplaint,
      CoffeeShopActions::TellJoke
    )
  end
end
```

The signature says that `action` contains exactly one variant. Here, the predictor makes one typed decision. An agent adds a loop in which the model selects actions or tools over several steps.

## The Discriminator

DSPy.rb's JSON Schema converter represents struct unions with `anyOf`. Each variant includes a generated `_type` discriminator whose value is the struct's simple class name, without its enclosing module:

```json
{
  "action": {
    "_type": "TakeOrder",
    "drink": "flat white",
    "size": "small"
  }
}
```

`DSPy::Prediction` uses `_type` to select the struct class and removes fields that are not declared by that class before instantiation. Arrays of union values use the same conversion for each element.

```ruby
predictor = DSPy::Predict.new(CoffeeShopSignature)
result = predictor.call(request: "A small flat white, please")

case result.action
when CoffeeShopActions::TakeOrder
  submit_order(result.action.drink, result.action.size)
when CoffeeShopActions::HandleComplaint
  open_support_case(result.action.summary, result.action.severity)
when CoffeeShopActions::TellJoke
  tell_joke_about(result.action.topic)
end
```

If `_type` is absent, prediction conversion can fall back to structural matching. That fallback is less precise when variants share fields. Keep the discriminator in model responses whenever possible.

## Boundaries and Failure Modes

The union constrains the result shape. Application code must still judge whether the action is appropriate, authorize side effects, and decide whether to run the prediction inside an agent loop. Permissions, budgets, retries, and execution remain outside the type.

Use variants with distinct responsibilities and fields. If two structs have the same shape, the discriminator is the only reliable distinction. A user-defined `_type` property also conflicts with DSPy.rb's generated discriminator and raises during schema generation.

Union types fit routers, next-action decisions, tool results, and state transitions where the alternatives are known. Open-ended tool discovery or dynamic schemas need a different boundary.
