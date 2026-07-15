# Evaluate a Typed Sentiment Classifier

This example runs a `DSPy::ChainOfThought` sentiment classifier against a small synthetic set. It compares a built-in metric, a custom label metric, and a weighted demonstration metric, then prints per-example results.

## Prerequisites

- a repository checkout with `bundle install` completed
- `OPENAI_API_KEY`
- network access for the configured `openai/gpt-4o-mini` calls

The script loads `.env` from the repository root.

## Run

```bash
export OPENAI_API_KEY="your-key"
bundle exec ruby examples/sentiment-evaluation/sentiment_classifier.rb
```

The command prints the number of examples, aggregate metric results, per-example labels and confidence values, and the error-handling demonstration. Scores and labels vary by model run; the README does not prescribe fixed percentages.

## What the Metrics Establish

- The built-in and custom label metrics compare predictions with synthetic expected labels.
- The weighted metric assigns 50% to label agreement, 30% to closeness to an illustrative confidence value, and 20% to the presence and length of reasoning text.
- Those weights demonstrate the metric API. Reasoning length is not evidence of reasoning quality, and the synthetic confidence values are not a calibration dataset.

Replace the examples and policy weights with reviewed application data before using a score as an optimization objective or release gate.

## Failure Conditions

- The script exits when `OPENAI_API_KEY` is absent.
- Provider, transport, parsing, or validation errors become failed predictions or can stop the run, depending on where they occur.
- An empty tweet is not guaranteed to raise. Applications that reject empty input must validate that boundary explicitly.

See the [evaluation guide](https://oss.vicente.services/dspy.rb/optimization/evaluation/) for held-out sets and result semantics.
