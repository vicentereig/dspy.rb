---
layout: blog
title: "What TOON Gets That CSV Doesn’t for LLM Payloads"
date: 2025-11-15
description: "Token-Oriented Object Notation keeps your nested Sorbet structs intact—something flat CSV rows simply can’t do when you prompt large language models."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/toon-vs-csv-nested-relationships/"
image: /images/og/toon-vs-csv-nested-relationships.png
reading_time: "3 min read"
---

CSV is phenomenal for spreadsheets and OLAP imports, but it breaks down the moment you try to express nested relationships in an LLM prompt. Token-Oriented Object Notation (TOON)[^1] keeps the structural cues that Sorbet signatures describe—arrays of structs, nested arrays, enums—without reprinting every JSON key. The new unit spec in [`spec/sorbet/toon/books_serialization_spec.rb`](https://github.com/vicentereig/dspy.rb/blob/main/spec/sorbet/toon/books_serialization_spec.rb) captures a concrete example: a catalog of books, each with its own list of authors.

## Rich types, zero prompt glue

DSPy.rb leans on Sorbet runtime types so you can model prompts like regular functions—define input parameters and return values, and let the serializers do the dirty work. Here’s a classic “book has many authors” relationship straight out of the spec:

```ruby
class Author < T::Struct
  prop :name, String
  prop :notable_work, String
end

class Book < T::Struct
  prop :title, String
  prop :published_year, Integer
  prop :authors, T::Array[Author]
end
```

## The TOON payload (as recorded in the spec)

```text
catalog[2]:
  - title: Distributed Systems
    published_year: 2014
    authors[2]{name,notable_work}:
      Leslie Lamport,Paxos
      Nancy Lynch,FLP result
  - title: Programming Languages
    published_year: 2003
    authors[1]{name,notable_work}:
      Benjamin Pierce,TAPL
```

Why this matters:

- **Row grouping stays explicit.** `authors[2]{name,notable_work}` tells the model it is about to read a two-row table, not a comma-delimited blob.
- **Type hints survive.** Because we rendered the payload via `Sorbet::Toon.encode`, both arrays know their element type (authors vs. books) without repeating keys.
- **Decoder fidelity.** `Sorbet::Toon.decode` rebuilds the same nested hash/struct graph, so `Predict` can return `Book` objects without any CSV parsing heuristics.

## Takeaways

- TOON is leaner than JSON but still hierarchical: arrays of structs format themselves as literal tables, so relationships remain obvious to both humans and models.
- CSV can still transport raw facts, but you end up writing bespoke parsing logic (and telling the LLM how to interpret it) every time your schema nests.
- When you already define signatures in Sorbet, just call `Sorbet::Toon.encode(payload)` and drop the resulting block into your prompt. The spec we added is a copy-pasteable reference for teammates who want to “see” the layout before adopting it.

Next stop: record a VCR cassette using this signature so we can show TOON’s nested layout flowing through an actual Enhanced Prompting call. Until then, the spec stands as the living documentation for how TOON preserves rich relationships that CSV can’t.

## Using these structs inside DSPy.rb

Hooking the `Book`/`Author` structs into a real predictor just takes a signature and an LM configured for TOON:

```ruby
class SummarizeBookCatalog < DSPy::Signature
  description 'Summarize a catalog of books and their authors'

  input do
    const :catalog, T::Array[Book]
  end

  output do
    const :highlights, String
    const :featured_authors, T::Array[Author]
  end
end
```

Wire up Gemini with BAML[^2]+TOON rendering:

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'google/gemini-2.5-flash',
    api_key: ENV.fetch('GEMINI_API_KEY'),
    schema_format: :baml,
    data_format: :toon
  )
end
```

Now your predictor automatically emits the nested TOON block:

```ruby
librarian = DSPy::Predict.new(SummarizeBookCatalog)
catalog_summary = librarian.call(
  catalog: sample_books
)

puts catalog_summary.highlights
catalog_summary.featured_authors.each { |author| puts author.name }
```

Because TOON preserves the nested structure, Gemini receives a compact table for each book's authors and DSPy hands you typed structs on the way back. No CSV gymnastics, no extra parsing layer—just signatures, Sorbet types, and TOON keeping everything coherent.

## Related Resources

- [Toolsets Documentation](https://vicentereig.github.io/dspy.rb/core-concepts/toolsets/) - Learn how to build tools that work with TOON-formatted data

[^1]: For a comprehensive introduction to TOON and how it pairs with BAML to cut prompt tokens in half, see [Cut Prompt Tokens in Half with BAML + TOON](https://vicentereig.github.io/dspy.rb/blog/articles/toon-data-format/).
[^2]: BAML (BoundaryML Schema Language) provides TypeScript-like schema syntax that's 83-85% more compact than JSON Schema. Learn more in [Rich Signatures, Lean Schemas](https://vicentereig.github.io/dspy.rb/blog/articles/baml-schema-format/).
