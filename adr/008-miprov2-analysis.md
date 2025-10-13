# ADR 008: MIPROv2 Python Implementation Analysis

**Status:** Analysis
**Date:** 2025-10-09
**Context:** Analysis of Python DSPy MIPROv2 implementation

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
  - Uses specific seeds: -3 (zero-shot), -2 (labeled-only), -1 (unshuffled), 0+ (shuffled)
  - Calls `BootstrapFewShot` and `LabeledFewShot` teleprompters
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
