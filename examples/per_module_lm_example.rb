# frozen_string_literal: true

# Example: Per-Module LM Configuration
# This demonstrates how different DSPy modules can use different LMs
# for optimal performance and cost efficiency

require_relative '../lib/dspy'

# Define signatures for different tasks
class SimpleClassification < DSPy::Signature
  description "Quick sentiment classification"

  input do
    const :text, String, description: "Text to classify"
  end

  output do
    const :sentiment, String, description: "positive, negative, or neutral"
  end
end

class ComplexReasoning < DSPy::Signature
  description "Complex mathematical reasoning task"

  input do  
    const :problem, String, description: "Mathematical word problem"
  end

  output do
    const :solution, String, description: "Step-by-step solution"
    const :answer, String, description: "Final numerical answer"
  end
end

# Set up different LMs for different use cases
fast_lm = DSPy::LM.new('openai/gpt-3.5-turbo', api_key: ENV['OPENAI_API_KEY'])
smart_lm = DSPy::LM.new('openai/gpt-4', api_key: ENV['OPENAI_API_KEY'])
reasoning_lm = DSPy::LM.new('openai/gpt-4-turbo', api_key: ENV['OPENAI_API_KEY'])

# Configure global default (for most tasks)
DSPy.configure do |config|
  config.lm = fast_lm
end

# Example 1: Basic usage with global LM
puts "=== Example 1: Using Global LM ==="
basic_classifier = DSPy::Predict.new(SimpleClassification)
puts "Basic classifier uses: #{basic_classifier.lm.model}"

# Example 2: Override LM for specific module
puts "\n=== Example 2: Per-Module LM Override ==="
premium_classifier = DSPy::Predict.new(SimpleClassification)
premium_classifier.configure { |config| config.lm = smart_lm }
puts "Premium classifier uses: #{premium_classifier.lm.model}"

# Example 3: Different modules for different complexity levels
puts "\n=== Example 3: Complexity-Based LM Assignment ==="

# Fast classification for simple tasks
sentiment_analyzer = DSPy::Predict.new(SimpleClassification)
puts "Sentiment analyzer uses: #{sentiment_analyzer.lm.model}"

# Smart reasoning for complex tasks  
math_solver = DSPy::ChainOfThought.new(ComplexReasoning)
math_solver.configure { |config| config.lm = reasoning_lm }
puts "Math solver uses: #{math_solver.lm.model}"

# Example 4: Pipeline with mixed LMs
puts "\n=== Example 4: Multi-Stage Pipeline ==="

class DocumentSummary < DSPy::Signature
  description "Summarize document content"
  
  input do
    const :document, String, description: "Full document text"
  end
  
  output do
    const :summary, String, description: "Concise summary"
  end
end

class QualityCheck < DSPy::Signature
  description "Check summary quality and accuracy"
  
  input do
    const :original, String, description: "Original document"
    const :summary, String, description: "Generated summary"  
  end
  
  output do
    const :quality_score, String, description: "Quality score from 1-10"
    const :feedback, String, description: "Improvement suggestions"
  end
end

# Pipeline: Fast summarization + Smart quality check
summarizer = DSPy::Predict.new(DocumentSummary) # Uses global fast_lm

quality_checker = DSPy::Predict.new(QualityCheck)
quality_checker.configure { |config| config.lm = smart_lm }

puts "Summarizer uses: #{summarizer.lm.model}"
puts "Quality checker uses: #{quality_checker.lm.model}"

# Example 5: ReAct agents with different capabilities
puts "\n=== Example 5: ReAct Agents with Specialized LMs ==="

# Simple calculator tool
class CalculatorTool < DSPy::Tools::Base
  tool_name "calculator"
  tool_description "Performs basic arithmetic operations"

  sig { params(operation: String, x: Float, y: Float).returns(Float) }
  def call(operation:, x:, y:)
    case operation
    when "add" then x + y
    when "multiply" then x * y
    else 0.0
    end
  end
end

class BasicMath < DSPy::Signature
  description "Solve basic math problems"
  
  input do
    const :question, String, description: "Math question"
  end
  
  output do
    const :answer, String, description: "Final answer"
  end
end

# Basic ReAct agent with fast LM
basic_agent = DSPy::ReAct.new(BasicMath, tools: [CalculatorTool.new])
puts "Basic ReAct agent uses: #{basic_agent.lm.model}"

# Advanced ReAct agent with reasoning LM
advanced_agent = DSPy::ReAct.new(BasicMath, tools: [CalculatorTool.new])
advanced_agent.configure { |config| config.lm = reasoning_lm }
puts "Advanced ReAct agent uses: #{advanced_agent.lm.model}"

# Example 6: Cost optimization strategy
puts "\n=== Example 6: Cost Optimization ==="

def create_cost_optimized_pipeline
  # Use fast LM for preprocessing
  preprocessor = DSPy::Predict.new(SimpleClassification)
  
  # Use smart LM only for complex cases
  complex_handler = DSPy::ChainOfThought.new(ComplexReasoning)
  complex_handler.configure { |config| config.lm = smart_lm }
  
  # Use reasoning LM for final validation
  validator = DSPy::Predict.new(QualityCheck)
  validator.configure { |config| config.lm = reasoning_lm }
  
  {
    preprocessor: preprocessor,
    complex_handler: complex_handler,
    validator: validator
  }
end

pipeline = create_cost_optimized_pipeline
puts "Preprocessor: #{pipeline[:preprocessor].lm.model} (cost-efficient)"
puts "Complex handler: #{pipeline[:complex_handler].lm.model} (balanced)"
puts "Validator: #{pipeline[:validator].lm.model} (highest quality)"

# Example 7: Advanced configuration patterns
puts "\n=== Example 7: Advanced Configuration Patterns ==="

# Method chaining alternative with configure
reasoner = DSPy::ChainOfThought.new(ComplexReasoning)
reasoner.configure do |config|
  config.lm = reasoning_lm
  # Future configuration options could be added here:
  # config.temperature = 0.2
  # config.max_tokens = 2000
end

puts "Advanced reasoner uses: #{reasoner.lm.model}"

# Direct config access
quick_classifier = DSPy::Predict.new(SimpleClassification)
quick_classifier.config.lm = fast_lm
puts "Quick classifier uses: #{quick_classifier.lm.model}"

puts "\n=== Benefits of Per-Module LM Configuration ==="
puts "✓ Cost optimization: Use cheaper models for simple tasks"
puts "✓ Performance optimization: Use powerful models for complex reasoning"
puts "✓ Flexibility: Mix and match LMs based on requirements"
puts "✓ Isolation: Each module's LM choice doesn't affect others"
puts "✓ Backward compatibility: Global configuration still works"
puts "✓ Standard interface: Uses familiar Dry::Configurable patterns"
