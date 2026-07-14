# DSPy.rb Examples

This directory indexes repository demos. For a first install-to-result path, use the canonical [Quick Start](../docs/src/getting-started/quick-start.md); these examples assume a checkout of this repository and its Bundler environment.

## Before Running an Example

Run `bundle install` from the repository root. Then read the selected script or its local README for required provider keys, optional packages, data downloads, and side effects.

Many examples explicitly load the repository's `.env` with `dotenv`; others read only the process environment. DSPy.rb itself does not load `.env`. Export the required key in your shell unless the selected example says that it loads `.env`.

Provider and model output varies. Some scripts call paid APIs, write results, or require external services. Their local README or source is the authority for those prerequisites.

## Prediction and Composition

- [`basic_search_agent.rb`](basic_search_agent.rb) — ReAct course search with typed `Course` results; OpenAI API call.
- [`workflow_router.rb`](workflow_router.rb) — fixed Ruby routing across typed predictors; Anthropic API calls.
- [`summarization_comparison.rb`](summarization_comparison.rb) — compare typed summaries with a separate judge model; OpenAI API calls.

## Agents and Tools

- [`react_loop/`](react_loop/) — calculator, unit conversion, and date tools in a ReAct loop.
- [`coffee-shop-agent/`](coffee-shop-agent/) — conversational ordering bot with short-term memory; see its README.
- [`github-assistant/`](github-assistant/) — GitHub-focused assistant with provider and GitHub prerequisites; see its README.
- [`deep_research_cli/`](deep_research_cli/) — terminal DeepSearch and DeepResearch client; see its README for LLM and search keys.
- [`codeact_research_agent.rb`](codeact_research_agent.rb) — generated Ruby execution with the optional `dspy-code_act` package; review the execution boundary before running.

## Evaluation and Optimization

- [`sentiment-evaluation/`](sentiment-evaluation/) — sentiment classifier plus evaluation helpers.
- [`ade_optimizer_miprov2/`](ade_optimizer_miprov2/) — ADE classifier optimized with MIPROv2; see its README for modes and output files.
- [`ade_optimizer_gepa/`](ade_optimizer_gepa/) — ADE classifier optimized with GEPA; see its README for provider requirements.
- [`hotpotqa_react_miprov2/`](hotpotqa_react_miprov2/) — multi-hop ReAct optimization with dataset caching.
- [`evaluator_loop.rb`](evaluator_loop.rb) — generator/evaluator loop with an explicit token budget.
- [`gepa_snapshot.rb`](gepa_snapshot.rb) — deterministic fixture snapshot generation for GEPA specs.

## Formats, Media, and Benchmarks

- [`multimodal/`](multimodal/) — image analysis and bounding-box examples.
- [`html_to_markdown/`](html_to_markdown/) — recursive typed HTML-to-Markdown pipeline; see its README.
- [`baml_vs_json_benchmark.rb`](baml_vs_json_benchmark.rb) — compare schema prompt formats across configured providers.
- [`json_modes_benchmark.rb`](json_modes_benchmark.rb) — compare OpenAI JSON strategies.
- [`event_system_demo.rb`](event_system_demo.rb) — event bus subscriptions and emitted attributes.
- [`telemetry_benchmark.rb`](telemetry_benchmark.rb) — OpenTelemetry span-throughput benchmark.

Run a selected script from the repository root, for example:

```bash
bundle exec ruby examples/basic_search_agent.rb
```

That command is specific to the indexed example. The Quick Start remains the canonical new-application path.
