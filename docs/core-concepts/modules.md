# Modules

DSPy.rb modules provide a foundation for building reusable LLM components. The `DSPy::Module` class serves as a base class for creating custom predictors that can be configured and tested.

## Overview

DSPy modules enable:
- **Custom Predictors**: Build specialized LLM components
- **Configuration**: Per-instance and global language model configuration
- **Manual Composition**: Combine multiple modules through explicit method calls
- **Type Safety**: Sorbet integration for type-safe interfaces

## Basic Module Structure

### Creating a Custom Module

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

  def forward_untyped(text:)
    @predictor.call(text: text)
  end
end

# Usage
analyzer = SentimentAnalyzer.new
result = analyzer.call(text: "I love this product!")

puts result.sentiment    # => "positive"
puts result.confidence   # => 0.9
```

### Module with Language Model Configuration

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
  def initialize(custom_lm: nil)
    super
    
    # Configure the language model for this instance
    if custom_lm
      configure do |config|
        config.lm = custom_lm
      end
    end
    
    # Create predictor (will use configured LM)
    @predictor = DSPy::ChainOfThought.new(ClassificationSignature)
  end

  def forward_untyped(text:)
    @predictor.call(text: text)
  end
end

# Usage with custom language model
custom_lm = DSPy::LM.new('openai/gpt-4')
classifier = ConfigurableClassifier.new(custom_lm: custom_lm)
result = classifier.call(text: "This is a technical document")
puts result.reasoning
```

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

  def forward_untyped(document:)
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

  def forward_untyped(content:)
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

## Working with Different Predictors

### Module Using Chain of Thought

```ruby
class ReasoningSignature < DSPy::Signature
  description "Classify with reasoning"
  
  input do
    const :text, String
  end
  
  output do
    const :category, String
    const :reasoning, String
  end
end

class ReasoningClassifier < DSPy::Module
  def initialize
    super
    
    @predictor = DSPy::ChainOfThought.new(ReasoningSignature)
  end

  def forward_untyped(text:)
    @predictor.call(text: text)
  end
end
```

### Module Using ReAct for Tool Integration

```ruby
class ResearchSignature < DSPy::Signature
  description "Research assistant"
  
  input do
    const :query, String
  end
  
  output do
    const :answer, String
  end
end

class ResearchAssistant < DSPy::Module
  def initialize
    super
    
    # Create individual tools
    calculator = DSPy::Tools::CalculatorTool.new
    
    # Or use a toolset (multiple tools from one class)
    memory_tools = DSPy::Tools::MemoryToolset.to_tools
    
    @tools = [calculator, *memory_tools]
    
    @predictor = DSPy::ReAct.new(ResearchSignature, tools: @tools)
  end

  def forward_untyped(query:)
    @predictor.call(query: query)
  end
end
```

For more details on creating tools and toolsets, see the [Toolsets documentation](toolsets.md).

### Module Using CodeAct for Dynamic Programming

```ruby
class DataAnalysisSignature < DSPy::Signature
  description "Analyze data using Ruby code execution"
  
  input do
    const :dataset_description, String
    const :analysis_task, String
  end
  
  output do
    const :analysis_result, String
  end
end

class DataAnalyst < DSPy::Module
  def initialize
    super
    
    @predictor = DSPy::CodeAct.new(DataAnalysisSignature, max_iterations: 8)
  end

  def forward_untyped(dataset_description:, analysis_task:)
    # Combine inputs for the code execution agent
    task = "Dataset: #{dataset_description}\nTask: #{analysis_task}"
    
    result = @predictor.call(task: task)
    
    # CodeAct provides additional execution context
    {
      analysis_result: result.solution,
      execution_steps: result.history.length,
      code_executed: result.history.map { |h| h[:ruby_code] }.compact
    }
  end
end

# Usage
analyst = DataAnalyst.new
result = analyst.call(
  dataset_description: "Array of sales data: [100, 150, 200, 300, 250]",
  analysis_task: "Calculate the average and identify the highest sale"
)

puts result[:analysis_result]
# => "Average: 200, Highest: 300"
puts result[:execution_steps]
# => 3
```

## Language Model Configuration

### Using Custom Language Model

```ruby
class CustomModuleSignature < DSPy::Signature
  description "Your module description"
  
  input do
    const :text, String
  end
  
  output do
    const :result, String
  end
end

class CustomLMModule < DSPy::Module
  def initialize(custom_lm: nil)
    super
    
    # Configure custom LM if provided
    if custom_lm
      configure do |config|
        config.lm = custom_lm
      end
    end
    
    @predictor = DSPy::Predict.new(CustomModuleSignature)
  end

  def forward_untyped(**inputs)
    # Uses the configured LM (custom or global)
    @predictor.call(**inputs)
  end
end

# Usage with custom LM
custom_lm = DSPy::LM.new('openai/gpt-4')
module_with_custom_lm = CustomLMModule.new(custom_lm: custom_lm)
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

## Best Practices

### 1. Single Responsibility

```ruby
# Good: Focused responsibility
class EmailClassifier < DSPy::Module
  def initialize
    super
    # Only handles email classification
  end

  def forward_untyped(email:)
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
  
  def forward_untyped(email:)
    classification = @classifier.call(email: email)
    spam_result = @spam_detector.call(email: email)
    
    { 
      classification: classification,
      spam_score: spam_result.score
    }
  end
end
```

### 2. Clear Interfaces with Signatures

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
  
  def forward_untyped(content:)
    @predictor.call(content: content)
  end
end
```

## Basic Optimization Support

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

