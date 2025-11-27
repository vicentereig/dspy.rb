---
layout: blog
title: "Let the Model Write Your Tools"
description: "Building a research agent with CodeAct where the LLM generates Ruby code on the fly"
date: 2025-11-27
author: "Vicente Reig"
category: "Tutorial"
reading_time: "4 min read"
image: /images/og/codeact-research-agent.png
---

[CodeAct](https://rubygems.org/gems/dspy-code_act) is a [DSPy.rb](https://github.com/vicentereig/dspy.rb) module that lets an LLM write and execute Ruby code to solve tasks. Instead of defining tools upfront, the agent generates code on the fly. This post walks through a minimal research agent that fetches data from web APIs.

## The Signature

First, define what the agent does:

```ruby
class ResearchQuery < DSPy::Signature
  description "Research a topic by generating Ruby code to fetch and analyze web content."

  input do
    const :query, String, description: "The research question or topic to investigate"
    const :context, String, description: "Available libraries and guidelines"
  end

  output do
    const :answer, String, description: "The answer based on research findings"
  end
end
```

Nothing special here - just a standard signature with a query in and an answer out.

## The Context

The `context` input is just a string describing what the agent can use. Here we explain that `Net::HTTP`, `URI`, and `JSON` are available, and list some useful API endpoints:

```ruby
RESEARCH_CONTEXT = <<~CONTEXT
  You have access to these Ruby libraries:
  - Net::HTTP - for HTTP requests
  - URI - for parsing URLs
  - JSON - for parsing JSON responses

  Useful APIs:
  - GitHub API: https://api.github.com/repos/{owner}/{repo}
  - Wikipedia API: https://en.wikipedia.org/api/rest_v1/page/summary/{title}
CONTEXT
```

## Running the Agent

Configure DSPy with your LLM, then create a CodeAct instance:

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

agent = DSPy::CodeAct.new(ResearchQuery, max_iterations: 8)
```

Call the agent with your query:

```ruby
result = agent.call(
  query: "How many stars does rails/rails have?",
  context: RESEARCH_CONTEXT
)

puts result.answer
```

## What Happens

The agent loops through three phases: **Think** (reason about the approach), **Code** (generate and execute Ruby), and **Observe** (decide if done or continue). Here's a real run:

```
🔬 Research Query: How many stars does rails/rails have?

📋 Final Answer:
The repository 'rails/rails' has 57915 stars.

🔍 Execution History (1 iterations):

[Step 1]
💭 Thought: To fetch the number of stars for the 'rails/rails' repository
   on GitHub, I will use the GitHub API endpoint for repository information.

💻 Code:
   uri = URI.parse('https://api.github.com/repos/rails/rails')
   http = Net::HTTP.new(uri.host, uri.port)
   http.use_ssl = true
   response = http.get(uri.request_uri)
   data = JSON.parse(response.body)
   stars = data['stargazers_count']
   puts "rails/rails has #{stars} stars."

✅ Result: rails/rails has 57915 stars.
```

The agent:
1. Reasoned about which API to use
2. Generated valid Ruby code with proper HTTPS handling
3. Executed the code and captured the output
4. Decided the task was complete after one iteration

## Specializing via Signatures

The signature defines what your agent does. Change the signature, get a different agent:

```ruby
# A data analyst
class AnalyzeCSV < DSPy::Signature
  description "Analyze CSV data and compute statistics"

  input do
    const :csv_data, String
    const :question, String
  end

  output do
    const :analysis, String
    const :numbers, T::Array[Float]
  end
end

# A code explainer
class ExplainCode < DSPy::Signature
  description "Execute code snippets to understand their behavior"

  input do
    const :code, String
    const :language, String
  end

  output do
    const :explanation, String
    const :output_example, String
  end
end
```

Each signature produces a specialized agent. The `description` guides the LLM's approach, input fields define what data it receives, and output fields shape what it returns. CodeAct handles the execution loop - you just define the interface.

## When to Use This

CodeAct works well when you need flexible data fetching or transformation. The agent can combine APIs, parse responses, and compute derived values - all without you writing tool definitions.

Use [**ReAct**](/blog/articles/react-agent-tutorial/) instead when you have well-defined tools with clear interfaces, or need stricter control over what the agent can do.

The tradeoff with CodeAct is safety: it uses `eval` to run generated code. Fine for experimentation, but add sandboxing before using with untrusted input.

## Sandboxing Options

Ruby has no built-in safe sandbox (`$SAFE` was removed in Ruby 3.0). For production use with untrusted input, consider these alternatives:

| Approach | Gem | How it works | Overhead |
|----------|-----|--------------|----------|
| Docker containers | [trusted-sandbox](https://github.com/vaharoni/trusted-sandbox) | Runs code in isolated containers with resource limits | ~100ms+ |
| V8 engine | [ruby_box](https://github.com/alecdotninja/ruby_box) | Compiles Ruby to JS via Opal, executes in V8 | Fast, but limited Ruby compatibility |
| Process isolation | [safe_ruby](https://github.com/ukutaht/safe_ruby) | Forks process with whitelisted methods | Moderate |
| WebAssembly | [wasmer-ruby](https://github.com/wasmerio/wasmer-ruby) | Memory-safe WASM sandbox | Complex setup |

For controlled experimentation, a lightweight approach with timeouts and pattern blocking:

```ruby
class SaferCodeAct < DSPy::CodeAct
  FORBIDDEN = [/`.*`/, /system\s*\(/, /exec\s*\(/, /File\.(delete|write)/]

  def execute_ruby_code_safely(ruby_code)
    return [nil, "Forbidden pattern"] if FORBIDDEN.any? { |p| ruby_code.match?(p) }

    Timeout.timeout(5) { super }
  rescue Timeout::Error
    [nil, "Timed out"]
  end
end
```

This isn't a real sandbox - it's just guardrails. For untrusted input, use Docker or WASM.

## Try It

The full example is at `examples/codeact_research_agent.rb`:

```
$ bundle exec ruby examples/codeact_research_agent.rb "How many stars does rails/rails have?"

🔬 Research Query: How many stars does rails/rails have?
============================================================

📋 Final Answer:
------------------------------------------------------------
The repository 'rails/rails' has 57915 stars.

🔍 Execution History (1 iterations):
------------------------------------------------------------

[Step 1]
💭 Thought: To fetch the number of stars for the 'rails/rails' repository on GitHub,
   I will use the GitHub API endpoint for repository information.
💻 Code:
   uri = URI.parse('https://api.github.com/repos/rails/rails')
   http = Net::HTTP.new(uri.host, uri.port)
   http.use_ssl = true
   response = http.get(uri.request_uri)
   data = JSON.parse(response.body)
   stars = data['stargazers_count']
   puts "rails/rails has #{stars} stars."
✅ Result: rails/rails has 57915 stars.
```

Or run it interactively:

```bash
bundle exec ruby examples/codeact_research_agent.rb
```
