---
layout: docs
title: Custom Toolsets
description: Add bounded application operations to a DSPy.rb Toolset
date: 2025-07-11 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
# Custom Toolsets

This guide extends the [Toolsets reference](/dspy.rb/core-concepts/toolsets/) with an application recipe. It assumes you already know the `toolset_name`, `tool`, and `.to_tools` APIs.

The current `.to_tools` export path constructs the Toolset with `new` and no arguments. The recipe is therefore stateless and has a zero-argument constructor. If a capability needs constructor-injected clients or per-request state, wrap it in individual `DSPy::Tools::Base` instances or keep the state outside the current Toolset export path.

<span id="toolset-architecture"></span>
<span id="base-toolset-structure"></span>
<span id="tool-method-requirements"></span>
<span id="advanced-type-support"></span>

## Build a Bounded Text Lookup Toolset

This operation accepts text already provided by the application. It does not read files, start a process, or make a network request. It caps input and output, treats the query as literal text, and returns a stable JSON failure envelope.

```ruby
require "dspy/tools/toolset"
require "json"

class ReleaseNotesToolset < DSPy::Tools::Toolset
  extend T::Sig

  MAX_TEXT_BYTES = 100_000
  MAX_QUERY_BYTES = 200
  MAX_MATCHES = 20

  toolset_name "release_notes"
  tool :find_lines, description: "Find up to 20 lines containing literal text"

  sig { params(text: String, query: String, limit: Integer).returns(String) }
  def find_lines(text:, query:, limit: 10)
    return failure("text_too_large") if text.bytesize > MAX_TEXT_BYTES
    return failure("invalid_query") if query.empty? || query.bytesize > MAX_QUERY_BYTES
    return failure("invalid_limit") unless (1..MAX_MATCHES).cover?(limit)
    return failure("invalid_encoding") unless text.valid_encoding? && query.valid_encoding?

    needle = query.downcase
    matches = text.each_line.with_index(1).filter_map do |line, number|
      { line: number, text: line.chomp } if line.downcase.include?(needle)
    end.first(limit + 1)
    truncated = matches.length > limit

    JSON.generate(ok: true, matches: matches.first(limit), truncated: truncated)
  rescue Encoding::CompatibilityError, ArgumentError => error
    failure("incompatible_encoding", detail: error.message)
  end

  private

  sig { params(code: String, detail: T.nilable(String)).returns(String) }
  def failure(code, detail: nil)
    JSON.generate(ok: false, error: code, detail: detail)
  end
end

tools = ReleaseNotesToolset.to_tools
lookup = tools.to_h { |tool| [tool.name, tool] }.fetch("release_notes_find_lines")
puts lookup.call(text: "Added caching\nFixed retries\n", query: "fixed", limit: 5)
```

The limits here bound this one in-memory operation. They do not authorize access to the source text or impose a timeout on an agent loop.

## Attach It to a Bounded Agent

The application chooses which tools enter the agent and how many model-directed steps are allowed:

```ruby
agent = DSPy::ReAct.new(
  SummarizeRelease,
  tools: ReleaseNotesToolset.to_tools,
  max_iterations: 5
)
```

Keep fixed sequencing in Ruby. Use `ReAct` only when model-directed choice among the exposed operations is useful.

`max_iterations` limits model-directed steps. It is not an elapsed-time deadline and does not cancel a running tool, subprocess, or network request; apply those limits at the operation boundary.

<span id="production-toolset-examples"></span>
<span id="1-simple-data-storage-toolset"></span>
<span id="2-file-system-operations-toolset"></span>
<span id="3-http-api-client-toolset"></span>
<span id="4-text-processing-toolset"></span>
<span id="advanced-patterns"></span>
<span id="1-stateful-toolsets"></span>
<span id="2-async-toolsets"></span>
<span id="3-validation-and-security"></span>
<span id="best-practices"></span>
<span id="1-error-handling"></span>
<span id="2-input-validation"></span>
<span id="3-resource-management"></span>
<span id="4-documentation"></span>
<span id="performance-considerations"></span>
<span id="1-lazy-loading"></span>
<span id="2-connection-pooling"></span>
<span id="3-caching"></span>

## Define the Operational Contract

Before exposing an application operation, decide and test:

- **Authority:** which user, tenant, or service may perform it; the schema has no authorization semantics.
- **Input policy:** allowed identifiers, paths, patterns, sizes, and encodings; type conversion is not sanitization.
- **Side effects:** read-only versus mutating behavior, idempotency, transaction boundaries, and partial-result cleanup.
- **Time and resources:** operation timeout, response cap, concurrency, retries, and the agent's `max_iterations`.
- **Failures:** stable error values or exceptions, which failures are retryable, and what may be shown to the model.

For shell commands, database queries, filesystem access, or HTTP calls, enforce these controls at the owning boundary. A Toolset proxy neither sandboxes the operation nor supplies a timeout. Prefer argument-vector process APIs over shell interpolation, use allowlists for reachable resources, and isolate untrusted execution at the OS or container level.

<span id="testing-custom-toolsets"></span>
<span id="unit-testing"></span>
<span id="integration-testing"></span>

## Test the Exported Boundary

Exercise the method directly, then exercise the proxy with the JSON-shaped values an agent supplies:

```ruby
RSpec.describe ReleaseNotesToolset do
  let(:proxy) do
    described_class.to_tools
      .to_h { |tool| [tool.name, tool] }
      .fetch("release_notes_find_lines")
  end

  it "returns bounded matches through dynamic_call" do
    result = JSON.parse(
      proxy.dynamic_call(
        "text" => "Added caching\nFixed retries\n",
        "query" => "fixed",
        "limit" => 5
      )
    )

    expect(result).to include("ok" => true, "truncated" => false)
    expect(result.fetch("matches").length).to eq(1)
  end

  it "rejects oversized input before processing it" do
    result = JSON.parse(
      proxy.call(text: "x" * 100_001, query: "x", limit: 5)
    )

    expect(result).to include("ok" => false, "error" => "text_too_large")
  end
end
```

Also test authorization denials, timeout behavior, cleanup after failures, and retry semantics for any real external capability. Those tests belong to the application operation, not only to schema generation.
