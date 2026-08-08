---
layout: docs
title: "Ruby RAG Tutorial with DSPy.rb"
name: Retrieval Augmented Generation (RAG)
description: "Build retrieval-augmented generation in Ruby with an application-owned retriever, typed signatures, and explicit evaluation."
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2026-08-08 00:00:00 +0000
---
# Retrieval Augmented Generation (RAG)

Retrieval-augmented generation (RAG) has two parts: retrieve relevant material, then ask a model to use it. DSPy.rb supplies the typed signature and module boundary. Your application owns the documents, search system, permissions, freshness policy, and citations.

DSPy.rb does not provide a vector store or an embedding model. Start with the smallest retriever that can answer your evaluation questions. Add a vector or hybrid index only when measurements justify the extra system.

## Define the retrieval boundary

Make the retriever return stable records. Keeping the identifier and source with the text makes citations and debugging possible.

```ruby
class LexicalRetriever
  def initialize(documents)
    @documents = documents
  end

  def search(query, limit: 3)
    terms = query.downcase.scan(/[a-z0-9]+/).uniq

    @documents
      .filter_map do |document|
        score = terms.count { |term| document[:text].downcase.include?(term) }
        score.positive? ? [score, document] : nil
      end
      .sort_by { |score, document| [-score, document[:id]] }
      .first(limit)
      .map(&:last)
  end
end
```

This is a working baseline, not a recommendation to use substring search in production. Replace it with an adapter for your search service when the baseline misses the cases that matter.

## Pass retrieved context to a typed module

Keep retrieval outside the signature. The model should receive the question and selected context; it should not decide which database or tenant to query.

```ruby
class AnswerFromContext < DSPy::Signature
  description "Answer a question using only the supplied context"

  input do
    const :question, String
    const :context, String
  end

  output do
    const :answer, String
    const :citations, T::Array[String]
  end
end

class RetrievedAnswer < DSPy::Module
  def initialize(retriever)
    super
    @retriever = retriever
    @answerer = DSPy::Predict.new(AnswerFromContext)
  end

  def forward(question:, limit: 3)
    documents = @retriever.search(question, limit: limit)
    context = documents.map do |document|
      "[#{document[:id]}] #{document[:text]}"
    end.join("\n\n")

    return {answer: "I could not find relevant context.", citations: []} if context.empty?

    result = @answerer.call(question: question, context: context)
    {answer: result.answer, citations: result.citations}
  end
end

documents = [
  {id: "refunds", text: "Refunds are available within 30 days of purchase."},
  {id: "support", text: "Support is available by email on business days."}
]

program = RetrievedAnswer.new(LexicalRetriever.new(documents))
program.call(question: "How long do I have to request a refund?")
```

The empty-result branch is deliberate. A retriever can return nothing; the application should choose that behavior rather than letting an empty prompt look like evidence.

## Adapt a real search system

Your adapter needs one small contract:

```ruby
documents = retriever.search(query, limit: 5)

# Each record should contain:
# {id: "stable-source-id", text: "retrieved passage", source: "public URL"}
```

The adapter can call a keyword index, vector database, hosted search API, or hybrid system. Keep these decisions outside DSPy.rb:

- enforce tenant and document permissions before returning text;
- apply freshness and publication rules in the index or adapter;
- cap the number and size of passages before the model call;
- preserve source identifiers and URLs for citations;
- return an empty array when no passage meets the retrieval policy.

Do not copy a vendor client into this page. Its authentication, API version, embedding model, retry policy, and response shape belong to the application that owns the service.

## Filter context before generation

Retrieval quality and answer quality are different measurements. Record retrieved identifiers, scores when the store provides them, and final context length. A simple application-owned policy can look like this:

```ruby
def prepare_context(documents, limit: 5, max_chars: 12_000)
  documents.first(limit).each_with_object([]) do |document, passages|
    break passages if passages.sum { |passage| passage[:text].length } >= max_chars

    passages << document
  end
end
```

This cap is not universal. Measure recall, answer correctness, latency, and cost on your own questions before changing it.

## Evaluate retrieval and answers separately

Use a held-out set. The questions used to tune retrieval or prompts should not be the only questions used to judge the result.

Track retrieval metrics such as:

- whether the expected source was retrieved;
- how many returned passages were relevant;
- how often the result set was empty;
- retrieval latency and cost.

Track answer metrics separately:

- whether the answer is supported by the returned context;
- whether citations identify supporting passages;
- whether the program refuses when context is insufficient;
- provider latency, cost, and parsing failures.

An answer score cannot tell you whether a failure came from search or generation. Keep those failures visible.

## Keep retrieval observable

Wrap the application-owned retriever when you need bounded measurements:

```ruby
class TracedRetriever
  def initialize(retriever)
    @retriever = retriever
  end

  def search(query, limit: 5)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    documents = @retriever.search(query, limit: limit)

    warn({
      event: "retrieval.complete",
      limit: limit,
      result_count: documents.length,
      elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    }.inspect)

    documents
  end
end
```

Do not log the user's full query or retrieved text by default. Log stable identifiers and bounded measurements; add redaction and access controls before retaining sensitive content.

## Decide whether you need a vector store

Use lexical search when the corpus is small, terminology is stable, or exact terms matter. Consider vector or hybrid retrieval when held-out questions show a repeatable recall problem that better indexing could address.

Changing the index does not prove that answers improved. Compare the old and new retrievers on the same held-out questions, then evaluate the complete program with the same answer metric.

## Continue by reader task

- **[Signatures](/dspy.rb/core-concepts/signatures/)** — define typed inputs and outputs.
- **[Modules](/dspy.rb/core-concepts/modules/)** — compose retrieval and generation with Ruby control flow.
- **[Evaluation](/dspy.rb/optimization/evaluation/)** — measure program behavior with explicit metrics.
- **[Observability](/dspy.rb/production/observability/)** — trace application-owned retrieval and model calls.
- **[Troubleshooting](/dspy.rb/production/troubleshooting/)** — diagnose provider, parsing, and validation failures.
