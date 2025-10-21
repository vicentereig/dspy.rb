# MIPROv2 Implementation Spike Notes

Goals for the next iteration on `dspy-miprov2`:

- **Minibatch parity:** Port the minibatch evaluation loop from Python (candidate batching, full-eval cadence, adaptive batch sizing) into the Ruby teleprompter. Keep the interfaces compatible with existing spec fixtures.
- **Acquisition functions:** Replace the current UCB-only strategy with a pluggable acquisition layer (UCB, Expected Improvement, Probability of Improvement) leveraging the new Gaussian Process backend. Ensure Sorbet signatures stay tight.
- **Teacher / task split:** Mirror upstream support for separate prompt/task models and teacher hooks. Audit `examples/ade_optimizer_*` to exercise the split.
- **Logging + metrics:** Align emitted events and stored trial logs with Python’s schema so downstream visualizers remain compatible.
- **Testing:** Add unit specs for the Gaussian Process wrapper (Cholesky stability, mean/std outputs) and integration specs that cover minibatch runs, teacher interactions, and fallbacks when `numo-tiny_linalg` is unavailable.

Dependencies are already isolated in the new gem; prototype work should happen within the `dspy-miprov2` namespace so the core gem stays slim.
