---
layout: blog
title: "CodeAct: When Your AI Writes Ruby Code"
description: "Deep dive into DSPy.rb's unique CodeAct module for dynamic code generation. Discover how to build AI agents that write their own Ruby code to solve problems."
date: 2025-06-15
author: "Vicente Reig"
category: "Features"
reading_time: "10 min read"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/codeact-dynamic-code-generation/"
---

Imagine an AI that doesn't just call predefined tools but writes its own Ruby code to solve problems. That's CodeAct - a unique feature in DSPy.rb that sets it apart from the Python version.

## The Problem with Fixed Tools

Traditional AI agents come with a predefined set of tools:

```ruby
# ReAct agent with fixed tools
agent = DSPy::ReAct.new(MySignature, tools: {
  search: SearchTool.new,
  calculator: CalculatorTool.new,
  weather: WeatherTool.new
})
```

But what happens when you need something these tools can't do? Maybe you need to parse a custom data format, apply a complex transformation, or implement a one-off algorithm. You'd have to stop, write a new tool, deploy it, and then retry.

CodeAct flips this model: instead of giving the AI tools, let it write the tools it needs.

## How CodeAct Works

Under the hood, CodeAct is deceptively simple:

1. It receives a task description
2. Generates Ruby code to solve it
3. Executes the code in a sandboxed environment
4. Returns the result or iterates if needed

Here's a real example:

```ruby
agent = DSPy::CodeAct.new

result = agent.forward(
  task: "Find all prime numbers between 1 and 100",
  context: "You have access to standard Ruby"
)

# CodeAct generates something like:
# def is_prime?(n)
#   return false if n < 2
#   (2..Math.sqrt(n)).none? { |i| n % i == 0 }
# end
# 
# (1..100).select { |n| is_prime?(n) }
```

## Real-World Use Cases

### Data Analysis on the Fly

```ruby
sales_data = {
  "2024-Q1" => { revenue: 1_200_000, costs: 800_000 },
  "2024-Q2" => { revenue: 1_500_000, costs: 900_000 },
  "2024-Q3" => { revenue: 1_800_000, costs: 950_000 },
  "2024-Q4" => { revenue: 2_100_000, costs: 1_100_000 }
}

result = agent.forward(
  task: "Calculate profit margins by quarter and identify trends",
  context: "sales_data contains quarterly financial data",
  data: { sales_data: sales_data }
)

# Output: "Profit margins increased from 33.3% in Q1 to 47.6% in Q4, 
#          showing consistent improvement. Q4 had the highest absolute 
#          profit of $1M despite increased costs."
```

### Custom Data Transformations

```ruby
# Complex nested JSON that needs flattening
api_response = {
  users: [
    { id: 1, profile: { name: "Alice", email: "alice@example.com" } },
    { id: 2, profile: { name: "Bob", email: "bob@example.com" } }
  ]
}

result = agent.forward(
  task: "Flatten this nested structure into a CSV-friendly format",
  context: "api_response contains nested user data",
  data: { api_response: api_response }
)

# CodeAct writes the transformation code:
# flattened = api_response[:users].map do |user|
#   {
#     user_id: user[:id],
#     name: user[:profile][:name],
#     email: user[:profile][:email]
#   }
# end
```

### Algorithm Implementation

```ruby
result = agent.forward(
  task: "Implement the Luhn algorithm to validate this credit card number: 4532015112830366",
  context: "Return true if valid, false otherwise"
)

# CodeAct implements Luhn from scratch:
# def luhn_valid?(number)
#   digits = number.to_s.chars.map(&:to_i)
#   checksum = digits.reverse.each_with_index.sum do |digit, index|
#     if index.odd?
#       doubled = digit * 2
#       doubled > 9 ? doubled - 9 : doubled
#     else
#       digit
#     end
#   end
#   checksum % 10 == 0
# end
```

## Safety First

Executing arbitrary code is dangerous. Here's how we handle it:

### Current Sandboxing

```ruby
class DSPy::CodeAct
  def execute_code(code)
    # Basic sandboxing
    safe_binding = binding
    
    # Remove dangerous methods
    %w[system exec `].each do |method|
      safe_binding.eval("undef #{method} if defined?(#{method})")
    end
    
    # Execute with timeout
    Timeout.timeout(5) do
      safe_binding.eval(code)
    end
  rescue Timeout::Error
    "Code execution timed out"
  end
end
```

### Production Considerations

For production use, consider additional layers:

```ruby
# Wrap CodeAct with additional safety
class SafeCodeAct
  def initialize
    @codeact = DSPy::CodeAct.new
    @executions = 0
  end
  
  def forward(task:, context:, data: {})
    # Rate limiting
    raise "Rate limit exceeded" if @executions >= 100
    @executions += 1
    
    # Input sanitization
    sanitized_task = sanitize_input(task)
    
    # Memory limits
    result = nil
    memory_before = GetProcessMem.new.mb
    
    result = @codeact.forward(
      task: sanitized_task,
      context: context + "\nDo not use system calls or file operations.",
      data: data
    )
    
    memory_after = GetProcessMem.new.mb
    if memory_after - memory_before > 50 # MB
      raise "Memory limit exceeded"
    end
    
    result
  end
  
  private
  
  def sanitize_input(input)
    # Remove potential system commands
    input.gsub(/system|exec|`|eval|load|require/, '[REDACTED]')
  end
end
```

## Debugging CodeAct

When things go wrong, CodeAct provides full visibility:

```ruby
# Enable detailed logging
DSPy.configure do |c|
  c.logger = Dry.Logger(:dspy) do |logger|
    logger.add_backend(level: :debug, stream: $stdout)
  end
end

result = agent.forward(task: "Complex task that might fail")

# Inspect the execution history
result.history.each_with_index do |step, i|
  puts "\n=== Step #{i + 1} ==="
  puts "Thought: #{step.thought}"
  puts "Code generated:"
  puts step.ruby_code
  
  if step.error_message.present?
    puts "ERROR: #{step.error_message}"
  else
    puts "Result: #{step.execution_result}"
  end
end
```

## CodeAct vs ReAct: When to Use Which

### Use CodeAct When:
- The task requires custom logic or algorithms
- You're doing data analysis or transformation
- You need a one-off solution
- Flexibility is more important than safety

### Use ReAct When:
- You have well-defined tools that cover your needs
- You need to interact with external APIs
- Safety and predictability are paramount
- You want to limit what the AI can do

Here's a practical example of choosing between them:

```ruby
# Task: "Get weather and calculate clothing recommendations"

# ReAct approach - safer, more controlled
weather_tool = WeatherAPI.new
clothing_tool = ClothingRecommender.new

react_agent = DSPy::ReAct.new(
  WeatherAdvice,
  tools: { weather: weather_tool, clothing: clothing_tool }
)

# CodeAct approach - more flexible, can create custom logic
codeact_agent = DSPy::CodeAct.new

result = codeact_agent.forward(
  task: "Get weather for Tokyo and suggest clothing based on temperature, humidity, and wind",
  context: "Use these APIs: WeatherAPI.get('Tokyo'), consider comfort ranges"
)
# CodeAct might create its own comfort index algorithm
```

## Advanced Patterns

### Iterative Problem Solving

CodeAct can refine its approach based on errors:

```ruby
result = agent.forward(
  task: "Parse this CSV with unknown delimiters and quote characters",
  context: "The data variable contains raw CSV text",
  data: { csv_text: 'name|age|city\n"John"|"30"|"New York"' }
)

# First attempt might assume comma delimiter
# When that fails, CodeAct tries different approaches
# Until it discovers the pipe delimiter
```

### Code Generation for Code

CodeAct can even generate DSPy code:

```ruby
result = agent.forward(
  task: "Create a DSPy signature for extracting product information from descriptions",
  context: "Generate a complete DSPy::Signature subclass"
)

# Outputs:
# class ProductExtractor < DSPy::Signature
#   description "Extract product details from descriptions"
#   
#   input do
#     const :description, String
#   end
#   
#   output do
#     const :name, String
#     const :price, T.nilable(Float)
#     const :features, T::Array[String]
#   end
# end
```

## The Future of CodeAct

We're working on several enhancements:

1. **Better Sandboxing**: Container-based execution for true isolation
2. **Code Caching**: Reuse generated code for similar tasks
3. **Type Inference**: Automatically detect and validate return types
4. **Async Execution**: Run code generation in background jobs
5. **Code Explanation**: Generate comments explaining the code

## Try It Yourself

Here's a challenge to get you started:

```ruby
require 'dspy'

DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

agent = DSPy::CodeAct.new

# Challenge: Have CodeAct solve a problem you face daily
result = agent.forward(
  task: "YOUR TASK HERE",
  context: "Any context needed",
  data: { your_data: "here" }
)

puts result.final_answer
```

## Conclusion

CodeAct represents a different way of thinking about AI agents. Instead of constraining them to predefined tools, we give them the power to create their own solutions. It's not right for every use case, but when you need flexibility and creativity, CodeAct delivers.

Remember: with great power comes great responsibility. Always validate CodeAct's output and use appropriate safety measures in production.

---

*Have you used CodeAct for something interesting? We'd love to hear about it! Share your experiences in our [GitHub discussions](https://github.com/vicentereig/dspy.rb/discussions).*