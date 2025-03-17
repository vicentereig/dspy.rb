# DSPy.rb

A port of the DSPy library to Ruby.

## Installation

```bash
gem install dspy
```

# Roadmap

Actually program LLMs instead of prompting them.

- Upcoming releases in evaluating and optimizing propmts

### First Release
First release targeting Composability with baseline prompts.

- [x] Modules: Signatures using JSON Schemas
- [x] Modules: Predict
- [ ] Modules: RAG
- [x] Modules: Chain Of Thought
- [ ] Modules: ReAct
- [x] Modules: Multiple Stage Pipelines
- [ ] Otel instrumentation
- [ ] Logging
- [ ] Streaming
- [ ] Thread safety

## Backlog

### Modules
Describing Inference Frameworks
- [ ] Responses are mostly hashes now, turn them into Dry Poros
- [ ] Modules: Adaptative Graph of Thoughts with Tools

### Features
- [x] Retries without sleeping

- [ ] Support for multiple LM Providers
- [ ] Support for reasoning providers

### Optimizers

Tune promptps and weights for your AI modules.

- [ ] Optimizing Prompts: RAG
- [ ] Optimizing Prompts: Chain Of Thought
- [ ] Optimizing Prompts: ReAct
- [ ] Optimizing Weights: Classification

## Design Notes

Here's where I sketch what I want the API to look like. Doesn't mean that it's currently implemented. Check the `spec/` for the current contracts.

### Configuring the global LM
- [ ] Needs to be thread safe
```ruby
DSPy.connfigure do |c|
    c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
end
```

### Configuring LMs per Signature

- [ ] Needs to be thread safe

```ruby
    class SentimentClassifier < DSPy::Signature
      description "Classify sentiment of a given sentence."
    
      input do
        required(:sentence).value(:string) #.description('The sentence whose sentiment you are analyzing')
      end
      output do
        required(:sentiment).value(included_in?: [:positive, :negative, :neutral])
        #.description('The allowed values to classify sentences')
        required(:confidence).value(:float) #.description('The confidence score for the classification')
      end
    end

    classify_with_openai = DSPy::Predict.new(SentimentClassifier) do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end

    classify_with_anthropic = DSPy::Predict.new(SentimentClassifier) do |c|
        c.lm = DSPy::LM.new('anthropic/claude-3-5-sonnet-20240620', api_key: ENV['ANTHROPIC_API_KEY'])
    end

    prediction_openai = classify_with_openai.call(sentence: "This book was super fun to read, though not the last chapter.")

    prediction_anthropic = classify_with_anthropic.call(sentence: "This book was super fun to read, though not the last chapter.")
```

### Configure
