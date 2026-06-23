---
layout: blog
title: "Making Structured Extraction More Reliable with Field Descriptions"
description: "Why field-level descriptions help Ruby LLM apps avoid valid-but-wrong structured extraction."
date: 2026-06-23
author: "Vicente Reig"
category: "Signatures"
reading_time: "5 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/making-structured-extraction-more-reliable-with-field-descriptions/"
image: /images/og/making-structured-extraction-more-reliable-with-field-descriptions.png
---

Structured extraction fails when the model fills the right field with the wrong meaning.

That is the annoying version of failure. The JSON is valid. The keys are present. The types pass. And the result is still quietly wrong, which is a terrible kind of wrong because it shows up later wearing a customer support ticket.

A production user recently asked whether field-level `description:` text in `DSPy::Signature` is officially supported: [GitHub issue #254](https://github.com/vicentereig/dspy.rb/issues/254). It is, and it matters more than it sounds, which is inconvenient because now the small question has become useful.

Field descriptions are exactly the kind of boring feature that matters once your LLM code leaves the demo phase and starts touching real business text. That is where the word "deadline" can mean an explicit cutoff date, a seasonal rule, a relative planning window, a late-application exception, or a polite little trap in paragraph seven.

In DSPy.rb, a signature is not just a list of field names and Ruby types. It is the contract between your application and the model. The type says what shape the answer must have. The field description says what the field actually means.

That distinction matters.

## Field Names Are Not Enough

Here is a compact extraction signature:

```ruby
class ProductExtraction < DSPy::Signature
  description "Extract structured product facts from source text."

  class Country < T::Enum
    enums do
      UnitedStates = new("US")
      Canada = new("CA")
      UnitedKingdom = new("GB")
      Australia = new("AU")
      Germany = new("DE")
    end
  end

  class ProductCategory < T::Enum
    enums do
      Grant = new("grant")
      Loan = new("loan")
      TaxCredit = new("tax_credit")
      Rebate = new("rebate")
      Certification = new("certification")
    end
  end

  input do
    const :source, String,
      description: "Source text to extract from. Use only facts stated or directly implied by this text."

    const :country, Country,
      description: "Country whose product rules should be applied."

    const :category, ProductCategory,
      description: "Product category to use when interpreting eligibility, timing, and application requirements."
  end

  output do
    const :application_deadline_note, T.nilable(String),
      description: "Application deadline info for this specific product. Include explicit cutoff dates, seasonal conditions, relative guidance, and exceptions. Keep concise and evidence-based."
  end
end
```

The enum types do useful work. They constrain `country` and `category` so your code does not have to interpret whatever the model felt like calling the United Kingdom that day. That is already a win.

But the field description does a different job. A field named `application_deadline_note` gets you part of the way there. It does not tell the model whether to include exceptions, relative guidance, seasonal conditions, late-application rules, or whether to stay grounded in the source text. The name points at the drawer. The description labels what is allowed inside.

That is what `description:` is for.

## Types Give Shape. Descriptions Give Meaning.

Structured extraction fails in two common ways.

The first is shape failure. The model gives you the wrong type, misses a field, invents a key, or returns JSON that looks like it was assembled during turbulence. Types and structured outputs help with that.

The second is meaning failure. The model returns valid structure, but the field does not mean what your application needs it to mean. This is sneakier because everything can pass validation while still being wrong.

For example:

```ruby
output do
  const :eligible_applicant_note, T.nilable(String),
    description: "Who can apply for this product. Include entity types, location requirements, exclusions, and conditional eligibility. Do not infer eligibility that is not grounded in the source text."

  const :excluded_items_note, T.nilable(String),
    description: "Items, costs, activities, or applicants explicitly excluded from this product. Return nil if the source does not mention exclusions."
end
```

Those descriptions are not decorative. They are where the domain rules live.

They tell the model what to include, what to exclude, how cautious to be, and what to do when the source is silent. Without them, you are asking the model to infer production semantics from a snake_case field name. That is not engineering. That is a trust fall with JSON.

## What DSPy.rb Does with Descriptions

DSPy.rb treats field descriptions as a first-class feature.

The `Signature` DSL captures `description:` into field metadata, carries it onto the generated `T::Struct`, and emits it through generated schemas. That means field descriptions can be used by prompt-rendered schemas, compact schema formats, and provider-native structured output paths where the provider supports that metadata.

The relevant implementation is intentionally plain:

- [`DSPy::Signature`](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/signature.rb) stores field descriptions and emits them through `input_json_schema`, `output_json_schema`, and `output_json_schema_with_defs`.
- [`DSPy::Ext::StructDescriptions`](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/ext/struct_descriptions.rb) supports `description:` on plain `T::Struct` `const` and `prop` fields too.
- The specs cover storing descriptions and emitting them into schemas.

This is not an accidental keyword that wandered in through an unlocked side door, looked around, and got a badge. It is part of the API surface.

## Where the Description Goes

The exact transport depends on provider and mode:

- Enhanced prompting with JSON schema renders descriptions into the prompt schema.
- [BAML schema format](/blog/articles/baml-schema-format/) preserves output descriptions as `@description(...)`.
- [TOON schema format](/blog/articles/toon-data-format/) includes descriptions in human-readable field guidance.
- OpenAI structured outputs receive descriptions through the generated JSON schema.
- Anthropic Beta structured outputs receive descriptions through the generated JSON schema.
- Gemini structured outputs use Gemini's supported schema subset. Descriptions remain part of DSPy metadata and prompt-based modes, but the provider-native Gemini schema path does not currently preserve every simple scalar or object field description in the final schema.

So the practical recommendation is still simple: write good field descriptions. Providers differ in how much native schema metadata they consume, but your DSPy signature remains the right place to express field semantics.

## How to Write Useful Field Descriptions

Good field descriptions are short, specific, and operational. They should tell the model how to behave when the field is not obvious.

Useful descriptions answer questions like:

- What should be included?
- What should be excluded?
- Should the model infer, or only extract?
- What should happen when the source is ambiguous?
- Should the answer be concise, exhaustive, normalized, or evidence-based?

Less useful:

```ruby
const :deadline, T.nilable(String),
  description: "The deadline"
```

More useful:

```ruby
const :deadline, T.nilable(String),
  description: "Application deadline stated in the source text. Include explicit dates, relative windows, seasonal rules, and exceptions. Return nil if no deadline is provided."
```

The second version gives the model a job. The first version gives it a shrug wearing a lanyard and asks everyone to act surprised when the output gets weird.

## The Small Habit That Pays Off

You do not need a wall of prompt text to make extraction more reliable. Often the best improvement is smaller and closer to the data contract:

```ruby
const :field_name, Type,
  description: "The exact semantics this field should carry."
```

Use the signature-level `description` for the overall task. Use field-level `description:` for the rules that belong to each field.

That is the habit. It is small, but it compounds. Your schemas become clearer. Your prompts become less mysterious. Your extraction code has fewer private assumptions hiding between the lines, where private assumptions go to become outages with good posture.

Write your field descriptions like you are explaining the field to a smart coworker who is new to the domain and has no patience for vibes.

Because, inconveniently, that is often the exact situation.
