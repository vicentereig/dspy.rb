---
layout: docs
title: "DSPy.rb Tutorial: Getting Started"
name: Getting Started
description: "Install DSPy.rb and build a typed LLM program with Ruby."
breadcrumb:
- name: Getting Started
  url: "/getting-started/"
date: 2025-06-28 00:00:00 +0000
last_modified_at: 2025-07-11 00:00:00 +0000
---
# Getting Started with DSPy.rb

Install DSPy.rb, configure a provider, and run a typed prediction in Ruby.

## What is DSPy.rb?

DSPy.rb is a Ruby framework for programming LLM systems. Signatures declare typed tasks. Modules choose execution strategies. Ruby composes modules into programs, while agents use tools where the model should choose the next action.

## The Programming Model

- **Signatures** declare typed inputs and outputs.
- **Modules** run a task with `Predict`, `ChainOfThought`, `ReAct`, or custom logic.
- **Ruby programs** compose modules with explicit control flow.
- **Agents and tools** delegate bounded action choices to the model.
- **Evaluation and optimizers** measure programs and compile better instructions or demonstrations from evidence.

## Quick Example

This signature declares a classifier's inputs and typed result:

```ruby
class EmailCategory < T::Enum
  enums do
    Technical = new('technical')
    Billing = new('billing')
    General = new('general')
  end
end

class EmailClassifier < DSPy::Signature
  input do
    const :subject, String
    const :body, String
  end
  
  output do
    const :category, EmailCategory
    const :confidence, Float
  end
end

# Use the classifier
classifier = DSPy::Predict.new(EmailClassifier)
result = classifier.call(
  subject: "Invoice for March 2024",
  body: "Please find attached your invoice..."
)

puts result.category    # => EmailCategory::Billing
puts result.confidence  # => 0.95
```

## What's Next?

<div class="grid gap-4 mt-8 sm:grid-cols-3 lg:grid-cols-3">
  <a href="{{ '/getting-started/installation/' | relative_url }}" class="relative rounded-lg border border-gray-200 bg-white p-6 shadow-sm hover:shadow-md">
    <div>
      <h3 class="text-base font-semibold leading-6 text-gray-900">Installation</h3>
      <p class="mt-2 text-sm text-gray-500">Install DSPy.rb and set up your development environment.</p>
    </div>
    <span class="absolute top-6 right-6 text-gray-400">
      <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </span>
  </a>
  
  <a href="{{ '/getting-started/quick-start/' | relative_url }}" class="relative rounded-lg border border-gray-200 bg-white p-6 shadow-sm hover:shadow-md">
    <div>
      <h3 class="text-base font-semibold leading-6 text-gray-900">Quick Start</h3>
      <p class="mt-2 text-sm text-gray-500">Build your first LLM application with DSPy.rb.</p>
    </div>
    <span class="absolute top-6 right-6 text-gray-400">
      <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </span>
  </a>
  
  <a href="{{ '/advanced/dspy-vs-langchain/' | relative_url }}" class="relative rounded-lg border border-gray-200 bg-white p-6 shadow-sm hover:shadow-md">
    <div>
      <h3 class="text-base font-semibold leading-6 text-gray-900">Framework Comparison</h3>
      <p class="mt-2 text-sm text-gray-500">Compare DSPy.rb vs LangChain Ruby with benchmarks and migration guide.</p>
    </div>
    <span class="absolute top-6 right-6 text-gray-400">
      <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </span>
  </a>
</div>
