# DSPy Programming in Ruby

I started DSPy.rb because I wanted DSPy's programming model in Rails applications. Rewriting those applications in Python made little sense. Keeping prompts as growing strings inside Ruby made less sense each time a model changed its response format.

The first versions were a port. DSPy.rb has since become an independent Ruby-native implementation: it carries over signatures, modules, agents, evaluation, and optimization, but it does not promise API compatibility with Stanford's Python project or official affiliation with it.

The useful idea is the same. Describe an LLM task as a program with inputs, outputs, control flow, examples, and a metric. Prompts still exist, but they become parameters of that program instead of the architecture around it.

## Start With A Contract

Consider sentiment classification. A direct API call often begins as a string:

```ruby
prompt = "Classify the sentiment of this text: #{text}"
response = client.chat(messages: [{ role: "user", content: prompt }])
```

Then the application needs a fixed label, a confidence score, parsing, and validation. Each requirement adds another instruction or another branch after the response.

In DSPy.rb, a signature declares the boundary:

```ruby
require "dspy"

class ClassifySentiment < DSPy::Signature
  description "Classify the sentiment of a given text"

  class Sentiment < T::Enum
    enums do
      Positive = new("positive")
      Negative = new("negative")
      Neutral = new("neutral")
    end
  end

  input do
    const :text, String
  end

  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    "openai/gpt-4o-mini",
    api_key: ENV.fetch("OPENAI_API_KEY")
  )
end

classifier = DSPy::Predict.new(ClassifySentiment)
result = classifier.call(text: "This Ruby gem is useful.")

puts result.sentiment
puts result.confidence
```

DSPy.rb turns the signature into provider instructions and a structured-output schema. It then coerces and validates the returned fields. A successful prediction exposes a `ClassifySentiment::Sentiment` and a `Float`; an invalid response raises before downstream code uses a malformed value.

The type boundary makes malformed output visible. Correctness still depends on the model, examples, and evaluation.

## Ruby Owns The Workflow

A signature describes one model interaction. A module combines interactions with ordinary Ruby control flow.

```ruby
class ExtractQuestion < DSPy::Signature
  description "Extract the question that must be answered"

  input do
    const :request, String
  end

  output do
    const :question, String
  end
end

class AnswerQuestion < DSPy::Signature
  description "Answer a question concisely"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

class QuestionAnswering < DSPy::Module
  def initialize
    @extract = DSPy::Predict.new(ExtractQuestion)
    @answer = DSPy::ChainOfThought.new(AnswerQuestion)
  end

  def forward(request:)
    extracted = @extract.call(request: request)
    @answer.call(question: extracted.question)
  end
end
```

Ruby decides the sequence. The same applies to branches, database reads, authorization checks, queues, and retries owned by the application or provider SDK. DSPy.rb does not need a special workflow language to express them.

`DSPy::ChainOfThought` adds a typed `reasoning` field before the declared output fields. It changes the predictor used for one step; it does not take control of the surrounding program.

## Give Agents Bounded Choices

Some tasks cannot be written as a fixed sequence because the next operation depends on what the model learns. `DSPy::ReAct` provides that loop: the model selects a tool, DSPy.rb executes it, and the observation feeds the next step.

Tools are Ruby objects with Sorbet signatures. DSPy.rb uses those signatures to produce the schemas shown to the model and to coerce arguments at the tool boundary.

```ruby
class Calculator < DSPy::Tools::Base
  extend T::Sig

  tool_name "calculator"
  tool_description "Calculate a percentage of a number"

  sig { params(percentage: Float, value: Float).returns(Float) }
  def call(percentage:, value:)
    value * percentage / 100.0
  end
end

class ResearchAnswer < DSPy::Signature
  description "Answer a question using the available tools"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

agent = DSPy::ReAct.new(
  ResearchAnswer,
  tools: [Calculator.new],
  max_iterations: 4
)

result = agent.call(question: "What is 15% of 250?")
puts result.answer
```

The application still owns the important limits: which tools exist, what each tool may access, how arguments are validated, and how many iterations the loop may run. A model can choose among the capabilities it receives. It cannot acquire a capability that the Ruby program did not provide.

For a choice that does not require tool execution, a union output is often enough:

```ruby
class SearchAction < T::Struct
  const :query, String
end

class CalculateAction < T::Struct
  const :expression, String
end

class AnswerAction < T::Struct
  const :answer, String
end

class ChooseAction < DSPy::Signature
  description "Choose the next action for a request"

  input do
    const :request, String
  end

  output do
    const :action, T.any(SearchAction, CalculateAction, AnswerAction)
  end
end
```

The returned `action` is one of the declared Sorbet structs. Ruby can dispatch on its class and keep execution policy outside the model call. The [union types article](https://oss.vicente.services/dspy.rb/blog/articles/union-types-agentic-workflows/) develops this pattern; the [ReAct tutorial](https://oss.vicente.services/dspy.rb/blog/articles/react-agent-tutorial/) covers a complete tool loop.

## Evaluate The Program You Built

A type-valid answer can still be wrong. Evaluation begins with examples and a metric that represents the behavior the application needs.

```ruby
examples = [
  DSPy::Example.new(
    signature_class: ClassifySentiment,
    input: { text: "I love this product." },
    expected: {
      sentiment: ClassifySentiment::Sentiment::Positive,
      confidence: 0.9
    }
  ),
  DSPy::Example.new(
    signature_class: ClassifySentiment,
    input: { text: "Worst purchase ever." },
    expected: {
      sentiment: ClassifySentiment::Sentiment::Negative,
      confidence: 0.9
    }
  )
]

exact_sentiment = lambda do |example, prediction|
  prediction.sentiment == example.expected_values[:sentiment]
end

evaluator = DSPy::Evals.new(classifier, metric: exact_sentiment)
evaluation = evaluator.evaluate(examples)

puts evaluation.score
puts evaluation.pass_rate
```

The metric above deliberately ignores confidence. A production metric might score calibration, penalize a costly false positive, or combine several component metrics. That decision belongs to the application; the optimizer will search for whatever the metric rewards.

Keep a held-out set. A better score on the examples used during optimization only proves that the search found those examples useful.

## Optimize Instructions And Examples

MIPROv2 searches over instructions and few-shot demonstrations for the predictors inside a program. It needs examples, a metric, and a budget. It returns the best candidate found during that search, not a universal improvement.

MIPROv2 ships in a separate gem:

```ruby
# Gemfile
gem "dspy"
gem "dspy-openai"
gem "dspy-miprov2"
```

```ruby
program = DSPy::Predict.new(ClassifySentiment)

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: exact_sentiment)
optimizer.configure do |config|
  config.auto_preset = DSPy::Teleprompt::AutoPreset::Light
end

result = optimizer.compile(
  program,
  trainset: examples,
  valset: examples
)

optimized_program = result.optimized_program
puts result.best_score_value
```

The repeated `examples` array keeps the snippet short; real work should separate training, validation, and held-out evaluation data. Search consumes model calls, and the result depends on the model, metric, examples, and budget. Measure the optimized program against data that did not select it.

My [medical predictor experiment](https://vicente.services/blog/2025/08/11/training-medical-llm-predictors-process,-costs,-and-optimization-with-dspy.rb/) is a useful warning. Tiny validation sets produced suspiciously perfect scores. Larger samples exposed the precision-recall tradeoff that the small run had hidden.

## Persist An Optimized Program

Optimization is expensive enough that the selected artifact should not live only in process memory. `DSPy::Storage::ProgramStorage` records the program together with its optimization result and metadata.

```ruby
storage = DSPy::Storage::ProgramStorage.new(
  storage_path: "./dspy_storage"
)

saved = storage.save_program(
  result.optimized_program,
  result,
  metadata: { dataset: "sentiment-v1" }
)

loaded = storage.load_program(saved.program_id)
loaded_program = loaded.program
```

The program and signature classes must be loaded during restoration, and the program class must support the storage deserialization contract. Evaluate `loaded_program` again before promoting it because loading only reconstructs the saved artifact.

## Where The Ruby Implementation Differs

DSPy.rb follows DSPy's programming model without translating its Python API line by line.

- Signatures use Sorbet types such as `T::Struct`, `T::Enum`, arrays, and unions.
- Provider adapters ship as separate gems, including `dspy-openai`, `dspy-anthropic`, and `dspy-gemini`.
- Ruby methods and modules express fixed control flow.
- `DSPy::Tools::Base` and `DSPy::Tools::Toolset` expose typed Ruby operations to agents.
- Evaluation, callbacks, events, and optional OpenTelemetry integrations fit Ruby application boundaries.
- Optimizers such as MIPROv2 and GEPA are DSPy.rb implementations with their own Ruby APIs and result objects.

Those differences are intentional, but they make mechanical translation from Python examples unreliable. Start from the DSPy concept, then check the Ruby API.

## Try One Complete Program

Add the core gem and one provider adapter:

```ruby
# Gemfile
gem "dspy"
gem "dspy-openai"
```

Run `bundle install`, set `OPENAI_API_KEY`, and save the following as `classify.rb`:

```ruby
require "dspy"

class Classify < DSPy::Signature
  description "Classify the sentiment of a sentence"

  class Sentiment < T::Enum
    enums do
      Positive = new("positive")
      Negative = new("negative")
      Neutral = new("neutral")
    end
  end

  input do
    const :sentence, String
  end

  output do
    const :sentiment, Sentiment
  end
end

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    "openai/gpt-4o-mini",
    api_key: ENV.fetch("OPENAI_API_KEY")
  )
end

classify = DSPy::Predict.new(Classify)
prediction = classify.call(sentence: "The upgrade was easier than expected.")

puts prediction.sentiment.serialize
```

Run it with `bundle exec ruby classify.rb`. From there, add examples and a metric before adding an optimizer. Add an agent only when the model genuinely needs to choose the next operation; keep deterministic sequencing in Ruby.

Documentation: [oss.vicente.services/dspy.rb](https://oss.vicente.services/dspy.rb)

DSPy.rb is MIT licensed. It is an independent Ruby-native implementation of DSPy's programming model and is not officially affiliated with the original DSPy project.
