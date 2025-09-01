---
layout: docs
title: 'CodeAct: Dynamic Code Generation'
description: Build intelligent agents that write and execute Ruby code dynamically
  for creative problem-solving
date: 2025-07-11 00:00:00 +0000
last_modified_at: 2025-08-13 00:00:00 +0000
---
# CodeAct: Dynamic Code Generation

CodeAct is a unique DSPy.rb module that enables AI agents to write and execute Ruby code dynamically. Unlike ReAct agents that use predefined tools, CodeAct agents can create their own solutions by generating code on the fly.

## When to Use CodeAct vs ReAct

### Use CodeAct when:
- You need flexible, creative solutions
- The task involves data transformation or analysis
- You want the agent to create custom algorithms
- Pre-defined tools are too limiting

### Use ReAct when:
- You have specific, well-defined tools
- You need predictable, controlled behavior
- External API calls are involved
- Safety and sandboxing are critical concerns

## Basic Example

```ruby
require 'dspy'

# Configure your language model
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# Create a CodeAct agent
agent = DSPy::CodeAct.new

# Ask it to solve a problem
result = agent.forward(
  task: "Calculate the Fibonacci sequence up to the 10th number",
  context: "You have access to standard Ruby libraries"
)

puts result.final_answer
# => [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]

# Inspect the generated code
result.history.each do |step|
  puts "Step #{step.step}:"
  puts "Thought: #{step.thought}"
  puts "Code: #{step.ruby_code}"
  puts "Result: #{step.execution_result}"
  puts "---"
end
```

## Advanced Usage

### Custom Execution Context

You can provide a custom context with pre-loaded data or helper methods:

```ruby
# Prepare data for analysis
sales_data = {
  "January" => [100, 150, 200],
  "February" => [120, 180, 190],
  "March" => [140, 210, 220]
}

agent = DSPy::CodeAct.new

result = agent.forward(
  task: "Calculate the average sales for each month and identify the best performing month",
  context: "You have access to a hash called `sales_data` with monthly sales figures",
  data: { sales_data: sales_data }
)

puts result.final_answer
# => "March is the best performing month with an average of 190.0"
```

### Complex Data Processing

CodeAct excels at tasks requiring custom logic:

```ruby
result = agent.forward(
  task: "Parse this CSV data and find all email addresses that belong to gmail.com",
  context: "CSV data is provided in the `csv_content` variable",
  data: {
    csv_content: <<~CSV
      name,email,department
      John Doe,john@gmail.com,Engineering
      Jane Smith,jane@company.com,Marketing
      Bob Johnson,bob@gmail.com,Sales
    CSV
  }
)

# The agent might generate code like:
# require 'csv'
# gmail_emails = []
# CSV.parse(csv_content, headers: true) do |row|
#   gmail_emails << row['email'] if row['email'].end_with?('@gmail.com')
# end
# gmail_emails
```

## Safety Considerations

CodeAct executes arbitrary Ruby code, which requires careful consideration:

### 1. Sandboxing (Currently Limited)
```ruby
# CodeAct currently uses basic sandboxing
# For production use, consider additional measures:

class SafeCodeAct < DSPy::CodeAct
  def execute_code(code)
    # Add timeout
    Timeout.timeout(5) do
      super
    end
  rescue Timeout::Error
    "Code execution timed out"
  end
end
```

### 2. Input Validation
```ruby
# Always validate and sanitize task descriptions
def safe_task(user_input)
  # Remove potential system commands
  user_input.gsub(/`.*?`/, '')
            .gsub(/system|exec|eval|load|require/, '')
end

result = agent.forward(
  task: safe_task(params[:user_task]),
  context: "Limited to data processing only"
)
```

### 3. Resource Limits
```ruby
# Monitor memory and CPU usage
require 'get_process_mem'

before_memory = GetProcessMem.new.mb

result = agent.forward(task: "Complex analysis task")

after_memory = GetProcessMem.new.mb
memory_used = after_memory - before_memory

if memory_used > 100 # MB
  # Log warning or take action
end
```

## Real-World Example: Data Analysis Pipeline

Here's how to use CodeAct for a realistic data analysis task:

```ruby
# Sales analysis agent
class SalesAnalyzer < DSPy::Module
  def initialize
    @code_act = DSPy::CodeAct.new
  end

  def analyze_trends(sales_data)
    result = @code_act.forward(
      task: <<~TASK,
        Analyze the sales data to:
        1. Calculate month-over-month growth rates
        2. Identify seasonal patterns
        3. Predict next month's sales using simple linear regression
        4. Return findings as a structured report
      TASK
      context: <<~CONTEXT,
        You have access to:
        - sales_data: Hash with dates as keys and sales amounts as values
        - Standard Ruby libraries
        - You may use simple statistical calculations
      CONTEXT
      data: { sales_data: sales_data }
    )
    
    # Parse and return structured results
    {
      analysis: result.final_answer,
      code_steps: result.history.map { |h| h.ruby_code },
      execution_time: result.metadata[:total_time]
    }
  end
end

# Usage
analyzer = SalesAnalyzer.new
report = analyzer.analyze_trends({
  "2024-01" => 10000,
  "2024-02" => 12000,
  "2024-03" => 11500,
  "2024-04" => 14000,
  "2024-05" => 15500,
  "2024-06" => 16000
})
```

## Debugging CodeAct

Enable logging to see what's happening:

```ruby
DSPy.configure do |c|
  config.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(level: :debug, stream: $stdout)
  end
end

# This will log each code generation attempt and execution result
result = agent.forward(task: "Debug this calculation: 1 + '2'")

# Access raw history for debugging
result.history.each do |step|
  if step.error_message.present?
    puts "Error in step #{step.step}: #{step.error_message}"
    puts "Failed code: #{step.ruby_code}"
  end
end
```

## Limitations and Future Improvements

Current limitations:
- Basic sandboxing (not suitable for untrusted input)
- No access to external gems during execution
- Limited to synchronous execution
- No built-in rate limiting

Planned improvements:
- Better sandboxing with containers
- Async execution support
- Integration with Jupyter-style notebooks
- Code explanation generation

## Best Practices

1. **Start Simple**: Test with basic tasks before complex ones
2. **Provide Context**: Clear context leads to better code generation
3. **Validate Output**: Always validate generated code results
4. **Monitor Resources**: Set timeouts and memory limits
5. **Log Everything**: Enable observability with Langfuse in production

## Next Steps

- Explore [ReAct agents](../predictors#dspyreact) for tool-based approaches
- Learn about [custom signatures](../signatures) for CodeAct
- See [production considerations](../../production) for deployment
