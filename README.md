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
- 🚧 Saving/loading optimized programs - *In Progress*
- OTel Integration
- Ollama support

## Installation

Skip the gem for now - install straight from this repo while I prep the first release:
```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

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

## Instrumentation & Observability

DSPy.rb includes built-in instrumentation that captures detailed events and 
performance metrics from your LLM operations. Perfect for monitoring your 
applications and integrating with observability tools.

### Available Events

Subscribe to these events to monitor different aspects of your LLM operations:

| Event Name | Triggered When | Key Payload Fields |
|------------|----------------|-------------------|
| `dspy.lm.request` | LLM API request lifecycle | `gen_ai_system`, `model`, `provider`, `duration_ms`, `status` |
| `dspy.lm.tokens` | Token usage tracking | `tokens_input`, `tokens_output`, `tokens_total` |
| `dspy.predict` | Prediction operations | `signature_class`, `input_size`, `duration_ms`, `status` |
| `dspy.chain_of_thought` | CoT reasoning | `signature_class`, `model`, `duration_ms`, `status` |
| `dspy.react` | Agent operations | `max_iterations`, `tools_used`, `duration_ms`, `status` |
| `dspy.react.tool_call` | Tool execution | `tool_name`, `tool_input`, `tool_output`, `duration_ms` |
| `dspy.evaluation.start` | Evaluation begins | `total_examples`, `metric_name`, `num_threads` |
| `dspy.evaluation.example` | Single example evaluated | `example_id`, `prediction`, `passed`, `duration_ms` |
| `dspy.evaluation.batch_complete` | Batch evaluation finished | `accuracy`, `passed_examples`, `total_examples` |
| `dspy.optimization.start` | Optimization begins | `teleprompter_class`, `trainset_size`, `valset_size` |
| `dspy.optimization.complete` | Optimization finished | `best_score`, `total_trials`, `duration_ms` |
| `dspy.optimization.trial_start` | Individual trial begins | `trial_number`, `candidate_instruction` |
| `dspy.optimization.trial_complete` | Trial finished | `trial_score`, `trial_passed`, `duration_ms` |

### Event Payloads

The instrumentation emits events with structured payloads you can process:

```ruby
# Example event payload for dspy.predict
{
  signature_class: "QuestionAnswering",
  model: "gpt-4o-mini",
  provider: "openai", 
  input_size: 45,
  duration_ms: 1234.56,
  cpu_time_ms: 89.12,
  status: "success",
  timestamp: "2024-01-15T10:30:00Z"
}

# Example token usage payload
{
  tokens_input: 150,
  tokens_output: 45,
  tokens_total: 195,
  gen_ai_system: "openai",
  signature_class: "QuestionAnswering"
}
```

Events are emitted via dry-monitor notifications, giving you flexibility to 
process them however you need - logging, metrics, alerts, or custom monitoring.

### Token Tracking

Token usage is extracted from actual API responses (OpenAI and Anthropic only), 
giving you precise cost tracking:

```ruby
# Token events include:
{
  tokens_input: 150,     # From API response
  tokens_output: 45,     # From API response  
  tokens_total: 195,     # From API response
  gen_ai_system: "openai",
  gen_ai_request_model: "gpt-4o-mini"
}
```

### Integration with Monitoring Tools

Subscribe to events for custom processing:

```ruby
# Subscribe to all LM events
DSPy::Instrumentation.subscribe('dspy.lm.*') do |event|
  puts "#{event.id}: #{event.payload[:duration_ms]}ms"
end

# Subscribe to specific events
DSPy::Instrumentation.subscribe('dspy.predict') do |event|
  MyMetrics.histogram('dspy.predict.duration', event.payload[:duration_ms])
end

# Monitor optimization progress
DSPy::Instrumentation.subscribe('dspy.optimization.*') do |event|
  case event.id
  when 'dspy.optimization.start'
    puts "Starting optimization with #{event.payload[:trainset_size]} examples"
  when 'dspy.optimization.trial_complete'
    puts "Trial #{event.payload[:trial_number]} scored #{event.payload[:trial_score]}"
  when 'dspy.optimization.complete'
    puts "Optimization finished! Best score: #{event.payload[:best_score]}"
  end
end
```

## License

This project is licensed under the MIT License.
