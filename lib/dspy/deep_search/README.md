# DSPy::DeepSearch

`dspy-deep_search` provides a search-read-reason loop with token budgets, queues, and an Exa client. The application still owns source policy, retrieval review, model choice, and external-service cost.

See the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for the canonical package name, status, and overlap disclosures.

## Prerequisites

- Ruby, Bundler, and the `dspy-deep_search` gem
- `EXA_API_KEY` for the bundled search client
- credentials for at least one model used by the seed, reader, and reasoning predictors

The module chooses from its documented model priorities unless you set `DSPY_DEEP_SEARCH_SEED_MODEL`, `DSPY_DEEP_SEARCH_READER_MODEL`, and `DSPY_DEEP_SEARCH_REASON_MODEL`.

## Install and Run

```ruby
gem "dspy"
gem "dspy-deep_search"
gem "dspy-openai" # or the adapter gems required by your selected models
```

Save this as `deep_search.rb`:

```ruby
require "dspy"
require "dspy/deep_search"

result = DSPy::DeepSearch::Module.new.call(
  question: "What changed in Ruby's fiber scheduler in recent releases?"
)

puts result.answer
puts result.citations
warn result.warning if result.warning
```

```bash
bundle install
export EXA_API_KEY="your-exa-key"
export OPENAI_API_KEY="your-model-provider-key"
bundle exec ruby deep_search.rb
```

The command prints a synthesized answer followed by collected citation URLs. A budget-exhausted run returns a partial result with `budget_exhausted` and `warning` set.

## Failure Conditions

- Missing Exa or model credentials prevent the corresponding external request.
- Search-provider errors may leave the run with fewer notes or citations.
- Retrieval quality and citations require application review; the module does not verify that a source is authoritative or that the final answer is correct.
- Token budgets bound recorded LM usage. Provider availability, rate limits, and transport errors remain external concerns.
