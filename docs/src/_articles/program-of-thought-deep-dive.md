---
layout: blog
title: "Program of Thought: The Missing Link Between Reasoning and Code"
description: "Program of Thought delegates computation to generated code. Here is how it differs from ChainOfThought and CodeAct, and why execution isolation matters."
date: 2025-07-12
author: "Vicente Reig"
category: "Research"
reading_time: "12 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/program-of-thought-deep-dive/"
image: /images/og/program-of-thought-deep-dive.png
---

Language models can describe a calculation correctly and still get the arithmetic wrong. Program of Thought (PoT) moves the computation into generated code: the model formulates the program, an interpreter executes it, and the result feeds the final answer.

PoT is not currently implemented in DSPy.rb. The optional `dspy-code_act` gem provides a different code-execution strategy: an agent loop that can generate code, inspect observations, and try again.

## Separate the task from the arithmetic

Consider this question:

> Compute 12! divided by the sum of the prime numbers between 1 and 30.

A language-only reasoning trace may calculate the factorial and identify the primes, then make an error in the final division. A PoT module instead generates an executable program:

```python
def factorial(n):
    result = 1
    for i in range(1, n + 1):
        result *= i
    return result

def is_prime(n):
    if n < 2:
        return False
    for i in range(2, int(n**0.5) + 1):
        if n % i == 0:
            return False
    return True

fact_12 = factorial(12)
primes = [n for n in range(1, 31) if is_prime(n)]
sum_primes = sum(primes)
result = fact_12 / sum_primes
```

The interpreter produces `3713190.697674419` for the division.

The important boundary is mechanical: the model chooses the computation, while the interpreter performs it. That helps only when the generated program represents the problem correctly.

## What the paper measured

Chen et al. introduced Program of Thoughts Prompting as a way to separate language reasoning from external computation. [The paper](https://arxiv.org/abs/2211.12588) reports an average improvement of roughly 12% over chain-of-thought prompting across its evaluated math and financial datasets, with larger gains on some financial tasks. The result belongs to those models, prompts, datasets, and evaluation settings; it is not a general accuracy guarantee for generated code.

The useful result is narrower than the headline: an interpreter removes some arithmetic burden from the language model. PoT can still fail by choosing the wrong formula, omitting a condition, generating invalid code, or misreading the execution result.

## PoT, CodeAct, and ChainOfThought

These modules delegate different decisions:

| Strategy | Execution shape | Model chooses | Application provides |
|---|---|---|---|
| `ChainOfThought` | One reasoning prediction | A reasoning path and answer | A typed task contract |
| Program of Thought | Generate, execute, answer | A program for one computation | An interpreter and execution policy |
| `CodeAct` | Think, code, observe, repeat | Code and whether to continue | A bounded agent loop and execution environment |

CodeAct is an agent because the model chooses another action after observing execution. PoT is usually a fixed workflow: generate code, execute it, and return the result. Generated code does not by itself make a system an agent.

In upstream DSPy, `ProgramOfThought` is a module strategy:

```python
import dspy

pot = dspy.ProgramOfThought("question -> answer")
result = pot(
    question="What is the compound interest on $1000 at 5% for 10 years?"
)
```

The [upstream implementation](https://github.com/stanfordnlp/dspy/blob/main/dspy/predict/program_of_thought.py) and [tutorial](https://dspy.ai/tutorials/program_of_thought/) are the relevant references. DSPy.rb users currently need to implement the fixed sequence themselves or choose CodeAct when iterative execution is actually useful.

## Where PoT fits

PoT is a reasonable fit when:

- The answer depends on exact numerical computation.
- The calculation can be represented in the interpreter's language.
- One execution step is enough, or failures can return through a deterministic retry policy.
- The execution environment can be isolated from application authority.

It is a poor fit when:

- The task is mainly qualitative.
- The model needs to choose among external operations over several observations.
- The generated program would need broad filesystem, network, or credential access.
- A small, deterministic function can perform the calculation directly.

That last case matters. If Ruby code can compute a known formula before the LM call, write the Ruby code. Generated programs are useful when the computation varies with the problem, not when code generation merely hides a function the application already knows.

## Security belongs to the execution design

PoT and CodeAct execute model-generated code. Error handling around `eval` or an interpreter is not isolation:

```python
import os
os.system("rm -rf /")
```

The exact attack changes with the language, but the boundary does not. Generated code may consume unbounded resources, read secrets, make network requests, or mutate state.

A production execution harness needs process or container isolation, resource limits, restricted networking, ephemeral storage, and a narrow result channel. It should not inherit the application process's credentials. DSPy.rb's current CodeAct implementation evaluates Ruby in-process, so its documentation treats it as controlled experimentation unless the caller supplies that isolation.

## A possible DSPy.rb module

A Ruby PoT implementation should keep the sequence deterministic:

```ruby
class ProgramOfThought < DSPy::Module
  def initialize(code_generator:, executor:, result_parser:)
    super()
    @code_generator = code_generator
    @executor = executor
    @result_parser = result_parser
  end

  def forward(question:)
    program = @code_generator.call(question: question)
    observation = @executor.call(code: program.code)
    @result_parser.call(
      question: question,
      code: program.code,
      observation: observation
    )
  end
end
```

Here Ruby owns all three transitions. The model writes a program and interprets the observation, but it cannot add another operation unless the module explicitly permits one. The executor is injected because isolation policy should not be hidden inside the predictor.

Before adding this to DSPy.rb, I would require:

1. An executor interface with an isolated implementation.
2. Explicit CPU, memory, time, output, and network limits.
3. Typed execution results and errors.
4. Evaluation against numerical tasks and adversarial programs.
5. A documented distinction from CodeAct's iterative agent loop.

## Choosing the strategy

Use `ChainOfThought` for general typed reasoning that needs no execution. Use PoT when a bounded calculation varies with the question and an isolated interpreter can perform it. Use CodeAct when the model needs to inspect code results and choose another code action.

The choice is an execution decision, not a maturity ladder. A fixed workflow is often the smaller and more auditable program.

## References

- [Original Program of Thoughts paper](https://arxiv.org/abs/2211.12588)
- [DSPy Program of Thought tutorial](https://dspy.ai/tutorials/program_of_thought/)
- [DSPy implementation](https://github.com/stanfordnlp/dspy/blob/main/dspy/predict/program_of_thought.py)
- [Original research repository](https://github.com/TIGER-AI-Lab/Program-of-Thoughts)
