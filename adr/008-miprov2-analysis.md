# ADR 008: MIPROv2 Python Implementation Analysis

**Status:** In Progress - Layer 4.2 Complete
**Date:** 2025-10-13
**Context:** Analysis and implementation of Python DSPy MIPROv2

## Overview

This document analyzes the Python MIPROv2 implementation to identify its architecture, dependencies, and key patterns.

## File Dependencies

### Core Implementation Files

**Main Implementation:**
- `/dspy/dspy/teleprompt/mipro_optimizer_v2.py` (783 lines)
  - Main MIPROv2 class
  - Implements three-phase optimization algorithm

**Base Classes:**
- `/dspy/dspy/teleprompt/teleprompt.py`
  - Base `Teleprompter` class with `compile()` interface
  - Simple base class with ~33 lines

**Utilities:**
- `/dspy/dspy/teleprompt/utils.py` (467 lines)
  - `create_minibatch(trainset, batch_size, rng)`
  - `eval_candidate_program(batch_size, trainset, program, evaluate, rng)`
  - `get_program_with_highest_avg_score(param_score_dict, fully_evaled_param_combos)`
  - `save_candidate_program(program, log_dir, trial_num, note)`
  - `create_n_fewshot_demo_sets(student, num_sets, trainset, ...)`
  - `get_signature(predictor)` / `set_signature(predictor, sig)`
  - Uses `BootstrapFewShot` and `LabeledFewShot` from `bootstrap.py`

**Instruction Proposal:**
- `/dspy/dspy/propose/grounded_proposer.py` (440 lines)
  - `GroundedProposer` class (inherits from `Proposer`)
  - `GenerateModuleInstruction` class (dspy.Module)
  - Internal signatures: `DescribeProgram`, `DescribeModule`, `GenerateSingleModuleInstruction`
  - Configuration flags: `program_aware`, `data_aware`, `tip_aware`, `fewshot_aware`

- `/dspy/dspy/propose/dataset_summary_generator.py`
  - `create_dataset_summary()` function

- `/dspy/dspy/propose/utils.py`
  - `create_example_string(fields, example)`
  - `create_predictor_level_history_string(program, pred_i, trial_logs, max_history)`
  - `get_dspy_source_code(program)`
  - `strip_prefix(text)`

### External Dependencies

**Critical:**
- `optuna` - Bayesian optimization library
  - `optuna.samplers.TPESampler` - Tree-structured Parzen Estimator
  - `optuna.create_study()` - Creates optimization study
  - `optuna.trial.create_trial()` - Manual trial injection
  - `optuna.trial.Trial` - Trial object for suggesting parameters

**Standard:**
- `numpy` - Numerical operations and averaging
- `dspy.evaluate.Evaluate` - Program evaluation
- `dspy.primitives.Example` - Training examples
- `dspy.primitives.Module` - Base program class

## Class Dependency Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         EXTERNAL LIBRARIES                       │
├─────────────────────────────────────────────────────────────────┤
│  • optuna (Bayesian optimization - TPESampler)                  │
│  • numpy (numerical operations)                                  │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────┴───────────────────────────────────┐
│                      MIPROv2                                     │
│                (mipro_optimizer_v2.py)                          │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ Responsibilities:                                          │ │
│  │ • compile(student, trainset, valset, ...)                 │ │
│  │ • _bootstrap_fewshot_examples()                           │ │
│  │ • _propose_instructions()                                 │ │
│  │ • _optimize_prompt_parameters()                           │ │
│  │ • _perform_full_evaluation()                              │ │
│  │ • _select_and_insert_instructions_and_demos()             │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────┬──────────────┬──────────────┬────────────────────┘
              │              │              │
    inherits  │    uses      │    uses      │    uses
              ▼              ▼              ▼
    ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐
    │Teleprompter │  │   Evaluate   │  │ GroundedProposer │
    │(base class) │  │   (dspy)     │  │  (propose/)      │
    └─────────────┘  └──────────────┘  └────────┬─────────┘
         │                                       │
         │uses                          inherits│    uses
         ▼                                       ▼
    ┌─────────────┐                    ┌─────────────────┐
    │   Module    │                    │    Proposer     │
    │   Example   │                    │  (base class)   │
    │(primitives) │                    └─────────────────┘
    └─────────────┘                             │
                                                │uses
                                                ▼
                          ┌────────────────────────────────────┐
                          │  GenerateModuleInstruction         │
                          │  (internal dspy.Module)            │
                          │  ┌──────────────────────────────┐ │
                          │  │ • DescribeProgram           │ │
                          │  │ • DescribeModule            │ │
                          │  │ • GenerateSingleModule...   │ │
                          │  └──────────────────────────────┘ │
                          └────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    UTILITY FUNCTIONS (utils.py)                  │
├─────────────────────────────────────────────────────────────────┤
│  Called by MIPROv2:                                             │
│  • create_minibatch(trainset, batch_size, rng)                  │
│  • eval_candidate_program(batch_size, trainset, program, ...)   │
│  • get_program_with_highest_avg_score(param_score_dict, ...)    │
│  • save_candidate_program(program, log_dir, trial_num)          │
│  • get_signature(predictor) / set_signature(...)                │
│  • create_n_fewshot_demo_sets(student, num_sets, trainset, ...) │
│                                                                  │
│  These use:                                                      │
│  • BootstrapFewShot (from bootstrap.py)                         │
│  • LabeledFewShot (from bootstrap.py)                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│              PROPOSER UTILITIES (propose/utils.py)               │
├─────────────────────────────────────────────────────────────────┤
│  Called by GroundedProposer:                                    │
│  • create_example_string(fields, example)                        │
│  • create_predictor_level_history_string(program, pred_i, ...)  │
│  • get_dspy_source_code(program)                                │
│  • strip_prefix(text)                                            │
│                                                                  │
│  Also uses:                                                      │
│  • create_dataset_summary(trainset, ...) - from                 │
│    dataset_summary_generator.py                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
1. MIPROv2.compile() receives:
   → student (Module), trainset, valset

2. Phase 1: _bootstrap_fewshot_examples()
   → calls create_n_fewshot_demo_sets()
   → returns demo_candidates dict

3. Phase 2: _propose_instructions()
   → creates GroundedProposer instance
   → calls propose_instructions_for_program()
   → returns instruction_candidates dict

4. Phase 3: _optimize_prompt_parameters()
   → creates Optuna study with TPESampler
   → defines objective() function (closure)
   → objective() calls:
     - _select_and_insert_instructions_and_demos()
     - eval_candidate_program()
     - _perform_full_evaluation() (if minibatch)
   → study.optimize(objective, n_trials)
   → returns best_program with attached metadata
```

## Key Data Structures

### trial_logs
```python
trial_logs = {
  trial_num: {
    'full_eval_program_path': str,
    'full_eval_score': float,
    'mb_score': float,
    'total_eval_calls_so_far': int,
    '0_predictor_instruction': int,  # index chosen
    '0_predictor_demos': int,        # index chosen
    'full_eval_program': Module,
    'mb_program': Module
  }
}
```

### param_score_dict
```python
param_score_dict = {
  "0,1,2": [  # comma-separated param indices
    (score, program, raw_params),
    (score, program, raw_params),
    ...
  ]
}
```

**Purpose:** Tracks all scores for each parameter combination to calculate averages.

### fully_evaled_param_combos
```python
fully_evaled_param_combos = {
  "0,1,2": {
    'program': Module,
    'score': float
  }
}
```

**Purpose:** Prevents re-evaluating the same configuration on full dataset.

### demo_candidates
```python
demo_candidates = {
  predictor_idx: [
    [demo1, demo2, ...],  # set 0
    [demo1, demo2, ...],  # set 1
    ...
  ]
}
```

### instruction_candidates
```python
instruction_candidates = {
  predictor_idx: [
    "instruction 0",  # Always current instruction
    "instruction 1",
    ...
  ]
}
```

## Critical Algorithm Details

### Optuna Integration (Python lines 437-589)

```python
# Create study with TPE sampler
sampler = optuna.samplers.TPESampler(seed=seed, multivariate=True)
study = optuna.create_study(direction="maximize", sampler=sampler)

# Add default program as baseline
trial = optuna.trial.create_trial(
    params=default_params,
    distributions=self._get_param_distributions(...),
    value=default_score
)
study.add_trial(trial)

# Optimize
study.optimize(objective, n_trials=num_trials)
```

**What TPESampler provides:**
- Builds probabilistic model P(score | parameters)
- Uses Expected Improvement acquisition function
- Handles categorical parameters natively
- Balances exploration vs exploitation
- Updates after each trial

### Minibatching Strategy (Python lines 552-571)

```python
# Every trial: evaluate on minibatch
batch_size = minibatch_size if minibatch else len(valset)
score = eval_candidate_program(batch_size, valset, ...)

# Every N trials: full evaluation
if minibatch and (
    (trial_num % (minibatch_full_eval_steps + 1) == 0) or
    (trial_num == (adjusted_num_trials - 1))
):
    # Get best-averaging config from minibatch trials
    highest_mean_program, mean_score = get_program_with_highest_avg_score(
        param_score_dict,
        fully_evaled_param_combos
    )

    # Evaluate on full dataset
    full_eval_score = eval_candidate_program(len(valset), valset, ...)

    # Feed back to Optuna
    trial = optuna.trial.create_trial(params=params, value=full_eval_score)
    study.add_trial(trial)
```

**Efficiency gain:** Evaluate 100 configs on 35 examples (3,500 LM calls) + 20 full evals on 300 examples (6,000 LM calls) = 9,500 total LM calls, instead of 100 full evals = 30,000 LM calls.

### Bootstrap Demo Set Creation (Python lines 363-417)

Uses specific seeds for reproducibility:
- Seed -3: Zero-shot (no demos)
- Seed -2: Labeled few-shot only
- Seed -1: Unshuffled bootstrapped few-shot
- Seed 0+: Shuffled bootstrapped few-shot with random demo count

### GroundedProposer Configuration (Python lines 271-327)

Initialization accepts 4 awareness flags:
```python
proposer = GroundedProposer(
    program=program,
    trainset=trainset,
    prompt_model=self.prompt_model,
    program_aware=program_aware_proposer,       # Include program code
    use_dataset_summary=data_aware_proposer,     # Include data summary
    use_task_demos=fewshot_aware_proposer,       # Include few-shot examples
    use_tip=tip_aware_proposer,                  # Include prompting tip
    # ...
)
```

Also has TIPS dictionary (line 17-24):
```python
TIPS = {
    "none": "",
    "creative": "Don't be afraid to be creative...",
    "simple": "Keep the instruction clear and concise.",
    "description": "Make sure your instruction is very informative...",
    "high_stakes": "The instruction should include a high stakes scenario...",
    "persona": 'Include a persona that is relevant to the task...',
}
```

## Key Insights

1. **Optuna is fundamental** - The Python implementation is built around Optuna's API and capabilities, particularly the TPESampler for Bayesian optimization.

2. **Minibatching is sophisticated** - It's not just "evaluate on smaller batches." The strategy involves:
   - Track scores for each parameter combination across multiple trials
   - Calculate averages to identify promising configurations
   - Periodically evaluate best-averaging configurations on full dataset
   - Feed full evaluation results back to the optimizer for learning

3. **Data structures are critical** - The specific structure of `trial_logs`, `param_score_dict`, and `fully_evaled_param_combos` is essential for the algorithm to work correctly. These enable parameter averaging and prevent redundant evaluations.

4. **Proposer has multiple awareness modes** - `GroundedProposer` has many configuration options and internal LM calls. The four awareness flags (`program_aware`, `data_aware`, `tip_aware`, `fewshot_aware`) significantly affect instruction quality.

5. **Seed-based bootstrapping** - The bootstrap phase uses specific seeds (-3, -2, -1, 0+) to create diverse demo sets with different strategies (zero-shot, labeled-only, unshuffled, shuffled).

6. **Closure pattern for optimization** - The `objective()` function captures state via closure, allowing Optuna to call it repeatedly while maintaining shared state across trials.

## Ruby-Specific Design Decisions

### T::Enum for Bootstrap Strategies

**Decision**: Use Sorbet's `T::Enum` for bootstrap strategies instead of Python's magic number seeds.

**Rationale:**
1. **Type Safety**: Sorbet provides compile-time and runtime type checking
2. **Self-Documentation**: Enum values are self-explanatory (`ZeroShot` vs `-3`)
3. **IDE Support**: Better autocomplete and refactoring support
4. **Ruby Idioms**: Enums are more idiomatic Ruby than magic numbers
5. **Prevents Errors**: Can't pass invalid seed values

**Implementation:**
```ruby
class BootstrapStrategy < T::Enum
  enums do
    ZeroShot = new      # No demos (Python seed = -3)
    LabeledOnly = new   # Labeled examples only (Python seed = -2)
    Unshuffled = new    # Bootstrapped, no shuffle (Python seed = -1)
    Shuffled = new      # Bootstrapped with shuffle (Python seed >= 0, requires separate seed param)
  end
end
```

**For `Shuffled` strategy**: Still requires a separate integer `seed` parameter for the random number generator, maintaining Python compatibility for reproducibility.

### Inline Bootstrap Logic

**Decision**: Implement bootstrap strategies inline in `create_n_fewshot_demo_sets` rather than using separate `BootstrapFewShot`/`LabeledFewShot` teleprompter classes.

**Rationale:**
1. **Pragmatic**: These teleprompters don't exist in Ruby yet
2. **Simpler**: Reduces complexity for initial MIPROv2 implementation
3. **Maintainable**: All bootstrap logic in one place
4. **Future-proof**: Can extract to separate classes later if needed

**Trade-offs:**
- **Pro**: Faster implementation, easier testing, less code
- **Con**: Less modular than Python, harder to reuse bootstrap logic elsewhere
- **Mitigation**: Extract to teleprompter classes in future refactor if needed

## Bottom-Up Implementation Plan

### Overview

To properly implement MIPROv2 in Ruby, we recommend a bottom-up approach that builds from foundational utilities to complex components. This approach:
- Minimizes complexity at each step
- Enables incremental testing and validation
- Establishes solid foundations before building higher-level abstractions
- Reduces risk by tackling pure functions before stateful components

### Implementation Layers

#### Layer 1: Foundation (Already Exists)
✅ **Primitives** - These should already be in the Ruby codebase:
- `DSPy::Module` - Base class for DSPy programs
- `DSPy::Example` - Training example representation
- `DSPy::Evaluate` - Program evaluation system

**Action:** Verify these exist and match Python behavior.

#### Layer 2: Base Classes (Verify Existence)
✅ **Base teleprompter and proposer:**
- `DSPy::Teleprompt::Teleprompter` - Base optimizer class with `compile()` interface
- `DSPy::Propose::Proposer` - Base class for instruction proposers

**Action:** Verify these exist and have the correct interface.

#### Layer 3: Utility Functions (START HERE) 🎯

**File:** `lib/dspy/teleprompt/utils.rb`

Core utilities used by MIPROv2. These are pure functions with no LM calls (except for bootstrap functions):

**3.1 Simple Utilities (Start with these):**
- `create_minibatch(trainset, batch_size, rng)` - Random sampling from dataset
- `get_signature(predictor)` - Extract signature from predictor (may already exist)
- `set_signature(predictor, updated_signature)` - Update predictor signature (may already exist)

**3.2 Program Evaluation:**
- `eval_candidate_program(batch_size, trainset, candidate_program, evaluate, rng)` - Evaluate program on minibatch or full set

**3.3 Minibatch Scoring (CRITICAL):**
- `get_program_with_highest_avg_score(param_score_dict, fully_evaled_param_combos)` - Find best-averaging configuration from trials
  - This is the core of the sophisticated minibatching strategy
  - Takes `param_score_dict` with multiple scores per config
  - Calculates averages and returns best unexplored config
  - Python implementation: lines 118-143 in `utils.py`

**3.4 Program Persistence:**
- `save_candidate_program(program, log_dir, trial_num, note)` - Save program to disk for inspection

**3.5 Bootstrap Functions:**
- `create_n_fewshot_demo_sets(student, num_candidate_sets, trainset, ...)`
  - Most complex utility function
  - **Ruby Design Decision**: Use `T::Enum` for bootstrap strategies instead of magic number seeds
  - Bootstrap strategies (Ruby `BootstrapStrategy` enum):
    - `ZeroShot` - No demonstrations (Python seed = -3)
    - `LabeledOnly` - Labeled examples only (Python seed = -2)
    - `Unshuffled` - Bootstrapped without shuffling (Python seed = -1)
    - `Shuffled` - Bootstrapped with shuffle and random size (Python seed >= 0)
  - **Implementation approach**: Inline bootstrap logic rather than using separate `BootstrapFewShot`/`LabeledFewShot` teleprompters (which don't exist in Ruby yet)
  - Python implementation: lines 328-417 in `utils.py`

**File:** `lib/dspy/propose/utils.rb`

Proposer-specific utilities:

- `create_example_string(fields, example)` - Format example for prompt
- `create_predictor_level_history_string(program, pred_i, trial_logs, max_history)` - Format trial history
- `get_dspy_source_code(program)` - Extract program source code (for program-aware proposer)
- `strip_prefix(text)` - Clean LM output by removing field prefixes

**Rationale for starting here:**
1. Pure functions are easiest to implement and test
2. No complex state management or LM interactions (except bootstrap)
3. Foundation for all higher layers
4. Can test each function in isolation with unit tests
5. `get_program_with_highest_avg_score` is critical for proper minibatching

#### Layer 4: Proposer Components

**4.1 Dataset Summary Generator**

**File:** `lib/dspy/propose/dataset_summary_generator.rb`

- `create_dataset_summary(trainset, view_data_batch_size, prompt_model)` - Generate dataset description
  - Uses LM to summarize dataset characteristics
  - Required for `data_aware` proposer mode

**4.2 Grounded Proposer**

**File:** `lib/dspy/propose/grounded_proposer.rb`

**Internal DSPy Signatures:**
- `DescribeProgram` - Signature for describing overall program purpose
- `DescribeModule` - Signature for describing individual module purpose
- `GenerateSingleModuleInstruction` - Dynamic signature with conditional fields based on awareness flags

**TIPS Dictionary:**
```ruby
TIPS = {
  "none" => "",
  "creative" => "Don't be afraid to be creative when creating the new instruction!",
  "simple" => "Keep the instruction clear and concise.",
  "description" => "Make sure your instruction is very informative and descriptive.",
  "high_stakes" => "The instruction should include a high stakes scenario...",
  "persona" => "Include a persona that is relevant to the task..."
}
```

**GenerateModuleInstruction Class:**
- Internal DSPy module that generates instructions
- Uses the three signatures above
- Configurable with awareness flags

**GroundedProposer Class:**
- Configuration flags: `program_aware`, `data_aware`, `tip_aware`, `fewshot_aware`
- `propose_instructions_for_program(trainset, program, demo_candidates, trial_logs, N)` - Main entry point
- `propose_instruction_for_predictor(...)` - Generate single instruction
- Uses `init_temperature` for LM calls
- Randomly selects tips when `set_tip_randomly=true`

**Python reference:** Lines 1-440 in `grounded_proposer.py`

#### Layer 5: Main Optimizer

**File:** `lib/dspy/teleprompt/mipro_v2.rb`

**MIPROv2 Class:**

**Phase 1: Bootstrap** (depends on Layer 3 utils)
- `_bootstrap_fewshot_examples(program, trainset, seed, teacher)`
- Calls `create_n_fewshot_demo_sets` from utils
- Returns `demo_candidates` dict

**Phase 2: Propose Instructions** (depends on Layer 4)
- `_propose_instructions(program, trainset, demo_candidates, ...)`
- Creates `GroundedProposer` instance with awareness flags
- Returns `instruction_candidates` dict

**Phase 3: Optimize** (depends on Layers 3-4)
- `_optimize_prompt_parameters(program, instruction_candidates, demo_candidates, evaluate, valset, ...)`
- **Decision point:** Optuna vs custom optimization
- Uses sophisticated minibatching with `param_score_dict` and `get_program_with_highest_avg_score`
- Tracks trials in `trial_logs` with detailed metadata
- Saves candidate programs periodically
- Returns best program with attached metadata

**Key Data Structures:**
- `trial_logs` - Detailed trial history (see ADR Key Data Structures section)
- `param_score_dict` - Scores per parameter combination for averaging
- `fully_evaled_param_combos` - Already fully-evaluated configs
- `demo_candidates` - Bootstrap results per predictor
- `instruction_candidates` - Proposed instructions per predictor

**Python reference:** Lines 1-783 in `mipro_optimizer_v2.py`

### Recommended Implementation Order

1. **Layer 3.1: Simple utilities** (1-2 days)
   - Start with `create_minibatch`
   - Verify/implement `get_signature` and `set_signature`
   - Add tests for each

2. **Layer 3.2-3.3: Evaluation and scoring** (2-3 days)
   - Implement `eval_candidate_program`
   - Implement `get_program_with_highest_avg_score` (CRITICAL)
   - Add comprehensive tests with mock data

3. **Layer 3.4-3.5: Persistence and bootstrap** (3-4 days)
   - Implement `save_candidate_program`
   - Implement `create_n_fewshot_demo_sets` (most complex utility)
   - Test with actual DSPy programs

4. **Layer 3 (Proposer utils):** (1-2 days)
   - Implement proposer utility functions
   - Test string formatting and history generation

5. **Layer 4.1: Dataset summary** (1 day)
   - Implement `create_dataset_summary`
   - Test with VCR

6. **Layer 4.2: Grounded proposer** (5-7 days)
   - Implement TIPS dictionary
   - Implement internal signatures
   - Implement `GenerateModuleInstruction`
   - Implement `GroundedProposer` with all awareness flags
   - Test each awareness mode separately

7. **Layer 5: MIPROv2 main class** (7-10 days)
   - Implement three-phase structure
   - Implement data structures (`trial_logs`, `param_score_dict`, etc.)
   - **Decide on optimization strategy** (see Options below)
   - Implement minibatching with parameter averaging
   - Add integration tests

8. **Documentation and validation** (3-5 days)
   - Document differences from Python
   - Create benchmarks
   - Compare results with Python implementation

### Total Estimate: 4-6 weeks for complete implementation

### Optimization Strategy Options

When reaching Layer 5, you'll need to decide on the optimization approach:

**Option A: Random Search (Simplest)**
- Randomly select parameter combinations
- Keep sophisticated minibatching with averaging
- Document as "Random Search MIPROv2"
- Est: 2-3 days for optimization loop

**Option B: Greedy + Epsilon-Greedy**
- Mix exploitation (best so far) with exploration (random)
- Use epsilon parameter to control exploration rate
- Simple, interpretable, no external dependencies
- Est: 3-4 days for optimization loop

**Option C: Python Optuna Subprocess**
- Call Python Optuna via subprocess
- Keep evaluation in Ruby
- Requires Python + Optuna installed
- Est: 5-7 days (handling interop)

**Option D: Pure Ruby Bayesian**
- Research Ruby optimization libraries
- Implement proven algorithm (Thompson Sampling, GP-UCB, etc.)
- Requires validation against benchmarks
- Est: 2-3 weeks (research + implementation + validation)

**Recommendation:** Start with Option A or B for v1, which maintains algorithm fidelity for everything except the optimization strategy. This allows testing and validation of all other components before tackling the complex optimization decision.

## References

- Python implementation: `/dspy/dspy/teleprompt/mipro_optimizer_v2.py`
- Utils: `/dspy/dspy/teleprompt/utils.py`
- Proposer: `/dspy/dspy/propose/grounded_proposer.py`
- Optuna documentation: https://optuna.readthedocs.io/

---

## Implementation Status (Layer 3.5 Complete)

**Date:** 2025-10-13
**Status:** ✅ Complete
**Branch:** `feature/miprov2-layer3.5-bootstrap`

### What Was Implemented

#### 1. Python-Compatible `create_n_fewshot_demo_sets` (Complete Replacement)

**File:** `lib/dspy/teleprompt/utils.rb`

**Signature:**
```ruby
def self.create_n_fewshot_demo_sets(
  student,                     # DSPy::Module to bootstrap
  num_candidate_sets,          # Total number of demo sets to create
  trainset,                    # Training examples
  max_bootstrapped_demos: 3,   # Max bootstrapped demos per set
  max_labeled_demos: 3,        # Max labeled demos to prepend
  min_num_samples: 1,          # Min samples for shuffled strategy
  metric: nil,                 # Optional validation metric
  teacher_settings: {},        # Reserved for future use
  seed: nil,                   # Random seed for reproducibility
  include_non_bootstrapped: true,  # Include ZeroShot and LabeledOnly
  labeled_sample: true         # Whether to sample labeled examples randomly
) -> Hash{Integer => Array<Array<DSPy::FewShotExample>>}
```

**Return Value:** Dictionary mapping predictor indices to arrays of demo sets:
```ruby
{
  0 => [
    [demo1, demo2, ...],  # Demo set 0 (ZeroShot)
    [demo1, demo2, ...],  # Demo set 1 (LabeledOnly)
    [demo1, demo2, ...],  # Demo set 2 (Unshuffled)
    [demo1, demo2, ...]   # Demo set 3+ (Shuffled with different seeds)
  ]
}
```

**Implementation Strategy:**
- **Inline bootstrap logic** - No separate `BootstrapFewShot`/`LabeledFewShot` teleprompters
- **Seed-based loop** - Iterates from seed -3 to num_candidate_sets
- **4 Bootstrap Strategies:**
  1. **ZeroShot** (seed=-3): Empty demonstrations for zero-shot learning
  2. **LabeledOnly** (seed=-2): Use trainset labels directly without bootstrapping
  3. **Unshuffled** (seed=-1): Bootstrap with original trainset order
  4. **Shuffled** (seed>=0): Bootstrap with shuffled trainset and random demo count

**Helper Methods Added:**
```ruby
create_labeled_demos(trainset, max_labeled, labeled_sample, rng)
create_bootstrapped_demos(student, trainset, max_bootstrapped, max_labeled, metric)
extract_output_fields_for_demo(prediction_hash, signature_class)
```

**Tests:** 18 comprehensive tests covering all strategies, reproducibility, edge cases
- File: `spec/unit/teleprompt/utils_bootstrap_strategies_spec.rb`
- All passing (18/18)

#### 2. MIPROv2 Updated to Use New Interface

**File:** `lib/dspy/teleprompt/mipro_v2.rb`

**Changes:**
- `phase_1_bootstrap` returns `Hash{predictor_idx => [[demos]]}` instead of `BootstrapResult`
- `phase_2_propose_instructions` uses `demo_candidates` parameter
- `phase_3_optimize` uses `demo_candidates` parameter
- `generate_candidate_configurations` extracts demo sets from `demo_candidates[0]`
- `build_miprov2_result` creates bootstrap statistics from dict structure

**Backward Compatibility:** None needed - MIPROv2 was already using internal methods

#### 3. SimpleOptimizer Removed (Ruby-only implementation)

**Rationale:** Python DSPy does not ship a SimpleOptimizer equivalent. To keep the Ruby surface aligned and reduce maintenance burden, the Ruby-only implementation, its tests, and documentation were removed.

**Changes:**
- Deleted `lib/dspy/teleprompt/simple_optimizer.rb`
- Removed unit specs and documentation under `docs/src/optimization/simple-optimizer.md`
- Updated storage manager specs, docs, and generated outputs to reference supported optimizers only (e.g., MIPROv2, GEPA)

**Backward Compatibility:** Breaking for any consumers relying on `DSPy::Teleprompt::SimpleOptimizer`. Migration path: adopt `DSPy::Teleprompt::MIPROv2` or other supported optimizers.

#### 4. Deprecated Classes (Kept for Compatibility)

**BootstrapResult** - Marked as `@deprecated`, kept for backward compatibility in existing tests
**BootstrapConfig** - Still used by `eval_candidate_program` and related methods

### Design Decisions Summary

#### Use T::Enum for Bootstrap Strategies (Instead of Magic Numbers)

**Rationale:**
- Type safety with Sorbet compile-time and runtime checking
- Self-documenting code (`ZeroShot` vs `-3`)
- Better IDE support (autocomplete, refactoring)
- More idiomatic Ruby than magic numbers
- Prevents invalid seed values

**Implementation:**
```ruby
class BootstrapStrategy < T::Enum
  enums do
    ZeroShot = new      # Python seed = -3
    LabeledOnly = new   # Python seed = -2
    Unshuffled = new    # Python seed = -1
    Shuffled = new      # Python seed >= 0, requires separate seed param
  end
end
```

**Note:** While we created the enum, the actual implementation uses the seed-based approach directly for simplicity. The enum remains available for future enhancements.

#### Inline Bootstrap Logic (Not Separate Teleprompters)

**Rationale:**
- `BootstrapFewShot` and `LabeledFewShot` don't exist in Ruby
- Simpler implementation - all logic in one place
- Faster to implement and test
- Easier to maintain initially
- Can extract to separate classes later if needed

**Trade-offs:**
- ✅ Faster implementation
- ✅ Easier testing
- ✅ Less code duplication
- ❌ Less modular than Python
- ❌ Harder to reuse bootstrap logic independently

#### SimpleOptimizer: Ruby-Only Implementation (Removed)

**Finding:** SimpleOptimizer never existed in Python DSPy. To reduce divergence (and maintenance), we removed the Ruby-only implementation in commit `1803397`.

**Historical Context (prior to removal):**
- Combined instruction + few-shot random search in a single optimizer
- Served as a lightweight alternative to MIPROv2 without external dependencies
- Offered a random/grid search strategy with trial-based evaluation

**Current Guidance:** Adopt `DSPy::Teleprompt::MIPROv2` (or future Ruby parity optimizers) for prompt tuning workflows.

### Testing Strategy

**Unit Tests:**
- `spec/unit/teleprompt/utils_bootstrap_strategies_spec.rb` - 18 tests for new interface
- `spec/unit/teleprompt/bootstrap_strategy_spec.rb` - 5 tests for T::Enum
- `spec/unit/teleprompt/utils_spec.rb` - Removed old tests (lines 131-349)
- `spec/unit/dspy/teleprompt/utils_spec.rb` - BootstrapResult tests (kept for compatibility)

**Integration Tests:**
- MIPROv2 specs still rely on BootstrapResult mocking (pending cleanup)

**Test Results:**
- All teleprompt unit tests passing (44/44)
- New bootstrap strategies tests passing (18/18)
- BootstrapStrategy enum tests passing (5/5)

### Performance Considerations

**Memory:**
- Dict-based return avoids intermediate BootstrapResult object allocation
- Demo sets are created on-demand per strategy
- FewShotExample objects are immutable and frozen

**Efficiency:**
- Inline bootstrap logic reduces method call overhead
- Seed-based loop allows efficient strategy selection
- Early termination for conditional strategies (ZeroShot, LabeledOnly)

### Future Work

#### Phase 1: Cleanup (Next PR)
- Remove BootstrapResult class entirely
- Update all specs to use dict interface directly
- Remove BootstrapConfig if not needed by other components

#### Phase 2: Optimization Strategy (Future)
- Research Ruby optimization libraries
- Consider implementing simplified Bayesian optimization
- Benchmark against Python MIPROv2 results
- Potentially use external Ruby gems (e.g., `ruby-optimization`)

#### Phase 3: Multi-Predictor Support
- Extend `extract_predictors_from_module` for complex modules
- ✅ Handle per-predictor demo set selection inside MIPROv2 optimization (Ruby parity with Python `_select_and_insert_instructions_and_demos`)
- ⏳ Test with modules containing multiple predictors once predictor discovery helpers land

#### Predictor Discovery Parity (New Gap)
- ✅ Add Python-parity `DSPy::Module#named_predictors` / `#predictors` helpers so optimizers can traverse nested modules.
- ✅ Update composite modules (`DSPy::ReAct`, `DSPy::CodeAct`) to expose their internal predictor pairs (thought → action, code → observe).
- ✅ Add predictor discovery parity specs covering Predict, ReAct, CodeAct, and Utils demo generation.
- ⏳ Verify `DSPy::ChainOfThought` + other composite modules maintain consistent predictor exposure in complex nesting scenarios.

### Documentation Updates Needed
- ✅ Removed SimpleOptimizer references (navigation, guides, optimization index)
- ✅ Updated optimization overview docs to emphasize MIPROv2 / GEPA
- ⏳ After predictor discovery lands, document Layer 5 improvements (instruction history, minibatching knobs, cross-predictor combos)
- ⏳ Author “Optimizing ReAct / CodeAct / ChainOfThought with MIPROv2” section showing configuration tips and limitations
- ⏳ Verify observability/OpenTelemetry instrumentation still emits expected optimization events after refactors and update docs if new metrics are exposed

#### Phase 4: Enhanced Strategies
- Implement metric-based filtering for Shuffled strategy
- Add strategy for curriculum learning (easy to hard)
- Support custom strategy plugins

### Migration Guide (For Future Users)

**Old Interface (Deprecated):**
```ruby
config = DSPy::Teleprompt::Utils::BootstrapConfig.new
config.max_bootstrapped_examples = 4
config.num_candidate_sets = 10

result = Utils.create_n_fewshot_demo_sets(program, trainset, config: config)
demo_sets = result.candidate_sets  # Array<Array<Example>>
```

**New Interface:**
```ruby
demo_candidates = Utils.create_n_fewshot_demo_sets(
  program,
  10,  # num_candidate_sets
  trainset,
  max_bootstrapped_demos: 4
)

demo_sets = demo_candidates[0]  # Get demo sets for first predictor
```

### Commits

1. **feat: add BootstrapStrategy T::Enum and update ADR-008**
2. **feat: replace create_n_fewshot_demo_sets with Python-compatible implementation**
3. **refactor: update MIPROv2 to use new create_n_fewshot_demo_sets interface**
4. **refactor: update SimpleOptimizer to use new interface**
5. **chore: deprecate BootstrapResult and remove obsolete tests**

## Layer 4.1: Dataset Summary Generator - Implementation Complete

**Status:** ✅ Implemented
**Date:** 2025-10-13
**Files:**
- `lib/dspy/propose/dataset_summary_generator.rb` (177 lines)
- `spec/unit/dspy/propose/dataset_summary_generator_spec.rb` (19 tests)
- `spec/integration/dataset_summary_generator_spec.rb` (10 tests)

### Implementation Summary

Implemented the dataset summary generator module for creating concise dataset descriptions used in data-aware instruction proposal.

**Three DSPy Signatures:**
1. `ObservationSummarizer` - Condenses observations into 2-3 sentence summary
2. `DatasetDescriptor` - Generates initial observations from dataset examples
3. `DatasetDescriptorWithPriorObservations` - Iteratively refines observations or returns "COMPLETE"

**Helper Functions:**
- `order_input_keys_in_string` - Ensures consistent ordering of input keys for caching
- `strip_prefix` - Removes common LLM output prefixes ("Answer:", "Output:", etc.)
- `create_dataset_summary` - Main function with iterative refinement algorithm

**Ruby-Specific Adaptations:**

1. **Module vs Class:** Implemented as module with class methods instead of standalone functions
   - More idiomatic Ruby organization
   - Easier to namespace under `DSPy::Propose`

2. **DSPy.with_lm Block:** Uses `DSPy.with_lm(lm)` instead of Python's `dspy.settings.context(lm=...)`
   - Leverages Ruby's Fiber-local storage for LM context
   - Cleaner block-based API

3. **No n/temperature Parameters:** Unlike Python's `dspy.Predict(sig, n=1, temperature=1.0)`, Ruby's `DSPy::Predict.new(sig)` doesn't accept these
   - Temperature/n controlled via global LM configuration or model-level settings
   - Simplifies API while maintaining functionality

4. **Algorithm Implementation:**
   - Processes dataset in configurable batches (default: view_data_batch_size)
   - Maximum 10 refinement calls to prevent excessive API usage
   - Early stopping after 5 consecutive "COMPLETE" responses
   - Graceful error handling with fallback to last successful observations

**Test Coverage:**
- Unit tests: 19 examples covering signatures, helpers, and edge cases
- Integration tests: 10 examples with VCR cassettes covering:
  - Small dataset summaries
  - Verbose output
  - Batch processing
  - Each signature independently
  - Helper functions with real LLM outputs

## Layer 4.2: Enhance GroundedProposer - Detailed Implementation Plan

**Status:** 🔄 In Progress
**Priority:** Remove `max_instruction_length` restriction (user emphasis)

### Current State Analysis

**Ruby GroundedProposer (595 lines):**
- ❌ No `program_aware`, `data_aware`, `tip_aware`, `fewshot_aware` flags
- ❌ Has `max_instruction_length = 200` hardcoded (5 locations total)
- ✅ Basic proposal functionality exists
- ✅ Has Config class but with different flags

**Python GroundedProposer (440 lines):**
- ✅ Has all awareness flags: `program_aware`, `use_dataset_summary` (data_aware), `use_task_demos` (fewshot_aware), `use_tip` (tip_aware)
- ✅ NO max_instruction_length anywhere in Python codebase
- ✅ Integrates with `create_dataset_summary` for data-aware mode
- ✅ Dynamic signature generation based on flags

**max_instruction_length Locations in Ruby Codebase:**
1. `grounded_proposer.rb:25` - Config attr_accessor declaration
2. `grounded_proposer.rb:43` - Default initialization to 200
3. `grounded_proposer.rb:351-352` - Truncation logic (cuts instructions)
4. `grounded_proposer.rb:486` - Normalization in scoring formula
5. `mipro_v2.rb:695` - Feature normalization `/ 100.0`, capped at 200 chars
6. `mipro_v2.rb:796` - Diversity scoring `/ 200.0`

### Implementation Plan (TDD Approach)

#### Phase 1: Match Python's Simpler Behavior ✅ COMPLETE

**Status**: ✅ Completed - 2025-10-13
**Approach**: Instead of removing length limits, we discovered Python has NO instruction length handling at all. We simplified Ruby to match Python's approach.

**Key Finding**: Python DSPy has NO:
- ❌ Instruction truncation
- ❌ Length-based scoring
- ❌ Length-based features
- ❌ Length-based diversity metrics

**Completed Changes:**

**Changes to `lib/dspy/propose/grounded_proposer.rb` (4 locations):**
1. Remove `max_instruction_length` attr_accessor (line 25)
2. Remove initialization `@max_instruction_length = 200` (line 43)
3. Remove truncation logic (lines 351-352) - let LLM-generated instructions be full length
4. Update scoring at line 486:
   ```ruby
   # Before: length_score = [instruction.length, @config.max_instruction_length].min / @config.max_instruction_length.to_f
   # After: Use dynamic normalization based on candidate set's actual max length
   max_length = candidate_instructions.map(&:length).max
   length_score = max_length > 0 ? instruction.length.to_f / max_length : 0.0
   ```

**Changes to `lib/dspy/teleprompt/mipro_v2.rb`:**
1. Line 695: Remove hardcoded 200 cap from feature extraction
   ```ruby
   # Before: features << [instruction.length.to_f / 100.0, 2.0].min  # Instruction length, capped at 200 chars
   # After: features << instruction.length.to_f / 100.0  # Instruction length feature (no cap)
   ```
2. Line 796: Use dynamic normalization for diversity scoring
   ```ruby
   # Before: instruction_diversity = candidate.instruction.length / 200.0
   # After: max_instr_len = state[:candidates].map { |c| c.instruction.length }.max
   #        instruction_diversity = max_instr_len > 0 ? candidate.instruction.length.to_f / max_instr_len : 0.0
   ```

**Test Results:**
- ✅ New tests: 8/8 passing
  - `spec/unit/dspy/propose/grounded_proposer_python_behavior_spec.rb` (5 tests)
  - `spec/unit/dspy/teleprompt/mipro_v2_python_behavior_spec.rb` (3 tests)
  - `spec/integration/grounded_proposer_python_parity_spec.rb` (3 VCR tests)
- ✅ Existing tests: 41/41 GroundedProposer tests passing (3 updated)
- ✅ Existing tests: 59/59 MIPROv2 tests passing (no changes needed)
- ✅ Total: 108/108 tests passing

**Python Parity Achieved:**
- Instructions are never truncated (matches Python)
- Scoring uses only action words and reasoning indicators (matches Python)
- Feature extraction uncapped (matches Python: no length features)
- Diversity based only on few-shot count (matches Python)

#### Phase 2: Add Python-Compatible Awareness Flags

**Refactor Config class in `grounded_proposer.rb`:**
```ruby
class Config
  extend T::Sig

  # Python-compatible awareness flags (match Python parameter names exactly)
  sig { returns(T::Boolean) }
  attr_accessor :program_aware        # Include program source code in context

  sig { returns(T::Boolean) }
  attr_accessor :use_dataset_summary  # Call DatasetSummaryGenerator (Python: use_dataset_summary)

  sig { returns(T::Boolean) }
  attr_accessor :use_task_demos       # Include few-shot examples (Python: use_task_demos)

  sig { returns(T::Boolean) }
  attr_accessor :use_tip              # Include instructional tips (Python: use_tip)

  sig { returns(T::Boolean) }
  attr_accessor :use_instruct_history # Include historical instructions (Python: use_instruct_history)

  # Additional parameters
  sig { returns(Integer) }
  attr_accessor :num_instruction_candidates

  sig { returns(Integer) }
  attr_accessor :view_data_batch_size

  sig { returns(Integer) }
  attr_accessor :num_demos_in_context

  sig { returns(T::Boolean) }
  attr_accessor :set_tip_randomly

  sig { returns(T::Boolean) }
  attr_accessor :set_history_randomly

  sig { returns(Float) }
  attr_accessor :init_temperature

  sig { returns(T::Boolean) }
  attr_accessor :verbose

  sig { void }
  def initialize
    # Match Python defaults
    @program_aware = true
    @use_dataset_summary = true
    @use_task_demos = true
    @use_tip = true
    @use_instruct_history = false  # Not yet implemented in Layer 4.2

    @num_instruction_candidates = 5
    @view_data_batch_size = 10
    @num_demos_in_context = 3
    @set_tip_randomly = true
    @set_history_randomly = false
    @init_temperature = 1.0
    @verbose = false
  end
end
```

**Remove obsolete flags:**
- Delete `use_task_description` (replaced by analysis logic)
- Delete `use_input_output_analysis` (always performed)
- Delete `use_few_shot_examples` (replaced by `use_task_demos`)
- Delete `max_examples_for_analysis` (use `view_data_batch_size` instead)
- Delete `proposal_model` (use global DSPy.lm instead)

**Breaking Changes Note:** Document migration path for existing code using old Config flags.

#### Phase 3: Integrate DatasetSummaryGenerator

**Update GroundedProposer#initialize:**
```ruby
sig do
  params(
    config: T.nilable(Config),
    program: T.nilable(T.untyped),  # DSPy::Module for program_aware mode
    trainset: T.nilable(T::Array[DSPy::Example])
  ).void
end
def initialize(config: nil, program: nil, trainset: nil)
  @config = config || Config.new
  @program = program
  @trainset = trainset

  # Generate dataset summary if data_aware mode enabled (Python: use_dataset_summary)
  @dataset_summary = nil
  if @config.use_dataset_summary && trainset && trainset.any?
    @dataset_summary = DatasetSummaryGenerator.create_dataset_summary(
      trainset,
      @config.view_data_batch_size,
      DSPy.lm,
      verbose: @config.verbose
    )
  end

  # Extract program source code if program_aware mode enabled
  @program_code_string = nil
  if @config.program_aware && program
    @program_code_string = extract_program_source(program)
  end
end
```

**Add helper method:**
```ruby
sig { params(program: T.untyped).returns(T.nilable(String)) }
def extract_program_source(program)
  # Use Ruby introspection to get source code
  # Similar to Python's inspect.getsource()
  if program.class.respond_to?(:source_location)
    file, line = program.class.source_location
    # Read source file and extract class definition
    # Return formatted source code string
  end
rescue => e
  DSPy.logger.warn("Could not extract program source: #{e.message}")
  nil
end
```

#### Phase 4: Update propose_instructions Method

**New method signature:**
```ruby
sig do
  params(
    signature_class: T.class_of(DSPy::Signature),
    examples: T::Array[T.untyped],
    few_shot_examples: T.nilable(T::Array[FewShotExample]),
    current_instruction: T.nilable(String),
    demo_candidates: T.nilable(T::Hash[Integer, T::Array[T::Array[FewShotExample]]]),
    trial_logs: T.nilable(T::Hash[T.untyped, T.untyped])
  ).returns(ProposalResult)
end
def propose_instructions(
  signature_class,
  examples,
  few_shot_examples: nil,
  current_instruction: nil,
  demo_candidates: nil,
  trial_logs: nil
)
  # Use awareness flags to conditionally include context
  context = build_proposal_context(
    signature_class: signature_class,
    examples: examples,
    few_shot_examples: (@config.use_task_demos ? few_shot_examples : nil),
    demo_candidates: (@config.use_task_demos ? demo_candidates : nil),
    dataset_summary: (@config.use_dataset_summary ? @dataset_summary : nil),
    program_code: (@config.program_aware ? @program_code_string : nil),
    tips: (@config.use_tip ? select_tips : nil),
    instruction_history: (@config.use_instruct_history ? format_trial_logs(trial_logs) : nil)
  )

  # Generate instructions using context
  generate_instructions_with_context(signature_class, context)
end
```

**Add context builder:**
```ruby
sig { params(kwargs: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
def build_proposal_context(**kwargs)
  context = {}

  # Add dataset summary if available
  context[:dataset_summary] = kwargs[:dataset_summary] if kwargs[:dataset_summary]

  # Add program code if available
  context[:program_code] = kwargs[:program_code] if kwargs[:program_code]

  # Add tips if enabled
  if kwargs[:tips]
    context[:tips] = @config.set_tip_randomly ? kwargs[:tips].sample : kwargs[:tips].first
  end

  # Add few-shot examples if enabled
  if kwargs[:few_shot_examples] || kwargs[:demo_candidates]
    context[:demonstrations] = format_demonstrations(
      kwargs[:few_shot_examples],
      kwargs[:demo_candidates],
      limit: @config.num_demos_in_context
    )
  end

  # Add instruction history if enabled
  context[:instruction_history] = kwargs[:instruction_history] if kwargs[:instruction_history]

  context
end
```

#### Phase 5: Update MIPROv2 Integration

**Changes to `lib/dspy/teleprompt/mipro_v2.rb`:**

Update `phase_2_propose_instructions`:
```ruby
def phase_2_propose_instructions(program, trainset, demo_candidates)
  # Initialize proposer with program and trainset for awareness modes
  proposer = DSPy::Propose::GroundedProposer.new(
    config: build_proposer_config,
    program: program,
    trainset: trainset
  )

  signature_class = extract_signature_class(program)
  few_shot_examples = demo_candidates&.dig(0)&.flatten&.take(5) || []
  current_instruction = extract_current_instruction(program)

  proposer.propose_instructions(
    signature_class,
    trainset,
    few_shot_examples: few_shot_examples,
    current_instruction: current_instruction,
    demo_candidates: demo_candidates,
    trial_logs: @trial_logs  # Pass for instruction history awareness
  )
end
```

Add configuration builder:
```ruby
def build_proposer_config
  proposer_config = DSPy::Propose::GroundedProposer::Config.new
  proposer_config.num_instruction_candidates = config.num_instruction_candidates
  proposer_config.program_aware = true  # Enable for MIPROv2
  proposer_config.use_dataset_summary = true  # Enable data-aware mode
  proposer_config.use_task_demos = true
  proposer_config.use_tip = true
  proposer_config.verbose = false
  proposer_config
end
```

#### Phase 6: Comprehensive Testing

**Unit Tests (`spec/unit/dspy/propose/grounded_proposer_spec.rb`):**
1. Config initialization with all awareness flags
2. Flag-based conditional logic (each flag independently)
3. Dataset summary integration (mock DatasetSummaryGenerator)
4. Program source extraction
5. Context building with different flag combinations
6. Instruction generation with varying context sizes
7. Long instructions (500+ chars) not truncated
8. Scoring normalization with dynamic max length

**Integration Tests (`spec/integration/grounded_proposer_awareness_spec.rb`):**
1. All awareness flags enabled (full context)
2. Only `use_dataset_summary` enabled
3. Only `program_aware` enabled
4. Only `use_task_demos` enabled
5. All flags disabled (baseline proposal)
6. Real DSPy::Module program source extraction
7. Instructions > 500 chars preserved end-to-end
8. VCR cassettes for all LLM interactions

**MIPROv2 Integration Tests:**
1. MIPROv2 with enhanced proposer (all awareness modes)
2. Verify trial_logs passed to proposer for history awareness
3. End-to-end optimization with data-aware proposer
4. Performance with long instructions (no truncation)

### Timeline Estimate

**5-7 days** (per original ADR-008 estimate)
- **Day 1:** Remove max_instruction_length + comprehensive tests ⭐ Priority
- **Day 2:** Refactor Config class + awareness flags + unit tests
- **Day 3:** Integrate DatasetSummaryGenerator + program source extraction
- **Day 4:** Update propose_instructions method + context building
- **Day 5:** Update MIPROv2 integration + trial_logs passing
- **Day 6:** Integration tests with VCR + all awareness modes
- **Day 7:** Documentation + PR + migration guide

### Success Criteria

**Phase 1 (Completed):**
- [x] `max_instruction_length` completely removed from entire codebase (6 locations)
- [x] Instructions > 500 chars work end-to-end without truncation
- [x] Simplified scoring (no length factor - matches Python)
- [x] Simplified diversity (only few-shot count - matches Python)
- [x] All existing tests pass (100/100 teleprompt/propose tests)
- [x] New tests for Python parity (8/8 passing)
- [x] Documentation updated in ADR-008

**Phase 2-6 (Pending):**
- [ ] All 4 Python awareness flags implemented: `program_aware`, `use_dataset_summary`, `use_task_demos`, `use_tip`
- [ ] DatasetSummaryGenerator integrated for data-aware mode
- [ ] Config class parameter names match Python exactly
- [ ] New tests cover all awareness mode combinations
- [ ] MIPROv2 uses enhanced proposer with configurable awareness
- [ ] Migration guide for Config API breaking changes

### Breaking Changes & Migration

**Config API Changes:**

**Removed (no replacement needed):**
- `use_task_description` - analysis logic always runs
- `use_input_output_analysis` - always performed
- `max_examples_for_analysis` - use `view_data_batch_size`
- `proposal_model` - use global `DSPy.lm`
- `max_instruction_length` - no more artificial limit

**Renamed (migration required):**
- `use_few_shot_examples` → `use_task_demos`

**Added (new functionality):**
- `program_aware` - include program source in context
- `use_dataset_summary` - call DatasetSummaryGenerator
- `use_tip` - include instructional tips
- `use_instruct_history` - include historical instructions
- `num_demos_in_context` - control demo count
- `set_tip_randomly` - randomize tip selection
- `set_history_randomly` - randomize history selection
- `init_temperature` - LLM temperature for proposals

**Migration Example:**
```ruby
# Before (old API)
config = GroundedProposer::Config.new
config.max_instruction_length = 500  # REMOVED
config.use_few_shot_examples = true  # RENAMED

# After (new API)
config = GroundedProposer::Config.new
# No max_instruction_length - no artificial limit!
config.use_task_demos = true  # Renamed from use_few_shot_examples
config.program_aware = true  # New: include program source
config.use_dataset_summary = true  # New: generate dataset summary
```

### Next Steps

According to the bottom-up implementation plan in this ADR:

**✅ Layer 3.5 Complete** - Bootstrap Functions
**✅ Layer 4.1 Complete** - Dataset Summary Generator
**✅ Layer 4.2 Complete** - GroundedProposer with full Python-compatible awareness flags
**→ Next: Layer 5** - Complete MIPROv2 with optimization strategy

- ✅ Progress Update (commit `e7b3204` / PR #147): Implemented Layer 5 scaffolding for trial management — Ruby MIPROv2 now records `trial_logs`, `param_score_dict`, `fully_evaled_param_combos`, and total evaluation calls, keeping parity-ready hooks for proposer history and minibatch support.
- ✅ Progress Update (commit `3e24c59`): Enabled instruction-history awareness by feeding stored `trial_logs` into `GroundedProposer` and persisting them across MIPROv2 runs, matching Python’s context-building behavior and covering it with unit tests.
- ✅ Progress Update (commit `6086de4`): Trial logs now capture per-predictor instruction snapshots from evaluated programs, ensuring history-aware proposals reflect the actual compiled prompts and surfacing them in serialized optimization traces.
- ✅ Progress Update (commit `0ba8a95`): Introduced concurrent minibatch evaluation using `concurrent-ruby`, configurable via `minibatch_size` and `num_threads`, so Layer 5 can scale evaluation throughput while preserving aggregated metrics parity with Python.
- ✅ Progress Update (commit `62a575e`): Added a program-aware `propose_instructions_for_program` hook and per-predictor metadata so Ruby MIPROv2 can generate instruction candidates aligned with Python’s multi-predictor interface while keeping earlier APIs working.
- ✅ Progress Update (commit `84621b1`): Generate cross-predictor instruction combinations and store them in trial metadata so multiprompt programs can explore per-module instruction tuples like Python’s Optuna search.
- ✅ Progress Update (branch `feature/miprov2-layer5-todos`): Implemented per-predictor instruction and few-shot selection inside `generate_candidate_configurations`/`apply_candidate_configuration`, updated optimization traces to log `few_shot_map`, and added parity specs covering multi-predictor programs.
- ✅ Progress Update: Added predictor discovery helpers (`Module#predictors`, `#named_predictors`), exposed ReAct/CodeAct internals, and covered Utils demo generation with multi-predictor specs so Layer 5 can enumerate and tune nested modules like Python.
- ✅ Integration Coverage: Added `spec/integration/dspy/mipro_v2_re_act_integration_spec.rb` with VCR cassette (`miprov2/react_light.yml`) to validate end-to-end optimization of a lightweight ReAct program, ensuring per-predictor awareness works with real LM traces.
- ✅ Status Update (2025-10-18): Layer 5 parity is on track—per-predictor flows, predictor discovery, and ReAct integration are in place. Remaining work focuses on documenting Bayesian strategy trade-offs and validating observability emitters with live telemetry once open-telemetry is re-enabled.

**Layer 4.2 Achievement**: Successfully implemented all Python-compatible awareness flags:
- Phase 1: Python-compatible instruction handling (no length limits)
- Phase 2-3: Config with awareness flags (program_aware, use_dataset_summary, use_task_demos, use_tip, use_instruct_history)
- Phase 4: Updated propose_instructions to use awareness flags (dataset summary, program code, task demos, tips)
- Phase 5: MIPROv2 integration (passes program and trainset to GroundedProposer)
- Phase 6: All tests passing (60 total: 57 unit + 3 integration)

**Commits:**
- `60d624a` - feat: add Python-compatible awareness flags to GroundedProposer
- `3d4861d` - refactor: remove unnecessary 'unknown' fallback in GroundedProposer
- `8392d74` - fix: correct Python parity integration test assertions

Continue following the bottom-up approach documented in this ADR.

---

## Ready for Layer 5 (Next Session)

**What's Built:**
- ✅ Bootstrap system (`create_n_fewshot_demo_sets`)
- ✅ Dataset summary generator
- ✅ GroundedProposer with full awareness flags
- ✅ All supporting utilities

**Next: Layer 5 - MIPROv2 Main Class** (Est: 7-10 days)

Key decisions needed:
1. **Optimization strategy**: Random Search (recommended) vs Epsilon-Greedy vs Optuna
2. **Trial management**: Data structures for tracking trials and scores
3. **Minibatching**: Parameter averaging across mini-batches

See "Layer 5: MIPROv2 main class" section above for detailed breakdown.
