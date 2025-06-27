# MIPROv2 Implementation Plan

## What we're building

We want to add MIPROv2 optimization to dspy.rb so we can automatically improve our prompts. The goal is to take a signature like our math Q&A one and make it better by finding the right instructions and few-shot examples.

## The three-step optimization process

MIPROv2 works in three phases:

**Step 1: Bootstrap Few-Shot Examples**
- Takes examples from your training set
- Runs them through your current program 
- Keeps the ones that produce correct outputs
- Creates multiple candidate sets of good examples
- These become potential few-shot examples for your optimized prompt

**Step 2: Propose Instructions**
- Analyzes your training data to understand the task
- Looks at your program code to understand what it's trying to do
- Uses the few-shot examples from step 1 as context
- Generates multiple candidate instructions using an LLM
- Each instruction is tailored to your specific task and data

**Step 3: Bayesian Optimization**
- Tests different combinations of instructions + few-shot examples
- Uses optimization algorithms to intelligently search the space
- Evaluates each combination on a validation set
- Keeps track of what works and suggests better combinations
- Returns the best performing instruction + example combination

## Porting strategy

We're porting from the Python implementation to Ruby. Here's what we need to translate:

### Python to Ruby library mappings

**Data handling**:
- `numpy` → `numo-narray` or `polars-df` (we'll use Polars)
- `pandas` → `polars-df` 
- `collections.defaultdict` → Ruby `Hash.new { |h, k| h[k] = [] }`

**Optimization**:
- `optuna` → Custom simple optimizer (random/grid search to start)
- `scipy.optimize` → Custom implementation or `rb-gsl` if needed

**Utilities**:
- `typing` → `sorbet-runtime` (already using)
- `textwrap` → Ruby `String` methods
- `logging` → Ruby `Logger` + our event system
- `time` → Ruby `Time` and `Process.clock_gettime`

### Key porting challenges

**Threading and job execution**:
- Python's `ThreadPoolExecutor` → Adapter pattern for flexibility
- Support multiple backends: `Concurrent::ThreadPoolExecutor`, Solid Queues, Sidekiq, etc.
- Create `DSPy::ExecutorAdapter` interface that can delegate to different job systems
- This lets users choose their preferred job processing system

**Bayesian optimization**:
- Start with simple random/grid search
- Can upgrade to proper Bayesian later with custom implementation

**Error handling**:
- Python's try/except → Ruby's begin/rescue
- Need to maintain the same error recovery patterns

**Configuration**:
- Python's nested dicts → Ruby Hash with symbol keys
- Auto mode settings need direct translation

### What we're keeping vs changing

**Keeping the same**:
- Three-phase optimization process (bootstrap → propose → optimize)
- Auto mode configurations (light/medium/heavy)
- Event-driven architecture (enhanced with our dry-monitor system)
- JSON serialization format for compatibility

**Changing for Ruby**:
- Using our existing event system instead of custom logging
- Polars instead of pandas for data handling
- Simpler optimization to start (no Optuna dependency)
- Executor adapter pattern for job processing flexibility
- Better integration with Ruby's object model

## The plan - 8 iterations

### Iteration 1: Foundation & Evaluation Framework

**What we're doing**: Building the basic evaluation and teleprompter infrastructure

**Deliverables**:
- `lib/dspy/evaluate.rb` - System to run metrics on our predictions
- `lib/dspy/teleprompt/teleprompter.rb` - Base class for all optimizers
- New events for the optimization lifecycle
- Unit tests (keeping our one expectation per test rule)

**New events we'll add**:
```ruby
n.register_event('dspy.evaluation.start')
n.register_event('dspy.evaluation.batch_complete') 
n.register_event('dspy.optimization.trial_start')
n.register_event('dspy.optimization.trial_complete')
```

### Iteration 2: Data Pipeline & Bootstrapping

**What we're doing**: Building the system to generate few-shot examples

**Deliverables**:
- `lib/dspy/teleprompt/utils.rb` - All the bootstrap utilities
- Polars integration for fast data handling
- Minibatch evaluation (so we don't blow up our API costs)
- Events for tracking bootstrap progress

**Key pieces**:
- `create_n_fewshot_demo_sets()` method
- `eval_candidate_program()` method  
- Proper error handling when examples fail

### Iteration 3: Simple Optimizer & Instruction Proposal

**What we're doing**: Making the system that writes better instructions

**Deliverables**:
- `lib/dspy/propose/grounded_proposer.rb` - The thing that writes new prompts
- Simple random/grid search optimizer (no fancy Bayesian stuff yet)
- Integration with our existing signature system
- Events for tracking what instructions get proposed

### Iteration 4: MIPROv2 Core Implementation

**What we're doing**: Putting it all together into the full MIPROv2 system

**Deliverables**:
- `lib/dspy/teleprompt/mipro_v2.rb` - The complete implementation
- Auto modes (light: 6 trials, medium: 12, heavy: 18)
- Full three-phase pipeline working end-to-end
- Performance tracking throughout

### Iteration 5: Persistence & Serialization

**What we're doing**: Making sure we can save and load our optimized prompts

**Deliverables**:
- `lib/dspy/storage/` directory with all persistence code
- JSON serialization that captures everything we need
- History tracking for optimization runs
- Events for save/load operations

**New events**:
```ruby
n.register_event('dspy.storage.save')
n.register_event('dspy.storage.load')
n.register_event('dspy.storage.error')
```

### Iteration 6: Registry & Version Management

**What we're doing**: Production-ready signature management

**Deliverables**:
- `lib/dspy/registry/signature_registry.rb` - Version control for prompts
- Rollback capability when optimizations go wrong
- YAML config file support
- Registry monitoring events

### Iteration 7: OTEL & New Relic Integration

**What we're doing**: Getting production observability working

**Deliverables**:
- `lib/dspy/subscribers/otel_subscriber.rb` - OpenTelemetry integration
- `lib/dspy/subscribers/newrelic_subscriber.rb` - New Relic integration
- Spans for optimization operations
- Custom metrics export

**What we'll track**:
- How long optimizations take
- Token usage and costs
- Error rates
- Performance changes after optimization

**Detailed instrumentation tasks**:

**OTEL Subscriber** (`lib/dspy/subscribers/otel_subscriber.rb`):
- Subscribe to all `dspy.optimization.*` events
- Create spans for each optimization trial
- Track optimization duration, success/failure rates
- Include token usage from our existing `TokenTracker`
- Export custom metrics for optimization performance

**New Relic Subscriber** (`lib/dspy/subscribers/newrelic_subscriber.rb`):
- Subscribe to optimization events using our dry-monitor system
- Create custom events for optimization runs
- Track business metrics like accuracy improvements
- Alert on optimization failures or performance degradation
- Dashboard metrics for optimization ROI

**Events we'll add for instrumentation**:
```ruby
# In instrumentation.rb
n.register_event('dspy.optimization.start')
n.register_event('dspy.optimization.complete')
n.register_event('dspy.optimization.trial_start')
n.register_event('dspy.optimization.trial_complete')
n.register_event('dspy.optimization.bootstrap_complete')
n.register_event('dspy.optimization.instruction_proposal_complete')
n.register_event('dspy.optimization.error')
n.register_event('dspy.signature.optimized')
n.register_event('dspy.signature.deployed')
```

**Integration with existing TokenTracker**:
- Use our existing `TokenTracker` to capture token usage during optimization
- Track costs for each optimization trial
- Monitor token efficiency improvements from optimization

### Iteration 8: Langfuse Integration & Polish

**What we're doing**: LLM-specific observability and wrapping up

**Deliverables**:
- `lib/dspy/subscribers/langfuse_subscriber.rb` - Langfuse integration
- Prompt version tracking and comparison
- Integration tests for the complete pipeline
- Documentation and examples

**Langfuse features**:
- Compare prompt performance visually
- A/B testing support
- Cost tracking per optimization run

**Detailed Langfuse integration**:

**Langfuse Subscriber** (`lib/dspy/subscribers/langfuse_subscriber.rb`):
- Subscribe to all signature and optimization events
- Create Langfuse traces for optimization runs
- Track prompt versions and their performance
- Store few-shot examples and instructions as prompt templates
- Enable A/B testing between optimized and baseline prompts

**Langfuse-specific events**:
```ruby
# Additional events for Langfuse
n.register_event('dspy.langfuse.trace_start')
n.register_event('dspy.langfuse.prompt_version_created')
n.register_event('dspy.langfuse.comparison_logged')
```

**Integration with optimization pipeline**:
- Automatically log baseline vs optimized performance
- Track optimization metadata (which instructions worked, why)
- Create prompt lineage for version management
- Enable rollback based on Langfuse performance data

**Production monitoring setup**:
- Dashboard showing optimization impact
- Alerts for performance regression after deployment
- Cost tracking and ROI analysis
- Prompt performance trending over time

## How we'll work

Each iteration we'll:
1. Review what we built last time
2. Test integration with the existing system  
3. Plan the specific tasks for this iteration
4. Adjust the plan if we hit issues
5. **Compare with Python implementation** to ensure we're not missing key features

The idea is to build incrementally so we always have something working, and we can test each piece as we go. We'll start with a simplified version and add complexity as we validate each component works.

## Success criteria

We'll know we're done when:
- We can optimize a signature in under 5 minutes
- Saving and loading optimized signatures just works
- We have full observability in production
- A/B testing is ready to go
