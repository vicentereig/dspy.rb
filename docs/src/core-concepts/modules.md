---
layout: docs
title: "DSPy Modules: Composable LLM Components in Ruby"
name: Modules
description: "Build reusable LLM modules and compose them with ordinary Ruby control flow."
date: 2025-07-10 00:00:00 +0000
last_modified_at: 2025-10-07 00:00:00 +0000
---
# Modules

`DSPy::Module` is the reusable execution boundary in DSPy.rb. `Predict`, `ChainOfThought`, and `ReAct` are modules; applications can subclass `DSPy::Module` to compose them with Ruby.

## Choose a Module Boundary

A module can own:
- **Execution strategies** through built-in or custom modules
- **Configuration** at the instance, fiber, or global level
- **Composition** through explicit Ruby method calls and control flow
- **Instrumentation** around each module call

## Subclass DSPy::Module

### Define `forward`

```ruby
class SentimentSignature < DSPy::Signature
  description "Analyze sentiment of text"
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, String
    const :confidence, Float
  end
end

class SentimentAnalyzer < DSPy::Module
  def initialize
    super
    
    # Create the predictor
    @predictor = DSPy::Predict.new(SentimentSignature)
  end

  def forward(text:)
    @predictor.call(text: text)
  end
end

# Usage
analyzer = SentimentAnalyzer.new
result = analyzer.call(text: "I love this product!")

puts result.sentiment    # => "positive"
puts result.confidence   # => 0.9
```

### Inject Module Configuration

```ruby
class ClassificationSignature < DSPy::Signature
  description "Classify text into categories"
  
  input do
    const :text, String
  end
  
  output do
    const :category, String
    const :reasoning, String
  end
end

class ConfigurableClassifier < DSPy::Module
  def initialize
    super
    
    # Create predictor
    @predictor = DSPy::ChainOfThought.new(ClassificationSignature)
  end

  def forward(text:)
    @predictor.call(text: text)
  end
end

# Usage
classifier = ConfigurableClassifier.new
result = classifier.call(text: "This is a technical document")
puts result.reasoning
```

## Override the Language Model at Runtime

See [Module Runtime Context](/dspy.rb/advanced/module-runtime-context/) for fiber-local language model overrides and lifecycle callbacks.


## Manual Module Composition

### Sequential Processing

```ruby
class DocumentProcessor < DSPy::Module
  def initialize
    super
    
    # Create sub-modules
    @classifier = DocumentClassifier.new
    @summarizer = DocumentSummarizer.new
    @extractor = KeywordExtractor.new
  end

  def forward(document:)
    # Step 1: Classify document type
    classification = @classifier.call(content: document)
    
    # Step 2: Generate summary
    summary = @summarizer.call(content: document)
    
    # Step 3: Extract keywords
    keywords = @extractor.call(content: document)
    
    # Return combined results
    {
      document_type: classification.document_type,
      summary: summary.summary,
      keywords: keywords.keywords
    }
  end
end
```

### Conditional Processing

```ruby
class AdaptiveAnalyzer < DSPy::Module
  def initialize
    super
    
    @content_detector = ContentTypeDetector.new
    @technical_analyzer = TechnicalAnalyzer.new
    @general_analyzer = GeneralAnalyzer.new
  end

  def forward(content:)
    # Determine content type
    content_type = @content_detector.call(content: content)
    
    # Route to appropriate analyzer based on result
    if content_type.type.downcase == 'technical'
      @technical_analyzer.call(content: content)
    else
      @general_analyzer.call(content: content)
    end
  end
end
```

## Compose Predictor Types

### Module Using Chain of Thought

```ruby
class ClassificationSignature < DSPy::Signature
  description "Classify text into categories"
  
  input do
    const :text, String
  end
  
  output do
    const :category, String
    # Note: ChainOfThought automatically adds a :reasoning field
    # Do NOT define your own :reasoning field when using ChainOfThought
  end
end

class ReasoningClassifier < DSPy::Module
  def initialize
    super
    
    # ChainOfThought enhances the signature with automatic reasoning
    @predictor = DSPy::ChainOfThought.new(ClassificationSignature)
  end

  def forward(text:)
    # The result will include both :category and :reasoning fields
    @predictor.call(text: text)
  end
end

# Usage
classifier = ReasoningClassifier.new
result = classifier.call(text: "This is a technical document")

puts result.category   # => "technical"
puts result.reasoning  # => "The document mentions APIs and code examples..."
```

### Module Using ReAct for Tool Integration

```ruby
require "dspy"
require "dspy/tools/text_processing_toolset"

class ResearchSignature < DSPy::Signature
  description "Answer a question about supplied text"
  
  input do
    const :text, String
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

class ResearchAssistant < DSPy::Module
  MAX_TEXT_BYTES = 100_000
  TOOL_NAMES = %w[text_wc text_extract_lines].freeze

  def initialize
    super

    text_tools = DSPy::Tools::TextProcessingToolset.to_tools.select do |tool|
      TOOL_NAMES.include?(tool.name)
    end

    @predictor = DSPy::ReAct.new(
      ResearchSignature,
      tools: text_tools,
      max_iterations: 5
    )
  end

  def forward(text:, question:)
    raise ArgumentError, "text exceeds 100,000 bytes" if text.bytesize > MAX_TEXT_BYTES

    @predictor.call(text: text, question: question)
  end
end
```

### Complete Example: Code Analysis Agent

This `ReAct` module exposes only the portable count and line-range operations. It caps application input and bounds model-directed steps:

```ruby
require "dspy"
require "dspy/tools/text_processing_toolset"

class CodeAnalysisSignature < DSPy::Signature
  description "Analyze source code and answer questions about it"

  input do
    const :source_code, String
    const :question, String
  end

  output do
    const :answer, String
    const :relevant_lines, T::Array[String]
  end
end

class CodeAnalyzer < DSPy::Module
  MAX_SOURCE_BYTES = 100_000
  TOOL_NAMES = %w[text_wc text_extract_lines].freeze

  def initialize
    super

    text_tools = DSPy::Tools::TextProcessingToolset.to_tools.select do |tool|
      TOOL_NAMES.include?(tool.name)
    end

    @agent = DSPy::ReAct.new(
      CodeAnalysisSignature,
      tools: text_tools,
      max_iterations: 5
    )
  end

  def forward(source_code:, question:)
    raise ArgumentError, "source exceeds 100,000 bytes" if source_code.bytesize > MAX_SOURCE_BYTES

    @agent.call(source_code: source_code, question: question)
  end
end

# Usage
analyzer = CodeAnalyzer.new

result = analyzer.call(
  source_code: File.read("app/models/user.rb"),
  question: "What validations are defined?"
)
puts result.answer
puts result.relevant_lines
```

These examples deliberately exclude `text_grep`, `text_rg`, and `text_filter_lines`: those helpers accept command or regular-expression patterns and do not provide process deadlines or input/output caps. Tool arguments remain untrusted even when the module input was validated, so use an application-owned wrapper when provider output limits do not satisfy the same byte budget. `max_iterations` limits agent steps; it does not cancel a running tool.

### Building a GitHub Issue Triage Agent

The core feature is `DSPy::Tools::GitHubCLIToolset`, loaded with `require "dspy/tools/github_cli_toolset"`. Do not pass its entire authenticated proxy set to a triage agent: that would expose broader repository and arbitrary GET API access than issue listing requires. Wrap only the required read operation with an application-owned repository allowlist, credential scope, command timeout, output cap, and failure redaction before giving it to `ReAct`.

See [Toolsets](../toolsets) to define and export tools.

### Module Using CodeAct for Dynamic Programming

CodeAct is available via the `dspy-code_act` gem. The complete Think-Code-Observe module example now lives in [`lib/dspy/code_act/README.md`](https://github.com/vicentereig/dspy.rb/blob/main/lib/dspy/code_act/README.md), alongside guidance on safety, observability, and advanced usage.

## Define a Custom Execution Strategy

### Creating Custom Modules

Subclass `DSPy::Module` when the built-in modules do not define the required execution pattern, as `DSPy::ReAct` (core) and `DSPy::CodeAct` (optional gem) do. Custom modules can own:
- Building specialized agent architectures
- Implementing custom inference patterns
- Creating domain-specific processing pipelines
- Extending DSPy.rb with new capabilities

```ruby
class CustomAgentSignature < DSPy::Signature
  description "Custom agent for specialized tasks"
  
  input do
    const :task, String
    const :context, T::Hash[String, T.untyped]
  end
  
  output do
    const :result, String
    const :reasoning, String
  end
end

class CustomAgent < DSPy::Module
  def initialize
    super
    
    # Initialize your custom inference components
    @planner = DSPy::ChainOfThought.new(PlanningSignature)
    @executor = DSPy::CodeAct.new(ExecutionSignature)  # Requires the dspy-code_act gem
    @validator = DSPy::Predict.new(ValidationSignature)
  end

  def forward(task:, context: {})
    # Implement your custom inference logic
    plan = @planner.call(task: task, context: context)
    
    execution = @executor.call(
      plan: plan.plan,
      context: context
    )
    
    validation = @validator.call(
      result: execution.solution,
      original_task: task
    )
    
    {
      result: execution.solution,
      reasoning: plan.reasoning,
      confidence: validation.confidence
    }
  end
end

# Usage
agent = CustomAgent.new
result = agent.call(
  task: "Analyze data and generate insights",
  context: { data_source: "database", format: "json" }
)
```

## Testing Modules

### Basic Module Testing

```ruby
# In your test file (using RSpec)
describe SentimentAnalyzer do
  let(:analyzer) { SentimentAnalyzer.new }

  it "analyzes sentiment" do
    result = analyzer.call(text: "I love this!")
    
    expect(result).to respond_to(:sentiment)
    expect(result).to respond_to(:confidence)
    expect(result.sentiment).to be_a(String)
    expect(result.confidence).to be_a(Float)
  end

  it "handles empty input" do
    expect {
      analyzer.call(text: "")
    }.not_to raise_error
  end
end
```

### Testing Module Composition

```ruby
describe DocumentProcessor do
  let(:processor) { DocumentProcessor.new }

  it "processes documents through all stages" do
    document = "Sample document content..."
    result = processor.call(document: document)
    
    expect(result).to have_key(:document_type)
    expect(result).to have_key(:summary)
    expect(result).to have_key(:keywords)
  end
end
```

## Keep Module Boundaries Narrow and Typed

### 1. Give a Module One Execution Job

```ruby
# Good: Focused responsibility
class EmailClassifier < DSPy::Module
  def initialize
    super
    # Only handles email classification
  end

  def forward(email:)
    # Single, clear purpose
  end
end

# Good: Separate concerns through composition
class EmailProcessor < DSPy::Module
  def initialize
    super
    @classifier = EmailClassifier.new
    @spam_detector = SpamDetector.new
  end
  
  def forward(email:)
    classification = @classifier.call(email: email)
    spam_result = @spam_detector.call(email: email)
    
    { 
      classification: classification,
      spam_score: spam_result.score
    }
  end
end
```

### 2. Declare Interfaces with Signatures

```ruby
class DocumentAnalysisSignature < DSPy::Signature
  description "Analyze document content"
  
  input do
    const :content, String
  end
  
  output do
    const :main_topics, T::Array[String]
    const :word_count, Integer
  end
end

class DocumentAnalyzer < DSPy::Module
  def initialize
    super
    
    @predictor = DSPy::Predict.new(DocumentAnalysisSignature)
  end
  
  def forward(content:)
    @predictor.call(content: content)
  end
end
```

## Instruction Update Contract

Optimizers such as GEPA and MIPROv2 expect predictors to expose immutable update hooks so they can safely swap instructions and few-shot examples. When you build a custom module that participates in optimization:

- Implement `with_instruction(new_instruction)` and return a new instance configured with the provided instruction.
- Implement `with_examples(few_shot_examples)` when your module supports few-shot updates, also returning a new instance.

You can include `DSPy::Mixins::InstructionUpdatable` to signal this capability and surface helpful default errors during development:

```ruby
class SentimentPredictor < DSPy::Module
  include DSPy::Mixins::InstructionUpdatable

  def initialize
    super
    @predictor = DSPy::Predict.new(SentimentSignature)
  end

  def with_instruction(instruction)
    clone = self.class.new
    clone.instance_variable_set(:@predictor, @predictor.with_instruction(instruction))
    clone
  end

  def with_examples(examples)
    clone = self.class.new
    clone.instance_variable_set(:@predictor, @predictor.with_examples(examples))
    clone
  end
end
```

If a module omits these hooks, optimizers raise `DSPy::InstructionUpdateError` instead of mutating instance variables directly.

## Expose Predictor Updates to Optimizers

Modules can work with the optimization framework through their underlying predictors:

```ruby
# Create your module
classifier = SentimentAnalyzer.new

# Use with basic optimization if available
# (Advanced optimization features are limited)
training_examples = [
  DSPy::FewShotExample.new(
    input: { text: "I love this!" },
    output: { sentiment: "positive", confidence: 0.9 }
  )
]

# Basic evaluation
result = classifier.call(text: "Test input")
```
