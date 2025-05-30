# DSPy.rb

A Ruby port of the [DSPy library](https://dspy.ai/), enabling a composable and pipeline-oriented approach to programming with Large Language Models (LLMs) in Ruby.

## Current State

DSPy.rb provides a foundation for composable LLM programming with the following implemented features:

- **Signatures**: Define input/output schemas for LLM interactions using JSON schemas
- **Predict**: Basic LLM completion with structured inputs and outputs
- **Chain of Thought**: Enhanced reasoning through step-by-step thinking
- **RAG (Retrieval-Augmented Generation)**: Enriched responses with context from retrieval
- **Multi-stage Pipelines**: Compose multiple LLM calls in a structured workflow

The library currently supports:
- OpenAI and Anthropic via [Ruby LLM](https://github.com/crmne/ruby_llm)
- JSON schema validation with [dry-schema](https://dry-rb.org/gems/dry-schema/)

## Installation

This is not even fresh  off the oven. I recommend you installing 
it straight from this repo, while I build the first release.

```ruby
gem 'dspy', github: 'vicentereig/dspy.rb'
```

## Usage Examples

### Basic Prediction

```ruby
# Define a signature for sentiment classification
class Classify < DSPy::Signature
  description "Classify sentiment of a given sentence."

  input do
    required(:sentence).value(:string).meta(description: 'The sentence to analyze')
  end

  output do
    required(:sentiment).value(included_in?: %w(positive negative neutral))
      .meta(description: 'The sentiment classification')
    required(:confidence).value(:float).meta(description: 'Confidence score')
  end
end

# Initialize the language model
class SentimentClassifierWithDescriptions < DSPy::Signature
  description "Classify sentiment of a given sentence."

  input do
    required(:sentence)
      .value(:string)
      .meta(description: 'The sentence whose sentiment you are analyzing')
  end

  output do
    required(:sentiment)
      .value(included_in?: [:positive, :negative, :neutral])
      .meta(description: 'The allowed values to classify sentences')

    required(:confidence).value(:float)
                         .meta(description:'The confidence score for the classification')
  end
end
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end
# Create the predictor and run inference
classify = DSPy::Predict.new(Classify)
result = classify.call(sentence: "This book was super fun to read, though not the last chapter.")
# => {:confidence=>0.85, :sentence=>"This book was super fun to read, though not the last chapter.", :sentiment=>"positive"}
```

### Chain of Thought Reasoning

```ruby
class AnswerPredictor < DSPy::Signature
  description "Provides a concise answer to the question"

  input do
    required(:question).value(:string)
  end
  
  output do
    required(:answer).value(:string)
  end
end

DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

qa_cot = DSPy::ChainOfThought.new(AnswerPredictor)
response = qa_cot.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
# Result includes reasoning and answer in the response
# {:question=>"...", :answer=>"1/36", :reasoning=>"There is only one way to get a sum of 2..."}
```

### RAG (Retrieval-Augmented Generation)

```ruby
class ContextualQA < DSPy::Signature
  description "Answers questions using relevant context"
  
  input do
    required(:context).value(Types::Array.of(:string))
    required(:question).filled(:string)
  end

  output do
    required(:response).filled(:string)
  end
end

DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# Set up retriever (example using ColBERT)
retriever = ColBERTv2.new(url: 'http://your-retriever-endpoint')
# Generate a contextual response
rag = DSPy::ChainOfThought.new(ContextualQA)
prediction = rag.call(question: question, context: retriever.call('your query').map(&:long_text))
```

### Multi-stage Pipeline

```ruby
# Create a pipeline for article drafting
class ArticleDrafter < DSPy::Module
  def initialize
    @build_outline = DSPy::ChainOfThought.new(Outline)
    @draft_section = DSPy::ChainOfThought.new(DraftSection)
  end

  def forward(topic)
    # First build the outline
    outline = @build_outline.call(topic: topic)
    
    # Then draft each section
    sections = []
    (outline[:section_subheadings] || {}).each do |heading, subheadings|
      section = @draft_section.call(
        topic: outline[:title],
        section_heading: "## #{heading}",
        section_subheadings: [subheadings].flatten.map { |sh| "### #{sh}" }
      )
      sections << section
    end

    DraftArticle.new(title: outline[:title], sections: sections)
  end
end

DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end
# Usage
drafter = ArticleDrafter.new
article = drafter.call("World Cup 2002")
```

### ReAct: Reasoning and Acting with Tools

The `DSPy::ReAct` module implements the ReAct (Reasoning and Acting) paradigm, allowing LLMs to synergize reasoning with tool usage to answer complex questions or complete tasks. The agent iteratively generates thoughts, chooses actions (either calling a tool or finishing), and observes the results to inform its next step.

**Core Components:**

*   **Signature**: Defines the overall task for the ReAct agent (e.g., answering a question). The output schema of this signature will be augmented by ReAct to include `history` (an array of structured thought/action/observation steps) and `iterations`.
*   **Tools**: Instances of classes inheriting from `DSPy::Tools::Tool`. Each tool has a `name`, `description` (used by the LLM to decide when to use the tool), and a `call` method that executes the tool's logic.
*   **LLM**: The ReAct agent internally uses an LLM (configured via `DSPy.configure`) to generate thoughts and decide on actions.

**Example 1: Simple Arithmetic with a Tool**

Let's say we want to answer "What is 5 plus 7?". We can provide the ReAct agent with a simple calculator tool.

```ruby
# Define a signature for the task
class MathQA < DSPy::Signature
  description "Answers mathematical questions."

  input do
    required(:question).value(:string).meta(description: 'The math question to solve.')
  end

  output do
    required(:answer).value(:string).meta(description: 'The numerical answer.')
  end
end

# Define a simple calculator tool
class CalculatorTool < DSPy::Tools::Tool
  def initialize
    super('calculator', 'Calculates the result of a simple arithmetic expression (e.g., "5 + 7"). Input must be a string representing the expression.')
  end

  def call(expression_string)
    # In a real scenario, you might use a more robust expression parser.
    # For this example, let's assume simple addition for "X + Y" format.
    if expression_string.match(/(\d+)\s*\+\s*(\d+)/)
      num1 = $1.to_i
      num2 = $2.to_i
      (num1 + num2).to_s
    else
      "Error: Could not parse expression. Use format 'number + number'."
    end
  rescue StandardError => e
    "Error: #{e.message}"
  end
end

# Configure DSPy (if not already done)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end

# Initialize ReAct agent with the signature and tool
calculator = CalculatorTool.new
react_agent = DSPy::ReAct.new(MathQA, tools: [calculator])

# Ask the question
question_text = "What is 5 plus 7?"
result = react_agent.forward(question: question_text)

puts "Question: #{question_text}"
puts "Answer: #{result.answer}"
puts "Iterations: #{result.iterations}"
puts "History:"
result.history.each do |entry|
  puts "  Step #{entry[:step]}:"
  puts "    Thought: #{entry[:thought]}"
  puts "    Action: #{entry[:action]}"
  puts "    Action Input: #{entry[:action_input]}"
  puts "    Observation: #{entry[:observation]}" if entry[:observation]
end
# Expected output (will vary based on LLM's reasoning):
# Question: What is 5 plus 7?
# Answer: 12
# Iterations: 2 (or similar)
# History:
#   Step 1:
#     Thought: I need to calculate 5 plus 7. I have a calculator tool that can do this.
#     Action: calculator
#     Action Input: 5 + 7
#     Observation: 12
#   Step 2:
#     Thought: The calculator returned 12, which is the answer to "5 plus 7?". I can now finish.
#     Action: finish
#     Action Input: 12
```

**Example 2: Web Search with Serper.dev**

For questions requiring up-to-date information or broader knowledge, the ReAct agent can use a web search tool. Here's an example using the `serper.dev` API.

*Note: You'll need a Serper API key, which you can set in the `SERPER_API_KEY` environment variable.* 

```ruby
require 'net/http'
require 'json'
require 'uri'

# Define a signature for web-based QA
class WebQuestionAnswer < DSPy::Signature
  description "Answers questions that may require web searches."

  input do
    required(:question).value(:string).meta(description: 'The question to answer, potentially requiring a web search.')
  end

  output do
    required(:answer).value(:string).meta(description: 'The final answer to the question.')
  end
end

# Define the Serper Search Tool
class SerperSearchTool < DSPy::Tools::Tool
  def initialize
    super('web_search', 'Searches the web for a given query and returns the first organic result snippet. Useful for finding current information or answers to general knowledge questions.')
  end

  def call(query)
    api_key = ENV['SERPER_API_KEY']
    unless api_key
      return "Error: SERPER_API_KEY environment variable not set."
    end

    uri = URI.parse("https://google.serper.dev/search")
    request = Net::HTTP::Post.new(uri)
    request['X-API-KEY'] = api_key
    request['Content-Type'] = 'application/json'
    request.body = JSON.dump({ q: query })

    begin
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        results = JSON.parse(response.body)
        first_organic_result = results['organic']&.first
        if first_organic_result && first_organic_result['snippet']
          return "Source: #{first_organic_result['link']}\nSnippet: #{first_organic_result['snippet']}"
        elsif first_organic_result && first_organic_result['title']
          return "Source: #{first_organic_result['link']}\nTitle: #{first_organic_result['title']}"
        else
          return "No relevant snippet found in the first result."
        end
      else
        return "Error: Serper API request failed with status #{response.code} - #{response.body}"
      end
    rescue StandardError => e
      return "Error performing web search: #{e.message}"
    end
  end
end

# Configure DSPy (if not already done)
DSPy.configure do |c|
  c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY']) # Ensure your LM is configured
end

# Initialize ReAct agent with the signature and search tool
search_tool = SerperSearchTool.new
web_qa_agent = DSPy::ReAct.new(WebQuestionAnswer, tools: [search_tool])

# Ask a question requiring web search
question_text = "What is the latest news about the Mars rover Perseverance?"
result = web_qa_agent.forward(question: question_text)

puts "Question: #{question_text}"
puts "Answer: #{result.answer}"
puts "Iterations: #{result.iterations}"
puts "History (summary):"
result.history.each_with_index do |entry, index|
  puts "  Step #{entry[:step]}: Action: #{entry[:action]}, Input: #{entry[:action_input]&.slice(0, 50)}..."
  # For brevity, not printing full thought/observation here.
end
# The answer and history will depend on the LLM's reasoning and live search results.

## Roadmap

### First Release
- [x] Signatures and Predict module
- [x] RAG examples
- [x] Multi-Stage Pipelines
- [x] Validate inputs and outputs with JSON Schema
- [x] thread-safe global config
- [x] Convert responses from hashes to Dry Poros (currently tons of footguns with hashes :fire:)
- [ ] Cover unhappy paths: validation errors 
- [x] Implement ReAct module for reasoning and acting
- [ ] Add OpenTelemetry instrumentation
- [ ] Improve logging
- [ ] Add streaming support (?)
- [x] Ensure thread safety
- [ ] Comprehensive initial documentation, LLM friendly.

#### Backburner

- [ ] Support for multiple LM providers (Anthropic, etc.)
- [ ] Support for reasoning providers
- [ ] Adaptive Graph of Thoughts with Tools

### Optimizers

- [ ] Optimizing prompts: RAG
- [ ] Optimizing prompts: Chain of Thought
- [ ] Optimizing prompts: ReAct
- [ ] Optimizing weights: Classification

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE.txt file for details.
