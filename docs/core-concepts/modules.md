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
class SentimentAnalyzer < DSPy::Module
  def initialize
    super
    
    # Define the signature for this module
    @signature = Class.new(DSPy::Signature) do
      description "Analyze sentiment of text"
      
      input do
        const :text, String
      end
      
      output do
        const :sentiment, String
        const :confidence, Float
      end
    end
    
    # Create the predictor
    @predictor = DSPy::Predict.new(@signature)
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
class ConfigurableClassifier < DSPy::Module
  def initialize(custom_lm: nil)
    super
    
    # Configure the language model for this instance
    if custom_lm
      configure do |config|
        config.lm = custom_lm
      end
    end
    
    @signature = Class.new(DSPy::Signature) do
      description "Classify text into categories"
      
      input do
        const :text, String
      end
      
      output do
        const :category, String
        const :reasoning, String
      end
    end
    
    # Create predictor (will use configured LM)
    @predictor = DSPy::ChainOfThought.new(@signature)
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
class ReasoningClassifier < DSPy::Module
  def initialize
    super
    
    @signature = Class.new(DSPy::Signature) do
      description "Classify with reasoning"
      
      input do
        const :text, String
      end
      
      output do
        const :category, String
        const :reasoning, String
      end
    end
    
    @predictor = DSPy::ChainOfThought.new(@signature)
  end

  def forward_untyped(text:)
    @predictor.call(text: text)
  end
end
```

### Module Using ReAct for Tool Integration

```ruby
class ResearchAssistant < DSPy::Module
  def initialize
    super
    
    @signature = Class.new(DSPy::Signature) do
      description "Research assistant"
      
      input do
        const :query, String
      end
      
      output do
        const :answer, String
      end
    end
    
    # Define available tools (basic tool support)
    @tools = [
      # Tool instances would go here
    ]
    
    @predictor = DSPy::ReAct.new(@signature, tools: @tools)
  end

  def forward_untyped(query:)
    @predictor.call(query: query)
  end
end
```

## Language Model Configuration

### Using Custom Language Model

```ruby
class CustomLMModule < DSPy::Module
  def initialize(custom_lm: nil)
    super
    
    # Configure custom LM if provided
    if custom_lm
      configure do |config|
        config.lm = custom_lm
      end
    end
    
    @signature = Class.new(DSPy::Signature) do
      description "Your module description"
      
      input do
        const :text, String
      end
      
      output do
        const :result, String
      end
    end
    
    @predictor = DSPy::Predict.new(@signature)
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
class DocumentAnalyzer < DSPy::Module
  def initialize
    super
    
    @signature = Class.new(DSPy::Signature) do
      description "Analyze document content"
      
      input do
        const :content, String
      end
      
      output do
        const :main_topics, T::Array[String]
        const :word_count, Integer
      end
    end
    
    @predictor = DSPy::Predict.new(@signature)
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

