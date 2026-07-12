---
layout: blog
title: "Let the Model Write Your Tools"
description: "Build a CodeAct research agent that chooses and executes Ruby code inside a bounded loop, with an explicit warning about process isolation."
date: 2025-11-27
author: "Vicente Reig"
category: "Tutorial"
reading_time: "4 min read"
image: /images/og/codeact-research-agent.png
---

[ReAct](/blog/articles/react-agent-tutorial/) lets a model choose among tools you wrote. [CodeAct](https://rubygems.org/gems/dspy-code_act) lets the model write the Ruby operation it wants to execute, inspect the result, and continue until it has an answer.

That flexibility changes the safety boundary. The current `dspy-code_act` implementation calls Ruby `eval` in the application process. The example below is suitable for controlled experiments with trusted input. It is not a sandbox for production or multi-tenant workloads.

## Define the task

The signature describes the research input and final output:

```ruby
class ResearchQuery < DSPy::Signature
  description "Research a topic by generating Ruby code to fetch and analyze web content."

  input do
    const :query, String, description: "The research question or topic to investigate"
    const :context, String, description: "Available libraries and execution constraints"
  end

  output do
    const :answer, String, description: "The answer supported by execution results"
  end
end
```

The signature fixes the task boundary. CodeAct still lets the model choose the code and whether another iteration is needed.

## Describe the execution context

The `context` field tells the model which libraries and endpoints are relevant:

```ruby
RESEARCH_CONTEXT = <<~CONTEXT
  You have access to these Ruby libraries:
  - Net::HTTP for HTTP requests
  - URI for parsing URLs
  - JSON for parsing JSON responses

  Useful APIs:
  - GitHub API: https://api.github.com/repos/{owner}/{repo}
  - Wikipedia API: https://en.wikipedia.org/api/rest_v1/page/summary/{title}
CONTEXT
```

This text guides code generation. It does not restrict what `eval` can access. A real execution policy must be enforced outside the generated program.

## Run the agent

Install the optional gem and configure an LM:

```ruby
gem 'dspy'
gem 'dspy-code_act'
```

```ruby
DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',
    api_key: ENV['OPENAI_API_KEY']
  )
end

agent = DSPy::CodeAct.new(ResearchQuery, max_iterations: 8)

result = agent.call(
  query: "How many stars does rails/rails have?",
  context: RESEARCH_CONTEXT
)

puts result.answer
```

CodeAct runs a Think-Code-Observe loop:

1. A predictor returns a thought and Ruby code.
2. CodeAct executes the code and captures stdout or the evaluated result.
3. A second predictor inspects the observation and chooses `continue` or `finish`.
4. The loop stops at `finish` or `max_iterations`.

The model owns the bounded action choice. The application owns the iteration limit, execution environment, network policy, credentials, and termination behavior around the loop.

## Inspect a run

A recorded run generated code equivalent to:

```ruby
uri = URI.parse('https://api.github.com/repos/rails/rails')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
response = http.get(uri.request_uri)
data = JSON.parse(response.body)
puts "rails/rails has #{data['stargazers_count']} stars."
```

The result includes typed history entries:

```ruby
result.history.each do |entry|
  puts "Step #{entry.step}"
  puts entry.thought
  puts entry.ruby_code
  puts entry.execution_result
  warn entry.error_message unless entry.error_message.empty?
end
```

The star count in an old trace will become stale. The useful evidence is the selected endpoint, generated code, captured observation, and decision to finish.

## Signatures specialize the loop

Changing the signature changes the task and result contract without changing CodeAct's execution loop:

```ruby
class AnalyzeCSV < DSPy::Signature
  description "Analyze CSV data and compute requested statistics."

  input do
    const :csv_data, String
    const :question, String
  end

  output do
    const :analysis, String
    const :numbers, T::Array[Float]
  end
end
```

The model still receives natural-language task and field descriptions. DSPy.rb turns those descriptions and the execution history into provider prompts; you do not maintain the multi-step prompt template yourself.

## Choose CodeAct or ReAct

Use CodeAct when the useful operation cannot be enumerated cleanly in advance, such as exploratory transformations over trusted data. Use ReAct when the allowed operations are known and each tool can expose a narrow typed interface.

| Property | ReAct | CodeAct |
|---|---|---|
| Model selects | A declared tool and typed arguments | Ruby code to execute |
| Authority boundary | Tool implementations | Execution environment |
| Best fit | Known APIs and controlled side effects | Open-ended computation in isolation |
| Primary risk | Overpowered tools | Arbitrary code execution |

Prefer ReAct when either approach can solve the task. A smaller authority surface is easier to test.

## Isolation is part of the harness

Timeouts and forbidden-string checks do not make `eval` safe. Generated Ruby can reach constants, loaded libraries, the filesystem, environment variables, network clients, and process APIs through many equivalent expressions.

For untrusted input, execute CodeAct in a disposable boundary with:

- A separate process or container.
- No inherited application secrets.
- An allowlisted network policy.
- Read-only or ephemeral storage.
- CPU, memory, wall-clock, and output limits.
- A narrow protocol for returning observations.

Ruby's `$SAFE` mechanism was removed in Ruby 3.0. Container or virtual-machine isolation adds overhead, but that overhead is part of running generated code honestly.

## Try the example

The full script is [`examples/codeact_research_agent.rb`](https://github.com/vicentereig/dspy.rb/blob/main/examples/codeact_research_agent.rb):

```bash
bundle exec ruby examples/codeact_research_agent.rb \
  "How many stars does rails/rails have?"
```

Run it interactively by omitting the question:

```bash
bundle exec ruby examples/codeact_research_agent.rb
```

Keep the demo local and controlled. Before connecting CodeAct to user input, move execution out of the application process and test the boundary as seriously as the agent loop.
