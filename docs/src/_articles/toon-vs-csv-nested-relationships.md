---
layout: blog
title: "What TOON Gets That CSV Doesn’t for LLM Payloads"
date: 2025-11-15
description: "Token-Oriented Object Notation keeps your nested Sorbet structs intact—something flat CSV rows simply can’t do when you prompt large language models."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/toon-vs-csv-nested-relationships/"
image: /images/og/toon-data-format.png
reading_time: "3 min read"
---

CSV is phenomenal for spreadsheets and OLAP imports, but it breaks down the moment you try to express nested relationships in an LLM prompt. Token-Oriented Object Notation (TOON) keeps the structural cues that Sorbet signatures describe—arrays of structs, nested arrays, enums—without reprinting every JSON key. The new regression spec in `spec/sorbet/toon/books_serialization_spec.rb` captures a concrete example: a catalog of books, each with its own list of authors.

## The Sorbet signature

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

Two structs, one pointing to an array of the other. CSV has no native way to represent “an array of structs inside another struct” without inventing index columns or carrying a foreign-key matrix across multiple sheets.

## The TOON payload (as recorded in the spec)

```toon
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

## What a CSV attempt would look like

```csv
book_title,book_published_year,author_name,author_notable_work
Distributed Systems,2014,Leslie Lamport,Paxos
Distributed Systems,2014,Nancy Lynch,FLP result
Programming Languages,2003,Benjamin Pierce,TAPL
```

Four silent problems immediately appear when you ship this to an LLM:

1. **No boundaries.** The model has to guess where one book ends and the next begins. That works for trivial cases but collapses once you introduce optional fields or mixed-length arrays.
2. **Duplicate scalar data.** Each author row repeats `book_title`/`book_published_year`, inflating token counts and encouraging hallucinated merges.
3. **Lost typing.** CSV doesn’t encode “this column is an array”; it’s just another string. Post-processing code has to rebuild the structure manually.
4. **Ambiguous ordering.** If you sort the rows differently, the LLM has zero cues to keep authors grouped with their book.

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

Wire up Gemini with BAML+TOON rendering:

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

Because TOON preserves the nested structure, Gemini receives a compact table for each book’s authors and DSPy hands you typed structs on the way back. No CSV gymnastics, no extra parsing layer—just signatures, Sorbet types, and TOON keeping everything coherent.
