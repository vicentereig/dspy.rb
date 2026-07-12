---
layout: docs
title: "Program Optimization in Ruby | MIPROv2 & GEPA"
name: Program Optimization
description: "Evaluate DSPy.rb programs, revise instructions and examples immutably, and compile candidates with MIPROv2 or GEPA."
breadcrumb:
- name: Optimization
  url: "/optimization/"
- name: Program Optimization
  url: "/optimization/prompt-optimization/"
prev:
  name: Evaluation Framework
  url: "/optimization/evaluation/"
next:
  name: MIPROv2 Optimizer
  url: "/optimization/miprov2/"
date: 2025-07-10 00:00:00 +0000
---
# Program Optimization

DSPy.rb applications define tasks with signatures and execute them with modules. Instructions and few-shot examples remain part of the program, but you do not need to maintain provider-specific prompt templates. Adapters render the signature, examples, and output constraints for each provider.

Optimization starts with a dataset and a metric. The optimizer proposes program variants, evaluates them, and returns the best candidate it found within the configured budget. A higher validation score is evidence about that dataset and metric, not a general guarantee.

## Inspect a Program

`DSPy::Predict` exposes its immutable `DSPy::Prompt`:

```ruby
class ClassifyText < DSPy::Signature
  description "Classify the sentiment of the given text"

  input do
    const :text, String
  end

  output do
    const :sentiment, String
    const :confidence, Float
  end
end

predictor = DSPy::Predict.new(ClassifyText)
prompt = predictor.prompt

puts prompt.instruction
puts prompt.few_shot_examples.size
```

The prompt stores the instruction and examples. The signature remains the source of the input and output contract.

## Revise Instructions and Examples

Use module methods to create a revised program. The original remains unchanged.

```ruby
revised = predictor.with_instruction(
  "Classify the text as positive, negative, or neutral."
)

examples = [
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "I love this product." },
    expected: { sentiment: "positive", confidence: 0.9 }
  ),
  DSPy::Example.new(
    signature_class: ClassifyText,
    input: { text: "The build failed again." },
    expected: { sentiment: "negative", confidence: 0.9 }
  )
]

revised = revised.with_examples(examples)
```

`with_instruction` and `with_examples` return new module instances. There is no `prompt=` writer on `DSPy::Predict`.

## Measure a Baseline

Evaluate the same examples and metric before and after a change:

```ruby
metric = lambda do |example, prediction|
  prediction.sentiment == example.expected_values[:sentiment]
end

baseline = DSPy::Evals.new(predictor, metric: metric).evaluate(validation_examples)
candidate = DSPy::Evals.new(revised, metric: metric).evaluate(validation_examples)

puts "Baseline: #{baseline.score}"
puts "Candidate: #{candidate.score}"
```

Keep a separate test set for the final comparison. Reusing the validation set for the final claim rewards candidates that happened to fit that set.

## Compile with MIPROv2

MIPROv2 lives in the optional `dspy-miprov2` gem:

```ruby
gem "dspy"
gem "dspy-miprov2"
```

Compile the program against training and validation examples:

```ruby
optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium(metric: metric)

result = optimizer.compile(
  predictor,
  trainset: training_examples,
  valset: validation_examples
)

optimized_program = result.optimized_program
puts optimized_program.prompt.instruction
puts result.best_score_value
```

MIPROv2 searches over instructions and demonstrations. Its API returns an `OptimizationResult`; deploy or serialize `result.optimized_program`, not the optimizer itself.

See [MIPROv2](/dspy.rb/optimization/miprov2/) for budgets, presets, and multi-predictor programs.

## Compile with GEPA

GEPA uses scalar scores and textual feedback to propose instruction changes. It lives in the optional `dspy-gepa` gem.

Use GEPA when your metric can explain a failure, not merely mark it wrong. The reflection model receives that feedback and uses it to propose the next candidate.

See [GEPA](/dspy.rb/optimization/gepa/) for its metric contract, reflection model, and evaluation budget.

## Store the Result

`ProgramStorage` saves the optimized program together with the optimization result and metadata:

```ruby
storage = DSPy::Storage::ProgramStorage.new(
  storage_path: "./dspy_storage"
)

saved = storage.save_program(
  result.optimized_program,
  result,
  metadata: { dataset: "sentiment-v1" }
)

loaded = storage.load_program(saved.program_id)
loaded_program = loaded.program
```

Record the dataset version, metric version, model, optimizer configuration, and validation score beside the artifact. Those details explain what the optimized program was selected to do.

Reloading reconstructs the program class named in the artifact. That class and its signature class must already be loaded, and the program class must implement `.from_h`. Evaluate `loaded_program` before promotion; persistence does not establish compatibility with a changed model, dependency, or application.

## Operational Limits

- Optimization spends LM calls. Set a budget before starting a run.
- A metric defines what the search rewards. Test the metric against examples a human has reviewed.
- Validation gains may not survive model, provider, or data changes.
- Optimizers revise supported textual parameters and demonstrations. They do not choose the product objective or make unsafe tools safe.
- Re-run evaluation before promoting a stored program into a changed environment.
