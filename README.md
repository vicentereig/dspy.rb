# DSPy.rb

**Build reliable LLM applications in Ruby using composable, type-safe modules.**

DSPy.rb brings structured LLM programming to Ruby developers.
Instead of wrestling with prompt strings and parsing responses,
you define typed signatures and compose them into pipelines that just work.

Traditional prompting is like writing code with string concatenation: it works until 
it doesn't. DSPy.rb brings you the programming approach pioneered 
by [dspy.ai](https://dspy.ai/): instead of crafting fragile prompts, you define 
modular signatures and let the framework handle the messy details.

The result? LLM applications that actually scale and don't break when you sneeze.

## What You Get

**Core Building Blocks:**
- **Signatures** - Define input/output schemas using Sorbet types
- **Predict** - Basic LLM completion with structured data
- **Chain of Thought** - Step-by-step reasoning for complex problems
- **ReAct** - Tool-using agents that can actually get things done
- **RAG** - Context-enriched responses from your data
- **Multi-stage Pipelines** - Compose multiple LLM calls into workflows

**Optimization & Evaluation:**
- **Prompt Objects** - Manipulate prompts as first-class objects instead of strings
- **Typed Examples** - Type-safe training data with automatic validation
- **Evaluation Framework** - Systematic testing with built-in metrics
- **MIPROv2 Optimizer** - State-of-the-art automatic prompt optimization
- **Simple Optimizer** - Random/grid search for quick experimentation

**Enterprise Features:**
- **Storage System** - Persistent optimization result storage with search and filtering
- **Registry System** - Version control for optimized signatures with deployment tracking
- **Multi-Platform Observability** - OpenTelemetry, New Relic, and Langfuse integration
- **Auto-deployment** - Intelligent deployment based on performance improvements
- **Rollback Protection** - Automatic rollback on performance degradation

**Developer Experience:**
- OpenAI and Anthropic support via [Ruby LLM](https://github.com/crmne/ruby_llm)
- Runtime type checking with [Sorbet](https://sorbet.org/)
- Type-safe tool definitions for ReAct agents
- Comprehensive instrumentation and observability

## Fair Warning

This is fresh off the oven and evolving fast. 
I'm actively building this as a Ruby port of the [DSPy library](https://dspy.ai/). 
If you hit bugs or want to contribute, just email me directly!

## What's Next
These are my goals to release v1.0.

- ✅ Prompt objects foundation - *Done*
- ✅ Evaluation framework - *Done*  
- ✅ Teleprompter base classes - *Done*
- ✅ MIPROv2 optimization algorithm - *Done*
- ✅ Storage & persistence system - *Done*
- ✅ Registry & version management - *Done*
- ✅ OpenTelemetry integration - *Done*
- ✅ New Relic integration - *Done*
- ✅ Langfuse integration - *Done*
- 🚧 Ollama support
- Agentic Memory support
- MCP Support
- Documentation website
- Performance benchmarks

## Installation

Skip the gem for now - install straight from this repo while I prep the first release:
```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

### Optional Observability Dependencies

Add any of these gems for enhanced observability:

```ruby
# OpenTelemetry (distributed tracing)
gem 'opentelemetry-api'
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'

# New Relic (APM)
gem 'newrelic_rpm'

# Langfuse (LLM observability) 
gem 'langfuse'
```

DSPy automatically detects and integrates with available platforms - no configuration required!

## Quick Start

### Basic Prediction

```ruby
# Define a signature for sentiment classification
class Classify < DSPy::Signature
  description "Classify sentiment of a given sentence."

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :sentence, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

# Configure DSPy with your LLM
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# Create the predictor and run inference
classify = DSPy::Predict.new(Classify)
result = classify.call(sentence: "This book was super fun to read, though not the last chapter.")

# result is a properly typed T::Struct instance
puts result.sentiment    # => #<Sentiment::Positive>  
puts result.confidence   # => 0.85
```

### Chain of Thought Reasoning

```ruby
class AnswerPredictor < DSPy::Signature
  description "Provides a concise answer to the question"

  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

# Chain of thought automatically adds a 'reasoning' field to the output
qa_cot = DSPy::ChainOfThought.new(AnswerPredictor)
result = qa_cot.call(question: "Two dice are tossed. What is the probability that the sum equals two?")

puts result.reasoning  # => "There is only one way to get a sum of 2..."
puts result.answer     # => "1/36"
```

### ReAct Agents with Tools

```ruby

class DeepQA < DSPy::Signature
  description "Answer questions with consideration for the context"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

# Define tools for the agent
class CalculatorTool < DSPy::Tools::Base

  tool_name 'calculator'
  tool_description 'Performs basic arithmetic operations'

  sig { params(operation: String, num1: Float, num2: Float).returns(T.any(Float, String)) }
  def call(operation:, num1:, num2:)
    case operation.downcase
    when 'add' then num1 + num2
    when 'subtract' then num1 - num2
    when 'multiply' then num1 * num2
    when 'divide'
      return "Error: Cannot divide by zero" if num2 == 0
      num1 / num2
    else
      "Error: Unknown operation '#{operation}'. Use add, subtract, multiply, or divide"
    end
  end

# Create ReAct agent with tools
agent = DSPy::ReAct.new(DeepQA, tools: [CalculatorTool.new])

# Run the agent
result = agent.forward(question: "What is 42 plus 58?")
puts result.answer # => "100"
puts result.history # => Array of reasoning steps and tool calls
```

### Multi-stage Pipelines
Outline the sections of an article and draft them out.

```ruby

# write an article!
drafter = ArticleDrafter.new
article = drafter.forward(topic: "The impact of AI on software development") # { title: '....', sections: [{content: '....'}]}

class Outline < DSPy::Signature
  description "Outline a thorough overview of a topic."

  input do
    const :topic, String
  end

  output do
    const :title, String
    const :sections, T::Array[String]
  end
end

class DraftSection < DSPy::Signature
  description "Draft a section of an article"

  input do
    const :topic, String
    const :title, String
    const :section, String
  end

  output do
    const :content, String
  end
end

class ArticleDrafter < DSPy::Module
  def initialize
    @build_outline = DSPy::ChainOfThought.new(Outline)
    @draft_section = DSPy::ChainOfThought.new(DraftSection)
  end

  def forward(topic:)
    outline = @build_outline.call(topic: topic)
    
    sections = outline.sections.map do |section|
      @draft_section.call(
        topic: topic,
        title: outline.title,
        section: section
      )
    end

    {
      title: outline.title,
      sections: sections.map(&:content)
    }
  end
end

```

## Prompt Objects and Optimization

Traditional prompt engineering treats prompts as strings - you write them once, hope they work, and when they don't, you're back to manual tweaking. DSPy.rb flips this around with **prompt objects** that can be manipulated, optimized, and composed programmatically.

### Why Prompt Objects Matter

```ruby
# Instead of this fragile approach:
prompt_string = "You are a helpful assistant. Answer this question: #{question}"

# You get composable, optimizable prompt objects:
class QA < DSPy::Signature
  description "Answer questions accurately and concisely"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

# The magic happens when you need to optimize
predictor = DSPy::Predict.new(QA)

# Later, optimization algorithms can automatically improve this:
# - Add better instructions
# - Include relevant examples  
# - Tune the reasoning approach
# - All without you manually crafting prompts
```

### Manipulating Prompts Programmatically

Every DSPy predictor works with prompt objects under the hood, and you can access and modify them:

```ruby
# Start with a basic predictor
qa = DSPy::Predict.new(QA)

# Enhance it with better instructions
improved_qa = qa.with_instruction(
  "Answer questions step-by-step, citing specific evidence when possible"
)

# Add few-shot examples for better performance
examples = [
  DSPy::FewShotExample.new(
    input: { question: "What is the capital of France?" },
    output: { answer: "Paris" },
    reasoning: "France is a country in Western Europe, and its capital city is Paris."
  )
]

expert_qa = improved_qa.with_examples(examples)

# All of these return new predictor instances - immutable and safe
result = expert_qa.call(question: "What is the capital of Japan?")
```

### Chain of Thought with Prompt Objects

Chain of Thought reasoning gets even more powerful with prompt objects:

```ruby
cot_qa = DSPy::ChainOfThought.new(QA)

# Optimization can automatically improve the reasoning instructions
optimized_cot = cot_qa.with_instruction(
  "Think through this step-by-step, considering multiple angles before concluding"
)
```

## Typed Examples and Validation

Stop debugging example format mismatches. DSPy.rb gives you type-safe examples that catch errors early and make optimization reliable.

### Type-Safe Training Data

```ruby
class MathWord < DSPy::Signature
  description "Solve word problems step by step"
  
  input do
    const :problem, String
  end
  
  output do
    const :answer, Integer
    const :explanation, String
  end
end

# Create validated examples that catch errors immediately
training_examples = [
  DSPy::Example.new(
    signature_class: MathWord,
    input: { problem: "Sarah has 5 apples and buys 3 more. How many does she have?" },
    expected: { answer: 8, explanation: "5 + 3 = 8 apples total" }
  ),
  DSPy::Example.new(
    signature_class: MathWord, 
    input: { problem: "A box contains 12 items. If 4 are removed, how many remain?" },
    expected: { answer: 8, explanation: "12 - 4 = 8 items remaining" }
  )
]

# This will fail fast if the types don't match your signature:
# DSPy::Example.new(
#   signature_class: MathWord,
#   input: { problem: "Test" },
#   expected: { answer: "not a number", explanation: "..." }  # TypeError!
# )
```

### Example Validation and Matching

```ruby
example = training_examples.first

# Examples know how to validate predictions
prediction = { answer: 8, explanation: "5 + 3 = 8 apples total" }
puts example.matches_prediction?(prediction)  # => true

wrong_prediction = { answer: 7, explanation: "Wrong math" }
puts example.matches_prediction?(wrong_prediction)  # => false

# Get detailed validation information
validation = example.validate_prediction(prediction)
puts validation.valid?     # => true
puts validation.errors     # => []
```

### Legacy Format Support

Don't worry about migrating existing training data - DSPy.rb handles legacy formats automatically:

```ruby
# You can still use hash-based examples
legacy_examples = [
  {
    input: { problem: "What is 2 + 2?" },
    expected: { answer: 4, explanation: "Add 2 and 2" }
  }
]

# DSPy automatically converts them when needed
DSPy::Example.from_legacy_format(MathWord, legacy_examples)
```

## Evaluation Framework

Building reliable LLM applications means systematic testing. DSPy.rb includes a comprehensive evaluation system that works seamlessly with your typed examples and supports multiple evaluation metrics.

### Basic Evaluation

```ruby
# Create your predictor
math_solver = DSPy::ChainOfThought.new(MathWord)

# Evaluate it on your examples
evaluator = DSPy::Evaluate.new(
  math_solver,
  metric: DSPy::Metrics.exact_match  # Built-in exact matching
)

results = evaluator.evaluate(training_examples)

puts "Accuracy: #{results.accuracy}"           # => 0.85
puts "Passed: #{results.passed_examples}"     # => 17
puts "Total: #{results.total_examples}"       # => 20
puts "Failed examples: #{results.failed_examples.count}"  # => 3
```

### Built-in Metrics

DSPy.rb includes common evaluation metrics out of the box:

```ruby
# Exact matching for precise comparisons
exact_metric = DSPy::Metrics.exact_match

# Fuzzy matching for text that might vary slightly
contains_metric = DSPy::Metrics.contains("key phrase")

# Numeric comparison with tolerance
numeric_metric = DSPy::Metrics.numeric_difference(tolerance: 0.1)

# Composite metrics for complex validation
composite_metric = DSPy::Metrics.composite_and(
  DSPy::Metrics.exact_match,
  DSPy::Metrics.contains("reasoning")
)
```

### Custom Metrics

Define domain-specific evaluation logic:

```ruby
# Custom metric for math problems
math_metric = proc do |example, prediction|
  # Check if the numerical answer is correct
  answer_correct = example.expected_values[:answer] == prediction[:answer]
  
  # Check if explanation mentions the operation
  problem = example.input_values[:problem]
  explanation = prediction[:explanation]
  
  has_operation = if problem.include?('+')
    explanation.include?('add') || explanation.include?('+')
  elsif problem.include?('-')
    explanation.include?('subtract') || explanation.include?('-')
  else
    true  # Other operations
  end
  
  answer_correct && has_operation
end

evaluator = DSPy::Evaluate.new(math_solver, metric: math_metric)
```

### Batch Evaluation and Performance Analysis

```ruby
# Evaluate with progress tracking
results = evaluator.evaluate(
  training_examples,
  display_progress: true,
  num_threads: 4  # Parallel evaluation
)

# Get detailed insights
puts "Average confidence: #{results.metrics[:average_confidence]}"
puts "Processing time: #{results.metrics[:total_duration_ms]}ms"

# Analyze failed cases
results.failed_examples.each do |failure|
  puts "Failed: #{failure.example.input_values[:problem]}"
  puts "Expected: #{failure.example.expected_values[:answer]}"
  puts "Got: #{failure.prediction[:answer]}"
  puts "Error: #{failure.error}" if failure.error
  puts "---"
end
```

## Building Optimization Pipelines

This is where DSPy.rb really shines. Instead of manually tuning prompts, you define the optimization problem and let the algorithms do the heavy lifting.

### Teleprompter Base Class

All optimization algorithms inherit from the `Teleprompter` base class:

```ruby
# Configure optimization settings
config = DSPy::Teleprompt::Teleprompter::Config.new
config.max_bootstrapped_examples = 8
config.max_labeled_examples = 32
config.num_threads = 4
config.max_errors = 10

# Initialize with custom metric
teleprompter = YourOptimizerClass.new(
  metric: math_metric,
  config: config
)

# Run optimization
result = teleprompter.compile(
  math_solver,
  trainset: training_examples,
  valset: validation_examples
)

# Get the optimized program
optimized_solver = result.optimized_program

puts "Optimization improved accuracy from #{baseline_accuracy} to #{result.best_score_value}"
```

### Optimization Results

The optimization process returns detailed results:

```ruby
puts "Best score: #{result.best_score_value} (#{result.best_score_name})"
puts "All scores: #{result.scores}"
puts "Optimization history: #{result.history}"
puts "Metadata: #{result.metadata}"

# Save results for later analysis
result.save_to_file("/path/to/optimization_results.json")
```

### Simple Optimizer

For quick experimentation and simpler optimization needs, DSPy.rb includes a Simple Optimizer that uses random/grid search:

```ruby
# Quick optimization with simple random search
config = DSPy::Teleprompt::SimpleOptimizer::OptimizerConfig.new
config.num_trials = 10
config.search_strategy = "random"  # or "grid"
config.use_instruction_optimization = true
config.use_few_shot_optimization = true

simple_optimizer = DSPy::Teleprompt::SimpleOptimizer.new(
  metric: your_metric,
  config: config
)

result = simple_optimizer.compile(
  program,
  trainset: training_examples,
  valset: validation_examples
)

puts "Simple optimization found score: #{result.best_score_value}"
```

### MIPROv2 Optimization

DSPy.rb includes **MIPROv2** (Multi-prompt Instruction Proposal with Retrieval Optimization), the state-of-the-art prompt optimization algorithm. It automatically improves your programs through a three-phase pipeline: bootstrap sampling, instruction generation, and Bayesian optimization.

#### Quick Start with Auto Modes

```ruby
# Define your signature and program
class QuestionAnswering < DSPy::Signature
  description "Answer questions accurately with supporting reasoning"
  
  input do
    const :question, String
    const :context, String
  end
  
  output do
    const :answer, String
    const :reasoning, String
  end
end

# Create training examples  
training_examples = [
  DSPy::Example.new(
    signature_class: QuestionAnswering,
    input: { 
      question: "What causes photosynthesis?",
      context: "Plants use sunlight, water, and carbon dioxide to produce glucose and oxygen through chlorophyll."
    },
    expected: { 
      answer: "Photosynthesis is caused by plants using sunlight, water, and CO2 to make glucose.",
      reasoning: "The process requires chlorophyll to capture light energy and convert it to chemical energy."
    }
  ),
  # ... more examples
]

# Initialize your base program
qa_program = DSPy::ChainOfThought.new(QuestionAnswering)

# Use auto modes for easy optimization
light_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.light      # 6 trials, fast
medium_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.medium    # 12 trials, balanced  
heavy_optimizer = DSPy::Teleprompt::MIPROv2::AutoMode.heavy      # 18 trials, thorough

# Run optimization (this will take a few minutes)
result = medium_optimizer.compile(
  qa_program,
  trainset: training_examples,
  valset: validation_examples
)

# Your program is now optimized!
optimized_qa = result.optimized_program

puts "Optimization improved accuracy from baseline to #{result.best_score_value}"
puts "Best instruction: #{result.metadata[:best_instruction]}"
puts "Optimization used #{result.history[:total_trials]} trials"
```

#### Advanced MIPROv2 Configuration

```ruby
# Full control with custom configuration
config = DSPy::Teleprompt::MIPROv2::MIPROv2Config.new
config.num_trials = 20
config.num_instruction_candidates = 8
config.bootstrap_sets = 10
config.optimization_strategy = "adaptive"  # greedy, adaptive, bayesian
config.init_temperature = 1.0
config.final_temperature = 0.1
config.early_stopping_patience = 5

# Custom evaluation metric
qa_metric = proc do |example, prediction|
  # Check answer accuracy + reasoning quality
  answer_correct = example.expected_values[:answer] == prediction[:answer]
  has_reasoning = prediction[:reasoning]&.length.to_i > 10
  answer_correct && has_reasoning
end

# Initialize with custom configuration
mipro = DSPy::Teleprompt::MIPROv2.new(
  metric: qa_metric,
  config: config
)

# Run optimization with detailed results
result = mipro.compile(
  qa_program,
  trainset: training_examples,
  valset: validation_examples
)

# Analyze optimization results
puts "=== Optimization Results ==="
puts "Best score: #{result.best_score_value} (#{result.best_score_name})"
puts "Total trials: #{result.history[:total_trials]}"
puts "Early stopped: #{result.history[:early_stopped]}"
puts "Strategy: #{result.metadata[:optimization_strategy]}"

puts "\n=== Bootstrap Statistics ==="
puts "Success rate: #{result.bootstrap_statistics[:success_rate]}"
puts "Successful examples: #{result.bootstrap_statistics[:successful_count]}"

puts "\n=== Best Configuration ==="
puts "Instruction: #{result.metadata[:best_instruction]}"
puts "Few-shot examples: #{result.metadata[:best_few_shot_count]}"
puts "Candidate type: #{result.metadata[:best_candidate_type]}"

# The optimized program includes the best instruction and examples
final_result = result.optimized_program.call(
  question: "How do birds fly?",
  context: "Birds have hollow bones, powerful flight muscles, and wing shapes that create lift."
)

puts "\n=== Optimized Output ==="
puts "Answer: #{final_result.answer}"
puts "Reasoning: #{final_result.reasoning}"
```

#### Understanding MIPROv2 Phases

MIPROv2 works through three distinct phases:

1. **Bootstrap Phase**: Generates successful few-shot examples from your training data
2. **Instruction Proposal**: Uses LLMs to generate candidate instructions based on task analysis  
3. **Bayesian Optimization**: Searches the space of instruction + few-shot combinations

```ruby
# Monitor optimization progress with events
DSPy::Instrumentation.subscribe('dspy.optimization.*') do |event|
  case event.id
  when 'dspy.optimization.phase_start'
    puts "🚀 Starting #{event.payload[:name]} phase"
  when 'dspy.optimization.phase_complete'
    puts "✅ Phase #{event.payload[:phase]} complete"
  when 'dspy.optimization.trial_complete'
    puts "   Trial #{event.payload[:trial_number]}: score = #{event.payload[:score]}"
  end
end
```

## Storage and Persistence

DSPy.rb includes a comprehensive storage system for persisting optimization results, making it easy to save, search, and analyze your optimized programs.

### Automatic Storage

Enable automatic storage to save all optimization results:

```ruby
# Configure teleprompter with storage
config = DSPy::Teleprompt::Teleprompter::Config.new
config.save_intermediate_results = true  # Enable automatic storage

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: your_metric, config: config)
result = optimizer.compile(program, trainset: train, valset: val)

# Results are automatically saved with metadata
# You can find them in ./optimization_results/ by default
```

### Storage Configuration

```ruby
# Customize storage behavior
storage_config = DSPy::Storage::StorageManager::StorageConfig.new
storage_config.storage_path = "./my_results"
storage_config.auto_save = true
storage_config.compression_enabled = true
storage_config.max_storage_size_mb = 1000

storage_manager = DSPy::Storage::StorageManager.new(config: storage_config)
```

### Searching and Loading Results

```ruby
# Search stored programs by tags, performance, or metadata
programs = storage_manager.search_programs(
  tags: ['miprov2', 'qa'],
  min_score: 0.8,
  optimizer: 'MIPROv2'
)

# Load a specific program
program_id = programs.first.program_id
loaded_program = storage_manager.load_program(program_id)

# Use the loaded program
result = loaded_program.call(question: "What is the capital of France?")
```

### Storage Analytics

```ruby
# Get storage statistics
stats = storage_manager.get_statistics

puts "Total programs: #{stats[:total_programs]}"
puts "Storage size: #{stats[:total_size_mb]}MB"
puts "Best score: #{stats[:best_score]}"

# Export/import for backups
storage_manager.export_data('./backup.json')
storage_manager.import_data('./backup.json')
```

## Registry and Version Management

The registry system provides version control for your optimized signatures, with deployment tracking and automatic rollback capabilities.

### Automatic Version Registration

```ruby
# Optimization results are automatically registered
config = DSPy::Teleprompt::Teleprompter::Config.new
config.save_intermediate_results = true

# Registry integration is automatic
optimizer = DSPy::Teleprompt::MIPROv2.new(config: config)
result = optimizer.compile(program, trainset: train, valset: val)

# Check the registry
registry = DSPy::Registry::SignatureRegistry.new
versions = registry.list_versions('YourSignature')
puts "#{versions.size} versions available"
```

### Manual Registry Operations

```ruby
# Register a version manually
registry = DSPy::Registry::SignatureRegistry.new

version = registry.register_version(
  'QuestionAnswering',
  {
    instruction: 'Answer questions with detailed reasoning',
    few_shot_examples_count: 3,
    optimization_metadata: { trials: 20, best_score: 0.87 }
  },
  version: 'v1.0.0',  # Optional: auto-generated if not provided
  metadata: { created_by: 'optimizer', environment: 'production' }
)

puts "Registered version: #{version.version} with hash: #{version.version_hash}"
```

### Deployment and Rollback

```ruby
# Deploy a version
deployed = registry.deploy_version('QuestionAnswering', 'v1.0.0')
puts "Deployed version #{deployed.version}"

# Get currently deployed version
current = registry.get_deployed_version('QuestionAnswering')
puts "Currently deployed: #{current.version}"

# Monitor performance and auto-rollback
registry_manager = DSPy::Registry::RegistryManager.new

# This will rollback if performance drops more than 5%
rollback_needed = registry_manager.monitor_and_rollback(
  'QuestionAnswering',
  current_performance_score: 0.75  # Down from 0.87
)

puts "Rollback performed: #{rollback_needed}"
```

### Advanced Registry Features

```ruby
# Compare versions
comparison = registry.compare_versions('QuestionAnswering', 'v1.0.0', 'v1.1.0')
puts "Performance difference: #{comparison[:comparison][:performance_difference]}"
puts "Configuration changes: #{comparison[:comparison][:configuration_changes]}"

# Get performance history with trends
history = registry.get_performance_history('QuestionAnswering')
puts "Latest score: #{history[:trends][:latest_score]}"
puts "Best score: #{history[:trends][:best_score]}"
puts "Improvement trend: #{history[:trends][:improvement_trend]}%"

# Export/import registry
registry.export_registry('./registry_backup.yml')
new_registry = DSPy::Registry::SignatureRegistry.new
new_registry.import_registry('./registry_backup.yml')
```

### Deployment Strategies

```ruby
# Configure automatic deployment
integration_config = DSPy::Registry::RegistryManager::RegistryIntegrationConfig.new
integration_config.auto_deploy_best_versions = true
integration_config.auto_deploy_threshold = 0.1  # 10% improvement required
integration_config.rollback_on_performance_drop = true
integration_config.deployment_strategy = "conservative"  # or "aggressive"

registry_manager = DSPy::Registry::RegistryManager.new(
  integration_config: integration_config
)

# Automatic deployment will happen during optimization
# when performance improves by more than 10%
```

## Working with Complex Types

### Enums

```ruby
class Color < T::Enum
  enums do
    Red = new
    Green = new
    Blue = new
  end
end

class ColorSignature < DSPy::Signature
  description "Identify the dominant color in a description"

  input do
    const :description, String,
      description: 'Description of an object or scene'
  end

  output do
    const :color, Color,
      description: 'The dominant color (Red, Green, or Blue)'
  end
end

predictor = DSPy::Predict.new(ColorSignature)
result = predictor.call(description: "A red apple on a wooden table")
puts result.color  # => #<Color::Red>
```

### Optional Fields and Defaults

```ruby
class AnalysisSignature < DSPy::Signature
  description "Analyze text with optional metadata"

  input do
    const :text, String,
      description: 'Text to analyze'
    const :include_metadata, T::Boolean,
      description: 'Whether to include metadata in analysis',
      default: false
  end

  output do
    const :summary, String,
      description: 'Summary of the text'
    const :word_count, Integer,
      description: 'Number of words (optional)',
      default: 0
  end
end
```

## Advanced Usage Patterns

### Multi-stage Pipelines

```ruby
class TopicSignature < DSPy::Signature
  description "Extract main topic from text"
  
  input do
    const :content, String,
      description: 'Text content to analyze'
  end
  
  output do
    const :topic, String,
      description: 'Main topic of the content'
  end
end

class SummarySignature < DSPy::Signature
  description "Create summary focusing on specific topic"
  
  input do
    const :content, String,
      description: 'Original text content'
    const :topic, String,
      description: 'Topic to focus on'
  end
  
  output do
    const :summary, String,
      description: 'Topic-focused summary'
  end
end

class ArticlePipeline < DSPy::Signature
  extend T::Sig
  
  def initialize
    @topic_extractor = DSPy::Predict.new(TopicSignature)
    @summarizer = DSPy::ChainOfThought.new(SummarySignature)
  end
  
  sig { params(content: String).returns(T.untyped) }
  def forward(content:)
    # Extract topic
    topic_result = @topic_extractor.call(content: content)
    
    # Create focused summary
    summary_result = @summarizer.call(
      content: content,
      topic: topic_result.topic
    )
    
    {
      topic: topic_result.topic,
      summary: summary_result.summary,
      reasoning: summary_result.reasoning
    }
  end
end

# Usage
pipeline = ArticlePipeline.new
result = pipeline.call(content: "Long article content...")
```

### Retrieval Augmented Generation

```ruby
class ContextualQA < DSPy::Signature
  description "Answer questions using relevant context"
  
  input do
    const :question, String,
      description: 'The question to answer'
    const :context, T::Array[String],
      description: 'Relevant context passages'
  end

  output do
    const :answer, String,
      description: 'Answer based on the provided context'
    const :confidence, Float,
      description: 'Confidence in the answer (0.0 to 1.0)'
  end
end

# Usage with retriever
retriever = YourRetrieverClass.new
qa = DSPy::ChainOfThought.new(ContextualQA)

question = "What is the capital of France?"
context = retriever.retrieve(question)  # Returns array of strings

result = qa.call(question: question, context: context)
puts result.reasoning   # Step-by-step reasoning
puts result.answer      # "Paris"
puts result.confidence  # 0.95
```

## Multi-Platform Observability

DSPy.rb provides enterprise-grade observability through multiple integrated platforms: **structured logging**, **OpenTelemetry**, **New Relic**, and **Langfuse**. Get complete visibility into your LLM operations with minimal configuration.

### Quick Setup

All observability platforms work automatically when their dependencies are available:

```ruby
# Gemfile - add any platforms you want to use
gem 'opentelemetry-api'       # For OpenTelemetry
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'
gem 'newrelic_rpm'            # For New Relic
gem 'langfuse'                # For Langfuse

# Environment variables
export OTEL_SERVICE_NAME=my-dspy-app
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export LANGFUSE_SECRET_KEY=sk_your_key
export LANGFUSE_PUBLIC_KEY=pk_your_key

# That's it! DSPy automatically detects and configures available platforms
```

### Structured Logging (Always Available)

Every operation is automatically logged with structured data:

```ruby
# All DSPy operations generate structured logs
qa = DSPy::ChainOfThought.new(QuestionAnswering)
result = qa.call(question: "What is Ruby?")

# Logs output:
# event=chain_of_thought signature=QuestionAnswering status=success duration_ms=850.5 reasoning_steps=3
# event=lm_request provider=openai model=gpt-4o-mini status=success duration_ms=750.2 tokens=145
```

### OpenTelemetry Integration

Get distributed tracing and metrics automatically:

```ruby
# No code changes needed - traces are automatic
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: accuracy_metric)
result = optimizer.compile(program, trainset: train, valset: val)

# Automatically creates:
# - Optimization spans with trial breakdown
# - LM request spans with timing
# - Metrics for duration, tokens, costs
# - Custom attributes for all operations
```

**Available Metrics:**
- `dspy.optimization.started` - Counter of optimizations
- `dspy.optimization.duration` - Histogram of durations  
- `dspy.optimization.score` - Histogram of best scores
- `dspy.lm.request.duration` - LM request latency
- `dspy.lm.tokens.total` - Token usage
- `dspy.lm.cost` - Request costs

### New Relic Integration

Application performance monitoring with custom dashboards:

```ruby
# Automatic custom metrics and events
# Visit New Relic to see:
# - Custom/DSPy/Optimization/Duration
# - Custom/DSPy/LM/Tokens/Total  
# - Custom/DSPy/LM/Cost
# - DSPyOptimizationComplete events
# - DSPyTrialComplete events
```

**Custom Events Created:**
- `DSPyOptimizationStart` / `DSPyOptimizationComplete`
- `DSPyTrialComplete` with scores
- `DSPyLMRequest` with provider/model details
- `DSPyAutoDeployment` / `DSPyAutoRollback`

### Langfuse Integration

LLM-specific observability with prompt tracking:

```ruby
# Comprehensive LLM observability
# Langfuse automatically tracks:
# - Complete optimization traces with trials
# - Individual LM requests with prompts/completions
# - Token usage and costs
# - Performance scores and trends
# - Deployment and rollback events

# Control what gets logged
langfuse_config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
langfuse_config.log_prompts = true      # Log input prompts
langfuse_config.log_completions = true  # Log LLM outputs
langfuse_config.calculate_costs = true  # Track costs
```

### Comprehensive Event Coverage

All DSPy operations emit detailed events across all platforms:

**Optimization Events:**
- `dspy.optimization.start` - Optimization begins
- `dspy.optimization.complete` - Optimization finishes  
- `dspy.optimization.trial_start` - Individual trial
- `dspy.optimization.trial_complete` - Trial results
- `dspy.optimization.error` - Optimization failures

**LLM Events:**
- `dspy.lm.request` - API requests with timing/tokens
- `dspy.predict` - Prediction operations
- `dspy.chain_of_thought` - Reasoning operations

**Storage & Registry Events:**
- `dspy.storage.save_complete` - Program storage
- `dspy.registry.register_complete` - Version registration
- `dspy.registry.deploy_complete` - Deployment
- `dspy.registry.auto_deployment` - Auto-deployments
- `dspy.registry.automatic_rollback` - Auto-rollbacks

### Custom Event Subscriptions

Add your own processing for any platform:

```ruby
# Monitor optimization progress
DSPy::Instrumentation.subscribe('dspy.optimization.*') do |event|
  case event.id
  when 'dspy.optimization.start'
    puts "🚀 Starting optimization: #{event.payload[:optimizer]}"
  when 'dspy.optimization.trial_complete'
    score = event.payload[:score]
    puts "   Trial #{event.payload[:trial_number]}: #{score}"
  when 'dspy.optimization.complete'
    puts "✅ Best score: #{event.payload[:best_score]}"
  end
end

# Track costs across all LM requests
total_cost = 0
DSPy::Instrumentation.subscribe('dspy.lm.request') do |event|
  if event.payload[:cost]
    total_cost += event.payload[:cost]
    puts "Total cost so far: $#{total_cost.round(4)}"
  end
end

# Monitor deployment events
DSPy::Instrumentation.subscribe('dspy.registry.*') do |event|
  case event.id
  when 'dspy.registry.auto_deployment'
    puts "🚀 Auto-deployed #{event.payload[:signature_name]} #{event.payload[:version]}"
  when 'dspy.registry.automatic_rollback'
    puts "⚠️  Auto-rollback: performance dropped #{event.payload[:performance_drop]}"
  end
end
```

### Configuration and Privacy

Control what data gets collected:

```ruby
# OpenTelemetry configuration
otel_config = DSPy::Subscribers::OtelSubscriber::OtelConfig.new
otel_config.trace_optimization_events = true
otel_config.trace_lm_events = false          # Disable for privacy
otel_config.export_metrics = true
otel_config.sample_rate = 0.1                # Sample 10% of traces

# New Relic configuration  
newrelic_config = DSPy::Subscribers::NewrelicSubscriber::NewrelicConfig.new
newrelic_config.record_custom_metrics = true
newrelic_config.record_custom_events = false  # Disable events
newrelic_config.metric_prefix = 'Custom/MyApp/DSPy'

# Langfuse configuration
langfuse_config = DSPy::Subscribers::LangfuseSubscriber::LangfuseConfig.new
langfuse_config.log_prompts = false          # Disable for sensitive data
langfuse_config.log_completions = false
langfuse_config.trace_optimizations = true   # Keep optimization traces
```

### Production Best Practices

1. **Use sampling** for high-volume applications:
   ```bash
   export OTEL_TRACE_SAMPLE_RATE=0.1  # Sample 10%
   ```

2. **Control sensitive data**:
   ```ruby
   langfuse_config.log_prompts = false  # For sensitive prompts
   ```

3. **Set up cost alerts**:
   ```ruby
   DSPy::Instrumentation.subscribe('dspy.lm.request') do |event|
     cost = event.payload[:cost]
     alert_if_high_cost(cost) if cost && cost > 0.10
   end
   ```

4. **Monitor optimization success rates**:
   ```ruby
   # Track failed optimizations
   DSPy::Instrumentation.subscribe('dspy.optimization.error') do |event|
     ErrorReporter.notify(event.payload[:error_message])
   end
   ```

The observability system is designed to be zero-configuration for development and highly configurable for production environments. See the complete [Observability Guide](./lib/dspy/observability_guide.md) for detailed setup instructions and dashboard examples.

## License

This project is licensed under the MIT License.
