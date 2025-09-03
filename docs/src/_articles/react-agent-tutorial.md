---
layout: blog
title: "Building Your First ReAct Agent in Ruby"
description: "Step-by-step guide to creating tool-using AI agents with DSPy.rb. Learn how to build agents that can reason about their actions and solve complex multi-step problems."
date: 2025-06-28
author: "Vicente Reig"
category: "Tutorial"
reading_time: "12 min read"
canonical_url: "https://vicentereig.github.io/dspy.rb/blog/articles/react-agent-tutorial/"
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
class WebSearchTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'web_search'
  tool_description 'Searches the web for information on a given topic'

  # Define a type for search results
  class SearchResult < T::Struct
    const :title, String
    const :url, String
    const :snippet, String
  end

  sig { params(query: String).returns(T::Array[SearchResult]) }
  def call(query:)
    # In production, this would call a real search API
    case query.downcase
    when /ruby programming/
      [
        SearchResult.new(title: "Ruby Programming Language", url: "https://ruby-lang.org", snippet: "A dynamic, open source programming language..."),
        SearchResult.new(title: "Ruby on Rails", url: "https://rubyonrails.org", snippet: "Rails is a web application framework...")
      ]
    when /climate change/
      [
        SearchResult.new(title: "IPCC Report 2024", url: "https://ipcc.ch", snippet: "Latest findings on global climate..."),
        SearchResult.new(title: "NASA Climate Data", url: "https://climate.nasa.gov", snippet: "Real-time climate monitoring...")
      ]
    else
      [SearchResult.new(title: "No results found", url: "", snippet: "Try a different query")]
    end
  end
end

# A calculator tool using Ruby's capabilities
class CalculatorTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'calculator'
  tool_description 'Evaluates mathematical expressions safely'

  # Define result types
  class CalculationSuccess < T::Struct
    const :result, Numeric
  end

  class CalculationError < T::Struct
    const :error, String
  end

  sig { params(expression: String).returns(T.any(CalculationSuccess, CalculationError)) }
  def call(expression:)
    # Safe evaluation of mathematical expressions
    allowed_methods = %w[+ - * / ** % sin cos tan log sqrt]
    
    # Validate the expression contains only allowed operations
    tokens = expression.scan(/[a-zA-Z_]+/)
    unauthorized = tokens - allowed_methods
    
    if unauthorized.any?
      CalculationError.new(error: "Unauthorized operations: #{unauthorized.join(', ')}")
    else
      result = eval(expression)
      CalculationSuccess.new(result: result)
    end
  rescue => e
    CalculationError.new(error: e.message)
  end
end

# A data analysis tool
class DataAnalysisTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'data_analysis'
  tool_description 'Performs statistical analysis on numerical data'

  # Define result types
  class AnalysisSuccess < T::Struct
    const :result, Float
    const :operation, String
  end

  class AnalysisError < T::Struct
    const :error, String
  end

  sig { params(data: T::Array[Numeric], operation: String).returns(T.any(AnalysisSuccess, AnalysisError)) }
  def call(data:, operation:)
    return AnalysisError.new(error: "Data cannot be empty") if data.empty?

    case operation.downcase
    when "mean"
      result = data.sum.to_f / data.size
      AnalysisSuccess.new(result: result, operation: operation)
    when "median"
      sorted = data.sort
      mid = sorted.size / 2
      result = sorted.size.odd? ? sorted[mid].to_f : (sorted[mid-1] + sorted[mid]) / 2.0
      AnalysisSuccess.new(result: result, operation: operation)
    when "std_dev"
      mean = data.sum.to_f / data.size
      variance = data.map { |x| (x - mean) ** 2 }.sum / data.size
      result = Math.sqrt(variance)
      AnalysisSuccess.new(result: result, operation: operation)
    else
      AnalysisError.new(error: "Unknown operation: #{operation}. Supported: mean, median, std_dev")
    end
  end
end
```

## Step 2: Define Your Agent's Signature

The signature defines what your agent does:

```ruby
class ResearchDepth < T::Enum
  enums do
    Basic = new('basic')
    Detailed = new('detailed')
    Comprehensive = new('comprehensive')
  end
end

class ResearchAssistant < DSPy::Signature
  description "Research a topic and provide a comprehensive summary with statistics"
  
  input do
    const :topic, String, description: "The topic to research"
    const :depth, ResearchDepth, description: "How detailed the research should be"
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
tools = [
  WebSearchTool.new,
  CalculatorTool.new,
  DataAnalysisTool.new
]

# Create the agent with default max_iters of 10 (as per documentation)
research_agent = DSPy::ReAct.new(ResearchAssistant, tools: tools)

# Use the agent
result = research_agent.forward(
  topic: "Ruby programming language adoption trends",
  depth: ResearchDepth::Detailed
)

puts "Summary: #{result.summary}"
puts "Key Statistics: #{result.key_statistics.join(', ')}"
puts "Sources: #{result.sources.join(', ')}"
puts "Confidence: #{result.confidence}"
```

## Step 4: Understanding the Agent's Reasoning

One of the best features of ReAct agents is transparency. You can see exactly how they think:

```ruby
# Enable detailed observability
DSPy.configure do |c|
  c.logger = Dry.Logger(:dspy) do |logger|
    logger.add_backend(level: :info, stream: $stdout)
  end
end

result = research_agent.forward(
  topic: "Climate change impact on agriculture",
  depth: ResearchDepth::Comprehensive
)

# Access the reasoning trace
result.history.each do |iteration|
  puts "\n=== Step #{iteration[:step]} ==="
  puts "Thought: #{iteration[:thought]}"
  puts "Action: #{iteration[:action]}"
  puts "Action Input: #{iteration[:action_input]}"
end

puts "\nTotal iterations: #{result.iterations}"
```

This might output:
```
=== Step 1 ===
Thought: I need to search for information about climate change impacts on agriculture
Action: web_search
Action Input: {"query": "climate change impact agriculture 2024"}

=== Step 2 ===
Thought: I found that yields may decline 10-25%. Let me calculate the impact for different scenarios
Action: calculator
Action Input: {"expression": "1000000 * 0.25"}

=== Step 3 ===
Thought: A 25% decline on 1 million tons of production means 250,000 tons lost. Let me search for adaptation strategies
Action: web_search
Action Input: {"query": "climate adaptation strategies agriculture"}

=== Step 4 ===
Thought: Based on my research and calculations, I have comprehensive information to provide a summary
Action: finish
Action Input: {}

Total iterations: 4
```

## Advanced: Custom Tool Creation

Let's create a more sophisticated tool that integrates with Rails:

```ruby
# app/tools/database_query_tool.rb
class DatabaseQueryTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'database_query'
  tool_description 'Executes safe database queries on allowed models'

  # Define result types
  class QuerySuccess < T::Struct
    const :result, T.any(Integer, Float, T::Array[T::Hash[String, T.untyped]])
    const :query_type, String
  end

  class QueryError < T::Struct
    const :error, String
  end

  sig { params(allowed_models: T::Array[String]).void }
  def initialize(allowed_models: [])
    @allowed_models = allowed_models
    super()
  end
  
  sig { params(model: String, query: String, limit: Integer).returns(T.any(QuerySuccess, QueryError)) }
  def call(model:, query:, limit: 10)
    # Security: Only allow whitelisted models
    unless @allowed_models.include?(model)
      return QueryError.new(error: "Model #{model} is not allowed")
    end
    
    # Get the actual model class
    model_class = model.constantize
    
    # Parse the query into ActiveRecord methods
    case query
    when /count where (\w+) = ['"]([^'"]+)['"]/
      field, value = $1, $2
      result = model_class.where(field => value).count
      QuerySuccess.new(result: result, query_type: "count")
      
    when /average (\w+) where (\w+) = ['"]([^'"]+)['"]/
      avg_field, where_field, value = $1, $2, $3
      result = model_class.where(where_field => value).average(avg_field).to_f
      QuerySuccess.new(result: result, query_type: "average")
      
    when /recent (\d+)/
      count = $1.to_i
      records = model_class.order(created_at: :desc).limit(count)
      result = records.map { |r| r.attributes.slice('id', 'name', 'created_at') }
      QuerySuccess.new(result: result, query_type: "recent")
      
    else
      QueryError.new(error: "Query pattern not recognized")
    end
  rescue => e
    QueryError.new(error: e.message)
  end
end

# Use it in an agent
analytics_agent = DSPy::ReAct.new(
  DataAnalytics,
  tools: [
    DatabaseQueryTool.new(allowed_models: ['User', 'Order', 'Product'])
  ]
)

result = analytics_agent.forward(
  question: "What's the average order value for customers who signed up in the last month?"
)
```

## Error Handling and Retries

ReAct agents can gracefully handle tool failures:

```ruby
class ResilientSearchTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'resilient_search'
  tool_description 'Searches with automatic retry on failures'

  class SearchResult < T::Struct
    const :title, String
    const :snippet, String
  end

  class SearchError < T::Struct
    const :error, String
    const :retry_count, Integer
  end

  sig { void }
  def initialize
    @attempt = 0
    super()
  end
  
  sig { params(query: String).returns(T.any(T::Array[SearchResult], SearchError)) }
  def call(query:)
    @attempt += 1
    
    # Simulate API failures
    if @attempt == 1
      SearchError.new(error: "API rate limit exceeded", retry_count: @attempt)
    else
      # Normal search results
      [SearchResult.new(title: "Result", snippet: "Found after retry")]
    end
  end
end

# The agent will automatically retry with different strategies
agent = DSPy::ReAct.new(SearchTask, tools: [ResilientSearchTool.new])
```

## Production Best Practices

### 1. Tool Timeouts

```ruby
class TimeoutTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'timeout_operation'
  tool_description 'Performs operations with timeout protection'

  class OperationSuccess < T::Struct
    const :result, String
  end

  class TimeoutError < T::Struct
    const :error, String
  end

  sig { params(data: String).returns(T.any(OperationSuccess, TimeoutError)) }
  def call(data:)
    Timeout.timeout(5) do
      # Your tool logic here
      processed_data = "Processed: #{data}"
      OperationSuccess.new(result: processed_data)
    end
  rescue Timeout::Error
    TimeoutError.new(error: "Tool execution timed out")
  end
end
```

### 2. Caching Results

```ruby
class CachedSearchTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'cached_search'
  tool_description 'Performs web search with caching for performance'

  sig { params(query: String).returns(T::Array[T::Hash[String, String]]) }
  def call(query:)
    Rails.cache.fetch(["search", query], expires_in: 1.hour) do
      # Expensive search operation
      perform_search(query)
    end
  end

  private

  sig { params(query: String).returns(T::Array[T::Hash[String, String]]) }
  def perform_search(query)
    # Mock implementation - replace with actual search API
    [
      { "title" => "Result 1", "url" => "https://example.com/1", "snippet" => "First result for #{query}" },
      { "title" => "Result 2", "url" => "https://example.com/2", "snippet" => "Second result for #{query}" }
    ]
  end
end
```

### 3. Async Tool Execution

```ruby
class AsyncTool < DSPy::Tools::Base
  extend T::Sig
  include Sidekiq::Worker

  tool_name 'async_operation'
  tool_description 'Queues long-running operations for background processing'

  class JobQueued < T::Struct
    const :status, String
    const :job_id, String
  end
  
  sig { params(job_params: T::Hash[String, T.untyped]).returns(JobQueued) }
  def call(job_params:)
    # Queue the job and return immediately
    job_id = SecureRandom.uuid
    AsyncToolJob.perform_async(job_id, job_params)
    
    JobQueued.new(status: "processing", job_id: job_id)
  end
end
```

### 4. Tool Authorization

```ruby
class AuthorizedTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'authorized_resource'
  tool_description 'Accesses resources with user authorization checks'

  class ResourceSuccess < T::Struct
    const :data, T::Hash[String, T.untyped]
  end

  class AuthorizationError < T::Struct
    const :error, String
  end

  sig { params(user: T.untyped).void }
  def initialize(user)
    @user = user
    super()
  end
  
  sig { params(resource_id: String).returns(T.any(ResourceSuccess, AuthorizationError)) }
  def call(resource_id:)
    resource = Resource.find(resource_id)
    
    unless can?(@user, :read, resource)
      return AuthorizationError.new(error: "Unauthorized")
    end
    
    ResourceSuccess.new(data: resource.attributes)
  rescue ActiveRecord::RecordNotFound
    AuthorizationError.new(error: "Resource not found")
  end
end

# Pass user-specific tools to the agent
agent = DSPy::ReAct.new(
  Task,
  tools: [
    AuthorizedTool.new(current_user)
  ]
)
```

## Debugging ReAct Agents

When things go wrong, here's how to debug:

```ruby
# 1. Enable verbose logging
DSPy.configure do |c|
  c.logger.level = :debug
end

# 2. Add tool logging with Context spans
class InstrumentedTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'instrumented_operation'
  tool_description 'Performs operations with detailed logging'

  class OperationSuccess < T::Struct
    const :result, String
    const :duration, Float
  end

  class OperationError < T::Struct
    const :error, String
    const :duration, Float
  end

  sig { params(data: String).returns(T.any(OperationSuccess, OperationError)) }
  def call(data:)
    started_at = Time.now
    
    # Emit start event - automatically creates OpenTelemetry span
    DSPy.event('tool.started', tool_name: 'instrumented_operation', input: data)
    
    begin
      result = perform_operation(data)
      duration = Time.now - started_at
      
      # Success event - includes performance metrics  
      DSPy.event('tool.completed', {
        tool_name: 'instrumented_operation',
        duration_ms: (duration * 1000).round(2),
        result_size: result.length,
        status: 'success'
      })
      
      OperationSuccess.new(result: result, duration: duration)
    rescue => e
      duration = Time.now - started_at
      
      # Error event - includes failure details
      DSPy.event('tool.failed', {
        tool_name: 'instrumented_operation', 
        error: e.message,
        error_class: e.class.name,
        duration_ms: (duration * 1000).round(2),
        status: 'error'
      })
      
      OperationError.new(error: e.message, duration: duration)
    end
  end

  private

  sig { params(data: String).returns(String) }
  def perform_operation(data)
    "Processed: #{data}"
  end
end

# Track tool performance with event subscribers
class ToolPerformanceTracker < DSPy::Events::BaseSubscriber
  attr_reader :tool_stats
  
  def initialize
    super
    @tool_stats = Hash.new { |h, k| h[k] = { calls: 0, total_duration: 0, errors: 0 } }
    subscribe
  end
  
  def subscribe
    add_subscription('tool.*') do |event_name, attributes|
      tool_name = attributes[:tool_name]
      
      case event_name
      when 'tool.completed'
        @tool_stats[tool_name][:calls] += 1
        @tool_stats[tool_name][:total_duration] += attributes[:duration_ms]
      when 'tool.failed'
        @tool_stats[tool_name][:errors] += 1
      end
    end
  end
end

tracker = ToolPerformanceTracker.new
# Now automatically tracks all instrumented tools

# 3. Inspect failed iterations
result = agent.forward(question: "Complex question")

# Check for errors in the agent's reasoning trace
result.history.each do |iteration|
  puts "\n=== Step #{iteration[:step]} ==="
  puts "Thought: #{iteration[:thought]}"
  puts "Action: #{iteration[:action]}"
  puts "Action Input: #{iteration[:action_input]}"
  
  # Check if this was the last step that didn't reach 'finish'
  if iteration[:action] != 'finish'
    puts "Status: Tool execution step"
  else
    puts "Status: Agent completed successfully"
  end
end

puts "\nAgent used #{result.iterations} total iterations"
puts "Final answer: #{result.answer}"
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
  tools: [sales_tool, stats_tool, report_tool]
)

# CodeAct approach - generates and executes Ruby code dynamically
codeact_agent = DSPy::CodeAct.new(SalesAnalysisSignature)

# CodeAct generates Ruby code like:
# sales_data = fetch_sales_data(start_date: "2024-01-01")
# average_sale = sales_data.sum / sales_data.count
# puts "Average sale: #{average_sale}"

# When to use ReAct vs CodeAct:
# - ReAct: When you have predefined tools and structured workflows
# - CodeAct: When you need dynamic computation and data analysis
# - ReAct: Better for production systems with controlled environments  
# - CodeAct: Better for exploratory data analysis and rapid prototyping
```

## Next Steps

Now that you've built your first ReAct agent, try these challenges:

1. **Multi-Agent System**: Create multiple agents that collaborate
2. **Tool Composition**: Build tools that use other tools
3. **State Management**: Add memory to your agents
4. **Custom Reasoning**: Override the reasoning prompts

Here's a starter for a multi-agent system:

```ruby
class WebResearchSignature < DSPy::Signature
  description "Research a topic comprehensively using web search"
  
  input do
    const :query, String, description: "The research query"
  end
  
  output do
    const :findings, T::Array[String], description: "Key research findings"
    const :summary, String, description: "Research summary"
  end
end

class DataAnalysisSignature < DSPy::Signature
  description "Analyze research data and extract insights"
  
  input do
    const :data, T::Array[String], description: "Data to analyze"
  end
  
  output do
    const :insights, T::Array[String], description: "Key insights"
    const :metrics, T::Array[String], description: "Important metrics"
  end
end

class ReportWritingSignature < DSPy::Signature
  description "Write a comprehensive report from research and analysis"
  
  input do
    const :research, String, description: "Research summary"
    const :analysis, T::Array[String], description: "Analysis insights"
  end
  
  output do
    const :report, String, description: "Final formatted report"
    const :confidence, Float, description: "Confidence in report quality (0-1)"
  end
end

class ResearchAgent < DSPy::Module
  extend T::Sig

  sig { void }
  def initialize
    super
    
    search_tool = WebSearchTool.new
    analysis_tool = DataAnalysisTool.new
    formatter_tool = FormatterTool.new
    
    @web_agent = DSPy::ReAct.new(WebResearchSignature, tools: [search_tool])
    @analyst_agent = DSPy::ReAct.new(DataAnalysisSignature, tools: [analysis_tool])
    @writer_agent = DSPy::ReAct.new(ReportWritingSignature, tools: [formatter_tool])
  end
  
  sig { params(topic: String).returns(T.untyped) }
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

class FormatterTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'format_report'
  tool_description 'Formats research data into a professional report'

  class FormattedReport < T::Struct
    const :formatted_text, String
    const :word_count, Integer
  end

  sig { params(content: String, style: String).returns(FormattedReport) }
  def call(content:, style: "professional")
    formatted = "# Research Report\n\n#{content}\n\n---\nGenerated in #{style} style"
    word_count = content.split.length
    
    FormattedReport.new(formatted_text: formatted, word_count: word_count)
  end
end
```

## Conclusion

ReAct agents are powerful tools for building AI applications that can interact with the real world. They provide transparency, reliability, and flexibility that makes them perfect for production use.

The key is to start simple - build basic tools, test them thoroughly, and gradually increase complexity. Remember that the best AI applications combine the reasoning power of language models with the reliability of well-crafted tools.

---

*Ready to build your own ReAct agent? Check out the [complete documentation](../../../core-concepts/predictors/) or share your creations in our [GitHub discussions](https://github.com/vicentereig/dspy.rb/discussions).*
