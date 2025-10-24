# CodeAct: Dynamic Code Generation for DSPy.rb

CodeAct is a DSPy.rb module that enables agents to write and execute Ruby code dynamically. Unlike ReAct agents that rely on predefined tools, CodeAct generates tailored Ruby code on the fly to solve complex tasks.

## When to Use CodeAct

- Choose CodeAct when you need creative problem solving, custom data transformations, or bespoke algorithms.
- Prefer ReAct when you have well-defined tools, must call external services, or need stricter safety guarantees.

## Quick Start

```ruby
require 'dspy'
require 'dspy/code_act'

DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV.fetch('OPENAI_API_KEY'))
end

agent = DSPy::CodeAct.new

result = agent.forward(
  task: "Calculate the Fibonacci sequence up to the 10th number",
  context: "You have access to standard Ruby libraries"
)

puts result.final_answer
# => [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]

result.history.each do |step|
  puts "Step #{step.step}"
  puts "Thought: #{step.thought}"
  puts "Code: #{step.ruby_code}"
  puts "Result: #{step.execution_result}"
end
```

## Advanced Usage

### Custom Execution Context

Provide structured data or helper methods with the `context` argument so generated code can reference them:

```ruby
sales_data = {
  "January" => [100, 150, 200],
  "February" => [120, 180, 190],
  "March" => [140, 210, 220]
}

agent = DSPy::CodeAct.new

result = agent.forward(
  task: "Calculate the average sales for each month and report the best performer",
  context: "You have access to `sales_data`, a hash keyed by month with numeric arrays",
  data: { sales_data: sales_data }
)

puts result.final_answer
# => "March is the best performing month with an average of 190.0"
```

### Arbitrary Data Processing

```ruby
csv_content = <<~CSV
  name,email,department
  John Doe,john@gmail.com,Engineering
  Jane Smith,jane@company.com,Marketing
  Bob Johnson,bob@gmail.com,Sales
CSV

result = agent.forward(
  task: "Parse the CSV data and list gmail.com addresses",
  context: "CSV data is available in `csv_content`",
  data: { csv_content: csv_content }
)
```

## Safety Checklist

Executing arbitrary Ruby code is powerful but risky. Consider:

1. **Sandboxing & Timeouts** – wrap execution in `Timeout.timeout` and restrict accessible objects.
2. **Input Sanitization** – scrub user input to remove shell-outs and dangerous methods.
3. **Resource Monitoring** – track memory and CPU usage to abort runaway code.

```ruby
class SafeCodeAct < DSPy::CodeAct
  def execute_code(ruby_code)
    Timeout.timeout(5) { super }
  rescue Timeout::Error
    "Code execution timed out"
  end
end
```

## Example: Sales Analysis Pipeline

```ruby
class SalesAnalyzer < DSPy::Module
  def initialize
    @agent = DSPy::CodeAct.new
  end

  def analyze_trends(sales_data)
    result = @agent.forward(
      task: <<~TASK,
        Analyze the sales data to:
        1. Compute month-over-month growth
        2. Identify seasonal patterns
        3. Predict next month's sales with simple linear regression
      TASK
      context: "You have access to `sales_data` and standard Ruby libraries",
      data: { sales_data: sales_data }
    )

    {
      analysis: result.final_answer,
      code_steps: result.history.map(&:ruby_code),
      execution_time: result.metadata[:total_time]
    }
  end
end
```

## Debugging

Enable structured logging to observe each iteration:

```ruby
DSPy.configure do |config|
  config.logger = Dry.Logger(:dspy, formatter: :json) do |logger|
    logger.add_backend(level: :debug, stream: $stdout)
  end
end
```

Inspect `result.history` entry-by-entry to review generated code, observations, and errors.

## Limitations & Roadmap

- Basic sandboxing—do not run untrusted input without additional guards.
- No support for external gem loading during execution.
- Future roadmap targets hardened sandboxing, async execution, and richer explanations.

## Best Practices

1. Start with simple prompts before moving to complex tasks.
2. Provide precise context and structured data for better code generation.
3. Always validate outputs and enforce timeouts or resource caps.
4. Capture telemetry (Observability, Langfuse) for production usage.
