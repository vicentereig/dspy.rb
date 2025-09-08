---
layout: docs
name: Getting Started
description: Get up and running with DSPy.rb in minutes
breadcrumb:
- name: Getting Started
  url: "/getting-started/"
date: 2025-06-28 00:00:00 +0000
last_modified_at: 2025-07-11 00:00:00 +0000
---
# Getting Started with DSPy.rb

Welcome to DSPy.rb! This guide will help you get up and running with building reliable LLM applications in Ruby.

## What is DSPy.rb?

DSPy.rb is a Ruby framework for building predictable LLM applications using composable, type-safe modules. Instead of wrestling with prompt engineering, you define clear interfaces and let the framework handle the complexity.

## Key Features

- **Type-safe interfaces** using Sorbet for compile-time checking
- **Composable modules** for building complex reasoning chains
- **Systematic testing** with comprehensive test coverage
- **Production-ready** with Rails and Ruby ecosystem integration

## Quick Example

Here's a simple example of defining an LLM interface with DSPy.rb:

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

<div class="grid gap-4 mt-8 sm:grid-cols-2">
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
</div>