# GEPA Optimizer (Beta)

> Genetic-Pareto Reflective Prompt Evolution for DSPy.rb

GEPA evolves a module's instructions by replaying traces, collecting feedback, and asking a reflection
model to propose improvements. The Ruby port currently supports:

- Core GEPA engine (state, Pareto frontier, reflective proposer).
- DSPy teleprompter (`DSPy::Teleprompt::GEPA`) that works with any `DSPy::Module` built from a signature or composite module.
- Optional reflection LM via `DSPy::ReflectionLM` or any object responding to `#call` (text only for now).

```ruby
gepa = DSPy::Teleprompt::GEPA.new(
  metric: ->(example, prediction) { prediction[:answer] == example.expected_values[:answer] ? 1.0 : 0.0 },
  reflection_lm: DSPy::ReflectionLM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
)

result = gepa.compile(student_module, trainset: train_examples, valset: validation_examples)
```

**Reflection LM requirements**
- Plain-text responses (structured outputs disabled).
- Returns the updated instruction inside ``` fences (handled automatically by `InstructionProposalSignature`).

**Roadmap**
- Richer dataset adapters (multi-predictor, ReAct trace capture).
- Merge proposer and optional logging backends.
- Parity checks against the Python GEPA test suite.
