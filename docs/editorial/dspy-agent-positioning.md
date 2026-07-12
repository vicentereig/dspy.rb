# DSPy.rb Positioning: Programs, Agents, Tools, and Harnesses

This note reviews the original DSPy project's direction through July 2026. It
uses primary sources only: official DSPy documentation, Stanford NLP's DSPy
repository and releases, and papers by DSPy contributors.

## Conclusion

DSPy has not replaced workflows with agents. Its current model is broader:

- A signature declares a task as typed inputs and outputs.
- A module chooses how to execute that task. `Predict`, `ChainOfThought`,
  `ProgramOfThought`, `ReAct`, and `RLM` are module strategies.
- A tool gives an agent an operation it can select during execution.
- Ordinary code composes modules into a program or pipeline.
- An optimizer compiles a program against examples, metrics, and feedback.
- Adapters and the LM runtime translate those abstractions into provider calls.

The editorial shift should therefore be from **workflow-first** language to
**programmable, optimizable AI systems**, with agents as the tool-using case.
The concise promise is: **program agents instead of hand-authoring their
prompts**.

"Harness" is useful industry language for the execution substrate around an
agent: tools, history, state, error handling, permissions, tracing, evaluation,
and deployment. It is not currently a first-class term in DSPy's official
conceptual model. DSPy calls these pieces modules, tools, history, adapters,
runtime, evaluation, and optimization. DSPy.rb should use `harness` only when
it defines the term and names those concrete mechanisms.

## Chronology

### January-June 2025: the small core remains intact

DSPy's published roadmap described the core as LMs, signatures and modules,
optimizers, and assertions. It argued for modular LM programs in place of
ad-hoc prompts and separated the program's decomposition and objectives from
the way an LM is prompted or fine-tuned. The roadmap is now marked outdated,
but the same abstractions remain visible in the current documentation.

Source: [official roadmap](https://github.com/stanfordnlp/dspy/blob/main/docs/docs/roadmap.md)

### July-August 2025: DSPy 3.0 broadens the execution and optimization layers

DSPy 3.0 added or matured adapters and custom types, async execution,
streaming, save/load, observability, `CodeAct`, improved `ReAct`, MCP and
LangChain tool integration, and several optimizers. The release described GRPO
through Arbor as reinforcement learning for compound AI systems; SIMBA as
useful for agentic or long-horizon tasks; and GEPA as reflective evolution of
textual components.

This release did not replace programs with agents. It made programs able to use
more tools and execution strategies, then optimized them at more than one
layer.

Sources:

- [DSPy 3.0.0 release](https://github.com/stanfordnlp/dspy/releases/tag/3.0.0)
- [GEPA paper](https://arxiv.org/abs/2507.19457)

### Late 2025: optimization reaches agents and long-context execution

GEPA formalized reflective optimization of textual system components using
scores and natural-language feedback. DSPy subsequently added tool-description
optimization for multi-agent systems, though a later release temporarily
removed the public tool-optimization documentation and feature switch. That
sequence is evidence of active experimentation, not a stable promise that DSPy
optimizes every part of an agent harness today.

DSPy also added `RLM`, based on Recursive Language Models. An RLM treats a long
input as an external environment, inspects it through a sandboxed interpreter,
and can make recursive LM calls. This expands the set of programmable execution
strategies; DSPy's docs still classify it as a module.

Sources:

- [DSPy 3.1 release series](https://github.com/stanfordnlp/dspy/releases/tag/3.1.0)
- [Recursive Language Models paper](https://arxiv.org/abs/2512.24601)
- [official module guide](https://dspy.ai/learn/programming/modules/)

### 2026: native tool use becomes a structured runtime concern

DSPy 3.2 made optimizer composition explicit: `BetterTogether` can chain prompt
optimization and weight optimization while evaluating each stage. DSPy 3.3's
experimental `ReActV2` moved tool interaction from a formatted trajectory
string to typed `History`, `Tool`, `ToolCalls`, and `ToolCallResults`. It added
parallel tool calls, native multi-turn tool history, call IDs, tool exception
handling, and a final `submit` tool. The same beta also introduced a typed,
provider-neutral LM request and response boundary.

This is the strongest evidence for a richer execution substrate. Official DSPy
terminology still calls `ReActV2` an agent module and describes the surrounding
pieces individually. It does not call the whole layer an agent harness.

Sources:

- [DSPy 3.2.0 release](https://github.com/stanfordnlp/dspy/releases/tag/3.2.0)
- [DSPy 3.3.0b1 release](https://github.com/stanfordnlp/dspy/releases/tag/3.3.0b1)
- [official DSPy home page](https://dspy.ai/)

## Do Users Still Write Prompts?

Usually they should not hand-author provider prompt templates. DSPy's current
home page says to express tasks as signatures, compose them with modules and
ordinary code, and compile programs with optimizers. ReAct accepts tools as
functions. Adapters render signatures, demonstrations, history, tool schemas,
and output constraints for a provider.

Prompts have not disappeared. They are parameters and generated artifacts:

- Signature instructions and field descriptions supply natural-language task
  information.
- Tool names and descriptions influence tool selection.
- Optimizers such as GEPA evolve textual components.
- Advanced users can supply custom instruction proposers, adapter behavior, or
  other textual guidance.

The accurate claim is not "no prompts." It is "no hand-maintained prompt
plumbing for the normal path." Users define behavior, examples, tools, metrics,
and constraints; DSPy constructs and can optimize the provider-facing prompts.

Sources:

- [official home page](https://dspy.ai/)
- [official optimizer guide](https://dspy.ai/learn/optimization/optimizers/)
- [official GEPA reference](https://dspy.ai/api/optimizers/GEPA/overview/)

## Adversarial Review

### "Everything is an agent" is too broad

Extraction, classification, evaluation, and deterministic multi-stage programs
often need no autonomous tool-selection loop. Calling them agents hides useful
differences in control flow and failure modes. DSPy's own home page presents
Extract, Agent, Pipeline, Multimodal, and Optimize as distinct cases.

### "Harness, not workflow" imports terminology DSPy does not own

The harness concept can clarify production responsibilities, but using it as
though it were an upstream DSPy abstraction would misstate the source material.
Use it as a defined architectural lens, followed immediately by the concrete
DSPy.rb components that provide the behavior.

### "Nobody writes prompts" overstates the abstraction

Developers still write signature instructions, field descriptions, tool
descriptions, examples, metrics, and sometimes custom optimizer guidance. DSPy
reduces direct prompt-template maintenance; it does not remove natural-language
specification from the system.

### Optimization does not erase engineering

GEPA and RL need objectives, data or rollouts, budgets, and evaluation. Tool
execution still needs permissions, validation, error handling, and traces.
Optimization can improve a defined program, but it cannot choose the right
product objective or make an unsafe tool safe.

## Editorial Position for DSPy.rb

Use this hierarchy throughout the corpus:

1. **AI system or program** for the complete application behavior.
2. **Module** for a reusable DSPy execution component.
3. **Agent** for a module that lets the model choose actions or tools in a loop.
4. **Pipeline or workflow** for developer-authored composition and control flow.
5. **Tool** for a typed operation available to an agent.
6. **Harness** for the defined runtime envelope around an agent, never as an
   unexplained synonym for DSPy itself.
7. **Optimizer** for compilation against metrics, examples, feedback, or
   rollouts.

Preferred messages:

- Define the task and its result; let adapters construct provider prompts.
- Add a reasoning strategy or tools without rewriting the task contract.
- Compose modules with Ruby control flow.
- Evaluate the complete program, then optimize its instructions,
  demonstrations, or other supported parameters.
- Treat agents as programs with a tool-selection loop, not as a replacement for
  every pipeline.
- Treat the harness as engineering: tool boundaries, state, traces, errors,
  permissions, and evaluation.

Avoid:

- "Workflows are dead" or "everything is an agent."
- "DSPy.rb is an agent harness" without defining the claim.
- "Never write prompts again."
- Describing deterministic composition as agent autonomy.
- Claiming agent or tool optimization that DSPy.rb does not implement.

## Inference

The following is an inference from the sources, not official DSPy language:

DSPy's direction is converging on an **optimizable agent runtime** inside a
broader programming model. Native tool calls, structured history, typed LM
boundaries, sandboxes, streaming, tracing, and optimizer composition are the
pieces the industry often groups under "agent harness." DSPy keeps those pieces
available to non-agent programs too. DSPy.rb should preserve that broader model
while making its agent story much easier to see.
