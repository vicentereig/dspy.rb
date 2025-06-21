# Experimental DSPy.rb Sorbet API

This document showcases the experimental Sorbet-based API for DSPy.rb, w
hich provides enhanced type safety and IDE integration through Sorbet's 
runtime type checking.

Eventually this will replace the dry-schema-based API, which is currently 
documented in the main README.

## Key Differences from the Main API

- **Type Safety**: Uses Sorbet's T::Struct for input/output validation instead of dry-schema
- **Enhanced IDE Support**: Full IDE integration with method signatures and return types
- **Field Descriptions**: Better LLM prompting through field descriptions that are preserved in JSON schemas
- **Runtime Validation**: Automatic validation of inputs and outputs with descriptive error messages

## Core Components

### Sorbet Signatures

Define structured inputs and outputs for LLM interactions using T::Struct-based schemas with field descriptions:

```ruby
class SentimentSignature < DSPy::SorbetSignature
  description "Classify sentiment of a given sentence."

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :sentence, String,
      description: 'The sentence to analyze'
  end

  output do
    const :sentiment, Sentiment,
      description: 'The sentiment classification'
    const :confidence, Float,
      description: 'Confidence score between 0.0 and 1.0'
  end
end
```

### Sorbet Predict

Basic LLM completion with structured inputs and outputs:

```ruby
# Configure DSPy with your LLM
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# Create predictor and run inference
classifier = DSPy::Predict.new(SentimentSignature)
result = classifier.call(sentence: "This book was super fun to read!")

# result is a properly typed T::Struct instance
puts result.sentiment    # => #<Sentiment::Positive>
puts result.confidence   # => 0.85
```

### Sorbet Chain of Thought

Enhanced reasoning through step-by-step thinking:

```ruby
class MathSignature < DSPy::SorbetSignature
  description "Solve mathematical problems step by step"

  input do
    const :problem, String,
      description: 'The mathematical problem to solve'
  end

  output do
    const :answer, String,
      description: 'The final numerical answer'
  end
end

# Chain of thought automatically adds a 'reasoning' field to the output
cot = DSPy::SorbetChainOfThought.new(MathSignature)
result = cot.call(problem: "What is the probability of getting a sum of 2 when rolling two dice?")

puts result.reasoning  # => "Let me think through this step by step..."
puts result.answer     # => "1/36"
```

### Sorbet Tools

Create type-safe tools for ReAct agents using Sorbet's method signatures:

```ruby
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
end

class AddNumbersTool < DSPy::Tools::Base

  tool_name 'add_numbers'
  tool_description 'Adds two numbers together'

  sig { params(x: Numeric, y: Numeric).returns(Numeric) }
  def call(x:, y:)
    x + y
  end
end
```

### Math ReAct Agent

Reasoning and Acting with type-safe tools:

```ruby
class MathQA < DSPy::SorbetSignature
  description "Answer mathematical questions using available tools"

  input do
    const :question, String,
      description: 'The math question to solve'
  end

  output do
    const :answer, String,
      description: 'The numerical answer to the question'
  end
end

# Create tools
calculator = CalculatorTool.new
adder = AddNumbersTool.new

# Create ReAct agent
agent = DSPy::SorbetReAct.new(MathQA, tools: [calculator, adder])

# The agent will automatically get enhanced output with history and iterations
result = agent.call(question: "What is 42 plus 58?")

puts result.answer      # => "100"
puts result.history     # => Array of reasoning steps
puts result.iterations  # => Number of reasoning iterations

# Each history entry contains structured information
result.history.each do |step|
  puts "Step #{step[:step]}: #{step[:thought]}"
  puts "Action: #{step[:action]} with input: #{step[:action_input]}"
  puts "Observation: #{step[:observation]}" if step[:observation]
end
```

## Enhanced Type Safety Features

### Runtime Validation

All Sorbet modules provide runtime validation:

```ruby
# Input validation
begin
  result = classifier.call(sentence: 123)  # Wrong type
rescue ArgumentError => e
  puts e.message  # Detailed validation error
end

# Output validation happens automatically
# If LLM returns invalid data, you'll get a clear error message
```

### Enhanced Output Structs

ReAct and ChainOfThought automatically create enhanced output structs:

```ruby
agent = DSPy::SorbetReAct.new(MathQA, tools: [calculator])

# Access the enhanced output struct class for your own type annotations
enhanced_class = agent.enhanced_output_struct
# => Class that includes original fields + history + iterations

# Results are instances of this enhanced class
result = agent.call(question: "What is 5 + 3?")
result.class == enhanced_class  # => true
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

class ColorSignature < DSPy::SorbetSignature
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

predictor = DSPy::SorbetPredict.new(ColorSignature)
result = predictor.call(description: "A red apple on a wooden table")
puts result.color  # => #<Color::Red>
```

### Optional Fields and Defaults

```ruby
class AnalysisSignature < DSPy::SorbetSignature
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
class TopicSignature < DSPy::SorbetSignature
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

class SummarySignature < DSPy::SorbetSignature
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

class ArticlePipeline < DSPy::SorbetModule
  extend T::Sig
  
  def initialize
    @topic_extractor = DSPy::SorbetPredict.new(TopicSignature)
    @summarizer = DSPy::SorbetChainOfThought.new(SummarySignature)
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

### RAG with Sorbet

```ruby
class ContextualQA < DSPy::SorbetSignature
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
qa = DSPy::SorbetChainOfThought.new(ContextualQA)

question = "What is the capital of France?"
context = retriever.retrieve(question)  # Returns array of strings

result = qa.call(question: question, context: context)
puts result.reasoning   # Step-by-step reasoning
puts result.answer      # "Paris"
puts result.confidence  # 0.95
```

## Migration from dry-schema API

The Sorbet API provides similar functionality with enhanced type safety:

### Before (dry-schema)
```ruby
class Classify < DSPy::Signature
  description "Classify sentiment"

  input do
    required(:sentence).value(:string).meta(description: 'Text to analyze')
  end

  output do
    required(:sentiment).value(included_in?: %w(positive negative neutral))
    required(:confidence).value(:float)
  end
end

classifier = DSPy::Predict.new(Classify)
```

### After (Sorbet)
```ruby
class SentimentSignature < DSPy::SorbetSignature
  description "Classify sentiment"

  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end

  input do
    const :sentence, String,
      description: 'Text to analyze'
  end

  output do
    const :sentiment, Sentiment,
      description: 'Sentiment: positive, negative, or neutral'
    const :confidence, Float,
      description: 'Confidence score'
  end
end

classifier = DSPy::SorbetPredict.new(SentimentSignature)
```

## Benefits of the Sorbet API

1. **Type Safety**: Compile-time and runtime type checking
2. **IDE Integration**: Full autocomplete and type information
3. **Better Error Messages**: Clear validation errors with field context
4. **Enhanced LLM Prompting**: Field descriptions improve LLM understanding
5. **Composability**: Type-safe module composition
6. **Runtime Validation**: Automatic input/output validation with T::Struct

## Limitations

1. **Experimental Status**: API may change as we gather feedback
2. **Sorbet Dependency**: Requires sorbet-runtime gem
3. **Learning Curve**: Developers need familiarity with Sorbet syntax
4. **Dynamic Types**: Some return types are T.untyped due to dynamic nature

## Future Roadmap

- Enhanced generic type support
- Better integration with Sorbet static type checker
- Performance optimizations
- Additional validation options
- Improved error messages and debugging tools
