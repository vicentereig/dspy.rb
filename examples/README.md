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

### Observability, Events, and Benchmarks

- **`event_system_demo.rb`** — End-to-end tour of the DSPy event bus, including type-safe LLM events and custom subscribers for optimization metrics.
- **`telemetry_benchmark.rb`** — Measures OpenTelemetry span throughput under typical DSPy workloads.
- **`baml_vs_json_benchmark.rb`** — Compares BAML vs JSON schema prompting across multiple providers, including cost estimates.
- **`json_modes_benchmark.rb`** — Evaluates OpenAI JSON modes vs enhanced prompting for structured outputs.

### Data, Evaluation, and Multimodal

- **`sentiment-evaluation/`** — Minimal sentiment classifier with evaluation helpers; great starter for building your own metrics.
- **`multimodal/`** — Vision-language snippets (`image_analysis.rb`, `bounding_box_detection.rb`) that show how to send images through DSPy LMs.

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
