# CodeAct: Dynamic Code Generation for DSPy.rb

`dspy-code_act` is for controlled experiments with trusted input. The current implementation evaluates model-generated Ruby inside the application process. It does not provide a sandbox, permission boundary, resource isolation, or safe handling of untrusted or multi-tenant input.

See the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for canonical package status and the execution-safety boundary.

## Prerequisites

- Ruby 3.3 or newer and Bundler
- `dspy`, one provider adapter, and `dspy-code_act`
- a provider key and model that can produce the required structured responses
- trusted input and a controlled execution environment
- outbound network access for the repository research example; generated Ruby calls a live HTTP API

## Install and Run the Example

```ruby
gem "dspy"
gem "dspy-openai"
gem "dspy-code_act"
```

In an application, run `bundle install` after adding those gems. From this repository, enable the optional package while installing the monorepo bundle, then run the example:

```bash
DSPY_WITH_CODE_ACT=1 bundle install
export OPENAI_API_KEY="your-key"
bundle exec ruby examples/codeact_research_agent.rb \
  "How many stars does rails/rails have?"
```

The script prints the final answer and records the generated code and observations in `result.history`. The answer can change with the live API; inspect the generated code and observation rather than treating an old count as a fixture.

## Define a CodeAct Task

CodeAct requires a signature and an iteration bound:

```ruby
class Calculate < DSPy::Signature
  input { const :question, String }
  output { const :answer, String }
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    "openai/gpt-4o-mini",
    api_key: ENV.fetch("OPENAI_API_KEY")
  )
end

agent = DSPy::CodeAct.new(Calculate, max_iterations: 4)
result = agent.call(question: "Return the first ten Fibonacci numbers")

puts result.answer
puts result.history.map(&:ruby_code)
```

The model chooses Ruby code, CodeAct evaluates it, and a second prediction chooses whether to continue or finish. The application owns the iteration limit and execution boundary.

## Choose CodeAct or ReAct

Prefer `DSPy::ReAct` when the allowed operations can be exposed as narrow typed tools. Use CodeAct only when open-ended computation is necessary and the execution environment can carry the larger authority boundary.

## Safety Checklist

Timeouts and forbidden-string checks do not make Ruby `eval` safe. Generated code can reach loaded constants, files, environment variables, network clients, and process APIs through many equivalent expressions.

Before accepting untrusted input, move execution outside the application process and provide:

- a disposable process, container, or virtual machine;
- no inherited application secrets;
- allowlisted network access;
- read-only or ephemeral storage;
- CPU, memory, wall-clock, and output limits; and
- a narrow protocol for returning observations.

The gem does not supply those controls. A provider error, invalid generated program, execution exception, or maximum-iteration result can stop or degrade a run; inspect `result.history` and handle those outcomes in the application.
