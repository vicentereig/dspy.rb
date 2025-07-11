---
layout: blog
title: "Building Your First ReAct Agent in Ruby"
description: "Step-by-step guide to creating tool-using AI agents with DSPy.rb. Learn how to build agents that can reason about their actions and solve complex multi-step problems."
date: 2025-06-28
author: "Vicente Reig"
category: "Tutorial"
reading_time: "12 min read"
---

ReAct (Reasoning and Acting) agents are the workhorses of AI applications. They can use tools, reason about their actions, and solve complex multi-step problems. Today, I'll show you how to build one from scratch.

## What is a ReAct Agent?

ReAct agents follow a simple loop:
1. **Reason** about what to do next
2. **Act** by calling a tool
3. **Observe** the result
4. **Repeat** until the task is complete

Let's build a research assistant that can search the web, calculate statistics, and generate reports.

## Step 1: Define Your Tools

In DSPy.rb, tools are just Ruby objects that respond to `call`:

```ruby
# A simple web search tool
class WebSearchTool
  def call(query:)
    # In production, this would call a real search API
    case query.downcase
    when /ruby programming/
      [
        { title: "Ruby Programming Language", url: "https://ruby-lang.org", snippet: "A dynamic, open source programming language..." },
        { title: "Ruby on Rails", url: "https://rubyonrails.org", snippet: "Rails is a web application framework..." }
      ]
    when /climate change/
      [
        { title: "IPCC Report 2024", url: "https://ipcc.ch", snippet: "Latest findings on global climate..." },
        { title: "NASA Climate Data", url: "https://climate.nasa.gov", snippet: "Real-time climate monitoring..." }
      ]
    else
      [{ title: "No results found", url: "", snippet: "Try a different query" }]
    end
  end
end

# A calculator tool using Ruby's capabilities
class CalculatorTool
  def call(expression:)
    # Safe evaluation of mathematical expressions
    allowed_methods = %w[+ - * / ** % sin cos tan log sqrt]
    
    # Validate the expression contains only allowed operations
    tokens = expression.scan(/[a-zA-Z_]+/)
    unauthorized = tokens - allowed_methods
    
    if unauthorized.any?
      { error: "Unauthorized operations: #{unauthorized.join(', ')}" }
    else
      { result: eval(expression) }
    end
  rescue => e
    { error: e.message }
  end
end

# A data analysis tool
class DataAnalysisTool
  def call(data:, operation:)
    case operation
    when "mean"
      { result: data.sum.to_f / data.size }
    when "median"
      sorted = data.sort
      mid = sorted.size / 2
      { result: sorted.size.odd? ? sorted[mid] : (sorted[mid-1] + sorted[mid]) / 2.0 }
    when "std_dev"
      mean = data.sum.to_f / data.size
      variance = data.map { |x| (x - mean) ** 2 }.sum / data.size
      { result: Math.sqrt(variance) }
    else
      { error: "Unknown operation: #{operation}" }
    end
  end
end
```

## Step 2: Define Your Agent's Signature

The signature defines what your agent does:

```ruby
class ResearchAssistant < DSPy::Signature
  description "Research a topic and provide a comprehensive summary with statistics"
  
  input do
    const :topic, String, description: "The topic to research"
    const :depth, String, description: "How detailed the research should be (basic, detailed, comprehensive)"
  end
  
  output do
    const :summary, String, description: "A comprehensive summary of the findings"
    const :key_statistics, T::Array[String], description: "Important numbers and facts"
    const :sources, T::Array[String], description: "URLs of sources used"
    const :confidence, Float, description: "Confidence level in the findings (0-1)"
  end
end
```

## Step 3: Create the ReAct Agent

Now let's put it all together:

```ruby
require 'dspy'

# Configure DSPy
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# Initialize tools
tools = {
  search: WebSearchTool.new,
  calculate: CalculatorTool.new,
  analyze: DataAnalysisTool.new
}

# Create the agent
research_agent = DSPy::ReAct.new(ResearchAssistant, tools: tools, max_iters: 5)

# Use the agent
result = research_agent.forward(
  topic: "Ruby programming language adoption trends",
  depth: "detailed"
)

puts "Summary: #{result.summary}"
puts "Key Statistics: #{result.key_statistics.join(', ')}"
puts "Sources: #{result.sources.join(', ')}"
puts "Confidence: #{result.confidence}"
```

## Step 4: Understanding the Agent's Reasoning

One of the best features of ReAct agents is transparency. You can see exactly how they think:

```ruby
# Enable detailed instrumentation
DSPy.configure do |c|
  c.instrumentation.enabled = true
  c.instrumentation.logger.level = :info
end

result = research_agent.forward(
  topic: "Climate change impact on agriculture",
  depth: "comprehensive"
)

# Access the reasoning trace
result.react_iterations.each_with_index do |iteration, i|
  puts "\n=== Iteration #{i + 1} ==="
  puts "Thought: #{iteration.thought}"
  
  if iteration.tool_name
    puts "Action: #{iteration.tool_name}(#{iteration.tool_args})"
    puts "Observation: #{iteration.observation}"
  end
end
```

This might output:
```
=== Iteration 1 ===
Thought: I need to search for information about climate change impacts on agriculture
Action: search({"query": "climate change impact agriculture 2024"})
Observation: [{"title": "IPCC Report 2024", "snippet": "Agricultural yields expected to decline by 10-25% by 2050..."}]

=== Iteration 2 ===
Thought: I found that yields may decline 10-25%. Let me calculate the impact for different scenarios
Action: calculate({"expression": "1000000 * 0.25"})
Observation: {"result": 250000}

=== Iteration 3 ===
Thought: A 25% decline on 1 million tons of production means 250,000 tons lost. Let me search for adaptation strategies
Action: search({"query": "climate adaptation strategies agriculture"})
Observation: [{"title": "Sustainable Farming Practices", "snippet": "Drought-resistant crops, precision irrigation..."}]
```

## Advanced: Custom Tool Creation

Let's create a more sophisticated tool that integrates with Rails:

```ruby
# app/tools/database_query_tool.rb
class DatabaseQueryTool
  def initialize(allowed_models: [])
    @allowed_models = allowed_models
  end
  
  def call(model:, query:, limit: 10)
    # Security: Only allow whitelisted models
    unless @allowed_models.include?(model)
      return { error: "Model #{model} is not allowed" }
    end
    
    # Get the actual model class
    model_class = model.constantize
    
    # Parse the query into ActiveRecord methods
    case query
    when /count where (\w+) = ['"]([^'"]+)['"]/
      field, value = $1, $2
      { result: model_class.where(field => value).count }
      
    when /average (\w+) where (\w+) = ['"]([^'"]+)['"]/
      avg_field, where_field, value = $1, $2, $3
      { result: model_class.where(where_field => value).average(avg_field) }
      
    when /recent (\d+)/
      count = $1.to_i
      records = model_class.order(created_at: :desc).limit(count)
      { result: records.map { |r| r.attributes.slice('id', 'name', 'created_at') } }
      
    else
      { error: "Query pattern not recognized" }
    end
  rescue => e
    { error: e.message }
  end
end

# Use it in an agent
analytics_agent = DSPy::ReAct.new(
  DataAnalytics,
  tools: {
    db_query: DatabaseQueryTool.new(allowed_models: ['User', 'Order', 'Product'])
  }
)

result = analytics_agent.forward(
  question: "What's the average order value for customers who signed up in the last month?"
)
```

## Error Handling and Retries

ReAct agents can gracefully handle tool failures:

```ruby
class ResilientSearchTool
  def initialize
    @attempt = 0
  end
  
  def call(query:)
    @attempt += 1
    
    # Simulate API failures
    if @attempt == 1
      { error: "API rate limit exceeded" }
    else
      # Normal search results
      [{ title: "Result", snippet: "Found after retry" }]
    end
  end
end

# The agent will automatically retry with different strategies
agent = DSPy::ReAct.new(SearchTask, tools: { search: ResilientSearchTool.new })
```

## Production Best Practices

### 1. Tool Timeouts

```ruby
class TimeoutTool
  def call(**args)
    Timeout.timeout(5) do
      # Your tool logic here
    end
  rescue Timeout::Error
    { error: "Tool execution timed out" }
  end
end
```

### 2. Caching Results

```ruby
class CachedSearchTool
  def call(query:)
    Rails.cache.fetch(["search", query], expires_in: 1.hour) do
      # Expensive search operation
      perform_search(query)
    end
  end
end
```

### 3. Async Tool Execution

```ruby
class AsyncTool
  include Sidekiq::Worker
  
  def call(job_params:)
    # Queue the job and return immediately
    job_id = SecureRandom.uuid
    AsyncToolJob.perform_async(job_id, job_params)
    
    { status: "processing", job_id: job_id }
  end
end
```

### 4. Tool Authorization

```ruby
class AuthorizedTool
  def initialize(user)
    @user = user
  end
  
  def call(resource_id:)
    resource = Resource.find(resource_id)
    
    unless can?(@user, :read, resource)
      return { error: "Unauthorized" }
    end
    
    { data: resource.attributes }
  end
end

# Pass user-specific tools to the agent
agent = DSPy::ReAct.new(
  Task,
  tools: { 
    resource: AuthorizedTool.new(current_user) 
  }
)
```

## Debugging ReAct Agents

When things go wrong, here's how to debug:

```ruby
# 1. Enable verbose logging
DSPy.configure do |c|
  c.instrumentation.logger.level = :debug
end

# 2. Add tool instrumentation
class InstrumentedTool
  def call(**args)
    started_at = Time.now
    Rails.logger.info "Tool called with: #{args.inspect}"
    
    result = perform_operation(**args)
    
    duration = Time.now - started_at
    Rails.logger.info "Tool completed in #{duration}s: #{result.inspect}"
    
    result
  rescue => e
    Rails.logger.error "Tool failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { error: e.message }
  end
end

# 3. Inspect failed iterations
result = agent.forward(task: "Complex task")

if result.failure?
  result.react_iterations.each do |iter|
    if iter.error?
      puts "Failed at: #{iter.thought}"
      puts "Tool error: #{iter.observation[:error]}"
    end
  end
end
```

## ReAct vs CodeAct: A Practical Comparison

Here's the same task implemented with both approaches:

```ruby
# Task: Analyze sales data and create a report

# ReAct approach - using predefined tools
sales_tool = SalesDataTool.new
stats_tool = StatisticsTool.new
report_tool = ReportGeneratorTool.new

react_agent = DSPy::ReAct.new(
  SalesAnalysis,
  tools: { sales: sales_tool, stats: stats_tool, report: report_tool }
)

# CodeAct approach - writing custom analysis code
codeact_agent = DSPy::CodeAct.new

# ReAct is better here because:
# 1. Tools can access live database
# 2. Report generation follows company templates
# 3. More predictable and auditable
```

## Next Steps

Now that you've built your first ReAct agent, try these challenges:

1. **Multi-Agent System**: Create multiple agents that collaborate
2. **Tool Composition**: Build tools that use other tools
3. **State Management**: Add memory to your agents
4. **Custom Reasoning**: Override the reasoning prompts

Here's a starter for a multi-agent system:

```ruby
class ResearchAgent < DSPy::Module
  def initialize
    @web_agent = DSPy::ReAct.new(WebResearch, tools: { search: SearchTool.new })
    @analyst_agent = DSPy::ReAct.new(DataAnalysis, tools: { analyze: AnalysisTool.new })
    @writer_agent = DSPy::ReAct.new(ReportWriting, tools: { format: FormatterTool.new })
  end
  
  def forward(topic:)
    # Research phase
    research = @web_agent.forward(query: topic)
    
    # Analysis phase
    analysis = @analyst_agent.forward(data: research.findings)
    
    # Writing phase
    report = @writer_agent.forward(
      research: research.summary,
      analysis: analysis.insights
    )
    
    report
  end
end
```

## Conclusion

ReAct agents are powerful tools for building AI applications that can interact with the real world. They provide transparency, reliability, and flexibility that makes them perfect for production use.

The key is to start simple - build basic tools, test them thoroughly, and gradually increase complexity. Remember that the best AI applications combine the reasoning power of language models with the reliability of well-crafted tools.

---

*Ready to build your own ReAct agent? Check out the [complete documentation](../../../core-concepts/predictors/) or share your creations in our [GitHub discussions](https://github.com/vicentereig/dspy.rb/discussions).*
