# DSPy.rb Port Positioning

## Verdict

DSPy.rb began as a port of DSPy, but the unqualified description "the Ruby port of Stanford's DSPy framework" no longer fits. DSPy.rb now evolves as an independent Ruby-native implementation of DSPy's programming model. It is neither API-compatible with DSPy nor an official DSPy project.

Use this high-level description:

> DSPy.rb brings DSPy's signature, module, agent, and optimizer model to Ruby, with Sorbet types and Ruby-native integrations.

For shorter contexts, use:

> A Ruby-native implementation of DSPy's programming model.

## Criteria

An unqualified port normally maintains a defined relationship to an upstream implementation:

- Major upstream components have downstream counterparts.
- Public APIs translate predictably between languages.
- Behavioral semantics and serialized artifacts are compatible or intentionally mapped.
- Upstream changes follow a repeatable porting process.
- Feature parity, or a documented parity subset, remains a maintenance goal.

An independent implementation can share the original project's ideas while redesigning APIs for its language, selecting a different feature set, introducing original architecture, and evolving without compatibility or parity guarantees.

## Strongest Case for "Port"

The lineage is real. The repository's first README described DSPy.rb as "A port of the DSPy library to Ruby." DSPy.rb retains DSPy's central concepts: signatures, modules, predictions, agents, examples, metrics, and optimizers. The upstream project also uses "community ports" as a category for implementations in other languages.

"Began as a port," "conceptual port," and "Ruby implementation of DSPy's programming model" are therefore defensible when the context calls for historical attribution.

## Strongest Case Against "Port"

The current compatibility surface is substantially different. DSPy.rb uses Sorbet-backed signatures, Ruby-specific provider gems, typed Ruby tools and toolsets, Ruby control flow, its own persistence formats, and independent implementations of agents and optimizers. Python examples cannot be translated mechanically, supported modules differ, and neither public API nor serialized-artifact compatibility is promised.

The phrase "the Ruby port" also risks implying an official or uniquely endorsed relationship that this repository does not establish.

## Usage

Prefer:

- "DSPy.rb brings DSPy's programming model to Ruby."
- "DSPy.rb is a Ruby-native implementation of DSPy's programming model."
- "DSPy.rb's GEPA implementation" when discussing an algorithm implemented here.
- "DSPy.rb began as a port" when discussing project history.
- "DSPy" or "the original DSPy project" when attributing upstream research and APIs.

Avoid:

- "The Ruby port of Stanford's DSPy framework."
- "Stanford DSPy for Ruby."
- "A drop-in Ruby port."
- "The official Ruby implementation."
- "Feature-compatible with DSPy."

Historical records such as changelogs and ADRs should remain unchanged unless their wording creates a current product claim.

## Primary Sources

- [DSPy repository](https://github.com/stanfordnlp/dspy)
- [DSPy documentation](https://dspy.ai/)
- [DSPy programming modules](https://dspy.ai/learn/programming/modules/)
- [DSPy releases, including references to community ports](https://github.com/stanfordnlp/dspy/releases)
- [DSPy.rb initial project commit](https://github.com/vicentereig/dspy.rb/commit/94784081fb6371f836f27a68cd2d40d0492e977a)
- [DSPy.rb Python comparison](../src/advanced/python-comparison.md)
