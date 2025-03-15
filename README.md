# DSPy.rb

A port of the DSPy library to Ruby.

## Installation

```bash
gem install dspy
```

## Roadmap

Actually program LLMs instead of prompting them.

### Modules and Inference Frameworks
Describing AI behabviours

- [x] Modules: Predict 
- [ ] Modules: RAG
- [ ] Modules: Chain Of Thought
- [ ] Modules: ReAct
- [ ] Modules: Multiple Stage Pipelines
- [ ] Modules: Adaptative Graph of Thoughts
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
    class Classify < DSPy::Signature
          description "Classify sentiment of a given sentence."
          
          input :sentence, String
          output :sentiment, [:positive, :negative, :neutral]
          output :confidence, Float
    end

    classify_with_openai = DSPy::Predict.new(Classify) do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end

    classify_with_anthropic = DSPy::Predict.new(Classify) do |c|
        c.lm = DSPy::LM.new('anthropic/claude-3-5-sonnet-20240620', api_key: ENV['ANTHROPIC_API_KEY'])
    end

    prediction_openai = classify_with_openai.call(sentence: "This book was super fun to read, though not the last chapter.")

    prediction_anthropic = classify_with_anthropic.call(sentence: "This book was super fun to read, though not the last chapter.")
```

### Configure
