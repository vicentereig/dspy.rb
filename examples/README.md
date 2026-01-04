# DSPy.rb Examples

This directory contains practical examples for using DSPy.rb features.

## Setup

Create a `.env` file in the project root with your API keys:
```bash
OPENAI_API_KEY=your-openai-key
ANTHROPIC_API_KEY=your-anthropic-key
```

## Examples by Category

### Optimization

- **`ade_optimizer_miprov2/`** — ADE classifier optimized with MIPROv2. Mirrors the docs walkthrough, uses the `dspy-miprov2` gem, supports `--auto light|medium|heavy`, and writes metrics/trial logs to `results/`.
- **`hotpotqa_react_miprov2/`** — Multi-hop HotPotQA ReAct agent tuned with MIPROv2. Demonstrates per-predictor instructions, tool usage, and dataset caching for larger pipelines.
- **`ade_optimizer_gepa/`** — ADE classifier optimized with GEPA. Shows how to wire reflection feedback and interpret Pareto-tracked candidates.
- **`gepa_snapshot.rb`** — Scripted GEPA run that produces fixture snapshots for specs. Useful when you want deterministic reflection output for testing.

### Agents & Workflow Automation

- **`basic_search_agent.rb`** — ReAct agent that calls a course-search tool and returns typed `Course` structs, highlighting structured outputs.
- **`react_loop/`** — Calculator/unit conversion/date tools wired into a ReAct loop with observability enabled.
- **`coffee-shop-agent/`** — Conversational ordering bot with short-term memory. Run `bundle exec ruby coffee-shop-agent/coffee_shop_agent.rb`.
- **`github-assistant/`** — GitHub-focused helper that chains CLI actions (requires a GitHub token in your environment). See the folder README for setup.
- **`deep_research_cli/`** — Terminal chat experience for DeepSearch + DeepResearch with Shopify `CLI::UI`, live token/status metrics, and the memory supervisor from `DSPy::DeepResearchWithMemory`. See the example README for setup and tests.
- **`ephemeral_memory_chat.rb`** — CLI chat session that uses module lifecycle hooks to keep an in-memory transcript while routing each turn to different LLMs based on complexity/cost.

### Observability, Events, and Benchmarks

- **`event_system_demo.rb`** — End-to-end tour of the DSPy event bus, including type-safe LLM events and custom subscribers for optimization metrics.
- **`telemetry_benchmark.rb`** — Measures OpenTelemetry span throughput under typical DSPy workloads.
- **`baml_vs_json_benchmark.rb`** — Compares BAML vs JSON schema prompting across multiple providers, including cost estimates.
- **`json_modes_benchmark.rb`** — Evaluates OpenAI JSON modes vs enhanced prompting for structured outputs.

### Data, Evaluation, and Multimodal

- **`sentiment-evaluation/`** — Minimal sentiment classifier with evaluation helpers; great starter for building your own metrics.
- **`pdf_recursive_summarizer.rb`** — Structure-first PDF summarizer using the map-reduce pattern. See [PDF Summarizer](#pdf-summarizer) below.
- **`multimodal/`** — Vision-language snippets (`image_analysis.rb`, `bounding_box_detection.rb`) that show how to send images through DSPy LMs.

---

## PDF Summarizer

A structure-first approach to document summarization that's simpler and more predictable than agentic navigation.

### Pipeline

```
Document + Query
      │
      ▼
┌─────────────────┐
│ DiscoverStructure │  ← 1 LLM call (ChainOfThought)
│ (preview + query) │     Identifies sections with relevance scores
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│         PARALLELIZABLE                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │Summarize │ │Summarize │ │Summarize │ │  ← N LLM calls
│  │Section A │ │Section B │ │Section C │ │
│  └──────────┘ └──────────┘ └──────────┘ │
└────────────────────┬────────────────────┘
                     │
                     ▼
          ┌─────────────────┐
          │SynthesizeSummaries│  ← 1 LLM call
          └────────┬────────┘
                   │
                   ▼
                Answer
```

### Signatures

| Signature | Purpose |
|-----------|---------|
| `DiscoverStructure` | Identify logical sections from document preview, assign relevance (high/medium/low/skip) |
| `SummarizeSection` | Summarize a single section with query-focused extraction |
| `SynthesizeSummaries` | Combine section summaries into coherent final answer |

### Usage

```bash
# Basic usage
bundle exec ruby examples/pdf_recursive_summarizer.rb --pdf document.pdf

# With a specific query
bundle exec ruby examples/pdf_recursive_summarizer.rb \
  --pdf research_paper.pdf \
  --query "What methodology was used?"

# Export results to JSON
bundle exec ruby examples/pdf_recursive_summarizer.rb \
  --pdf report.pdf \
  --output-json results.json
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--pdf PATH` | required | Path to PDF file |
| `--query QUERY` | "Provide a concise summary" | Focus question for relevance |
| `--model MODEL` | `openai/gpt-4o-mini` | LLM to use |
| `--preview-lines N` | 100 | Lines shown to structure discovery |
| `--max-section-chars N` | 8000 | Max chars per section |
| `--output-json PATH` | none | Export full results to JSON |

### Why Structure-First?

Compared to agentic/cursor approaches:

- **Predictable**: Fixed number of LLM calls (2 + N sections)
- **Parallelizable**: Section summarization can run concurrently
- **Debuggable**: Clear pipeline stages, easy to inspect intermediate results
- **Cost-efficient**: No history accumulation, minimal token overhead

Best for documents with discoverable structure (reports, papers, legal docs). For truly unstructured or exploratory tasks, consider a ReAct agent instead.

## Quick Start

1. **Basic prediction:**
```ruby
require 'dspy'

class QASignature < DSPy::Signature
  description "Answer questions concisely"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini')
end

predictor = DSPy::Predict.new(QASignature)
result = predictor.call(question: "What is 2+2?")
puts result.answer
```

2. **Chain of thought reasoning:**
```ruby
cot = DSPy::ChainOfThought.new(QASignature)
result = cot.call(question: "Explain why 2+2=4")
puts result.reasoning  # Shows step-by-step thinking
puts result.answer     # Shows final answer
```

3. **Creating training examples:**
```ruby
examples = [
  DSPy::Example.new(
    signature_class: QASignature,
    input: { question: "What is the capital of France?" },
    expected: { answer: "Paris" }
  )
]
```

## Running Examples

All examples check for required API keys and will exit with a helpful message if missing.

```bash
# Run a specific example
bundle exec ruby examples/sentiment-evaluation/sentiment_classifier.rb

# Run with debug output
DEBUG=true bundle exec ruby examples/sentiment-evaluation/sentiment_classifier.rb
```

## Tips

- Start with simple examples before trying optimization
- Use `DSPy::ChainOfThought` for complex reasoning tasks
- Check example outputs for expected data structures
- Examples use realistic datasets and evaluation metrics
