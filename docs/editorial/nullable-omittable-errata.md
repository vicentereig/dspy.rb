# Nullable and omittable errata policy

Current guides, examples, package documentation, and generated `llms*.erb` sources must use the canonical definitions in [Signatures](../src/core-concepts/signatures.md#nullable-and-omittable-fields): `T.nilable` permits `nil`; a DSPy signature `default:` permits omission.

Historical articles remain dated records. Do not silently rewrite an article merely because it contains a nilable declaration. Add a visible erratum only when the surrounding prose says that nilability alone makes a DSPy signature field omittable, or when a runnable historical example relies on omission. The erratum should link to the canonical explanation and preserve the original text unless it is unsafe to run.

The July 2026 audit found nilable declarations in historical articles, but no prose that equates nilability with omission. No article errata were required.
