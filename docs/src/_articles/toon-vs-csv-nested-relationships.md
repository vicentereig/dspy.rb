---
layout: blog
title: "TOON and CSV for Nested LLM Data"
date: 2025-11-15
description: "How TOON represents nested Sorbet structs and arrays that require flattening or extra conventions in CSV."
author: "Vicente Reig Rincon de Arellano"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/toon-vs-csv-nested-relationships/"
image: /images/og/toon-vs-csv-nested-relationships.png
reading_time: "3 min read"
---

CSV represents one table well. A catalog in which each book has several authors is not one table unless you flatten the relationship or split it across records. Token-Oriented Object Notation (TOON)[^1] can retain that nesting while using tabular rows for uniform arrays.

The unit spec in [`spec/sorbet/toon/books_serialization_spec.rb`](https://github.com/vicentereig/dspy.rb/blob/main/spec/sorbet/toon/books_serialization_spec.rb) uses these Sorbet types:

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

`Sorbet::Toon.encode` produces the following nested representation:

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

`authors[2]{name,notable_work}` declares the row count and columns for the nested author array. The book fields remain grouped with that array. Plain CSV would need an agreed flattening scheme, repeated book columns, or a second table with join keys.

## Decoding the Structure

`Sorbet::Toon.decode` returns Ruby primitives by default. Pass a struct class or signature when the caller needs reconstructed Sorbet objects. Inside DSPy.rb, `data_format: :toon` supplies the output signature to the decoder before `Predict` constructs its prediction.

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

```ruby
DSPy.configure do |c|
  c.lm = DSPy::LM.new(
    'gemini/gemini-2.5-flash',
    api_key: ENV.fetch('GEMINI_API_KEY'),
    schema_format: :baml,
    data_format: :toon
  )
end
```

```ruby
librarian = DSPy::Predict.new(SummarizeBookCatalog)
catalog_summary = librarian.call(catalog: sample_books)

puts catalog_summary.highlights
catalog_summary.featured_authors.each { |author| puts author.name }
```

This path uses prompt-rendered TOON rather than provider-native JSON structured output. It removes the need for application-specific CSV flattening, but it still depends on the model returning valid TOON that matches the signature.

## Choosing Between Them

Use CSV for a genuinely flat table, especially when existing systems already produce and consume it. Use TOON when one payload mixes objects, nested arrays, and repeated records and you want one representation that preserves those boundaries.

Neither format guarantees better model output. Compare token counts and evaluation results on the payloads and models that matter to the application.

## Related Resources

- [Signatures Documentation](https://oss.vicente.services/dspy.rb/core-concepts/signatures/)
- [Predictors Documentation](https://oss.vicente.services/dspy.rb/core-concepts/predictors/)
- [Rich Signatures, Lean Schemas](https://oss.vicente.services/dspy.rb/blog/articles/baml-schema-format/)

[^1]: See [Compact Schemas and Payloads with BAML and TOON](https://oss.vicente.services/dspy.rb/blog/articles/toon-data-format/) for the DSPy.rb configuration.
