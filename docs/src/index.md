---
layout: home
title: DSPy.rb - Program LLMs, Don't Prompt Them
description: Write modular, testable Ruby code instead of tweaking prompts
date: 2025-06-28 00:00:00 +0000
last_modified_at: 2025-09-01 00:00:00 +0000
---
<div class="mx-auto max-w-2xl py-16 sm:py-24 lg:py-32">
  <div class="mb-6 flex justify-center sm:mb-8">
    <div class="relative rounded-full px-3 py-1 text-sm leading-6 text-gray-600 ring-1 ring-gray-900/10 hover:ring-gray-900/20">
      Version {{ site.config.dspy_version }} is now available. <a href="{{ site.config.dspy_release_url }}" class="font-semibold text-dspy-ruby hover:text-red-700"><span class="absolute inset-0" aria-hidden="true"></span>See what's new <span aria-hidden="true">&rarr;</span></a>
    </div>
  </div>
  <div class="text-center">
    <h1 class="text-4xl font-bold tracking-tight text-gray-900 sm:text-6xl">Build LLM apps like you build software</h1>
    <p class="mt-6 text-lg leading-8 text-gray-600">Tired of copy-pasting prompts and hoping they work? DSPy.rb lets you write modular, type-safe Ruby code that handles the LLM stuff for you. Test it, optimize it, ship it.</p>
    <div class="mt-10 flex items-center justify-center gap-x-6">
      <a href="{{ '/getting-started/' | relative_url }}" class="rounded-md bg-dspy-ruby px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-red-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-dspy-ruby">Get started</a>
      <a href="{{ '/llms-full.txt' | relative_url }}" target="_blank" class="inline-flex items-center py-2.5 text-sm font-semibold text-gray-900 hover:text-dspy-ruby">llms-full.txt <span aria-hidden="true" class="ml-2">→</span></a>
    </div>
  </div>
</div>

<div class="mx-auto max-w-5xl px-6 lg:px-8">
  <div class="mx-auto max-w-3xl">
    <p class="text-sm text-gray-500 mb-8">DSPy.rb is a Ruby port of Stanford's <a href="https://dspy.ai" class="underline">DSPy framework</a>, adapted to Ruby idioms and enhanced with production-ready features.</p>
    
    <h2 class="text-2xl font-bold text-gray-900 mb-6">Why programmatic prompts?</h2>
    <p class="text-lg text-gray-600 mb-12">Because prompt engineering is a nightmare. You tweak words, cross your fingers, and deploy. When it breaks in production (and it will), you're back to square one. DSPy.rb fixes this by letting you define what you want, not how to ask for it.</p>
    
    <h3 class="text-xl font-semibold text-gray-900 mb-6">See it in action</h3>
    
    <p class="text-gray-600 mb-6">Define what you need with type-safe Signatures:</p>
<div markdown="1">
```ruby
class Email < T::Struct
  const :subject, String
  const :from, String
  const :to, String
  const :body, String
end

class EmailCategory < T::Enum
  enums do
    Technical = new('technical')
    Billing = new('billing')
    General = new('general')
  end
end

class Priority < T::Enum
  enums do
    Low = new('low')
    Medium = new('medium')
    High = new('high')
  end
end

class ClassifyEmail < DSPy::Signature
  description "Classify customer support emails by analyzing content and urgency"
  
  input do
    const :email, Email, 
          description: "The email to classify with all headers and content"
  end
  
  output do
    const :category, EmailCategory,
          description: "Main topic: technical (API, bugs), billing (payment, pricing), or general"
    const :priority, Priority,
          description: "Urgency level based on keywords like 'production', 'ASAP', 'urgent'"
    const :summary, String,
          description: "One-line summary of the issue for support dashboard"
  end
end
```
</div>

<h3 class="text-xl font-semibold text-gray-900 mt-12 mb-6">Let the LLM show its work</h3>
    <p class="text-gray-600 mb-6">Use Chain of Thought for complex reasoning:</p>
<div markdown="1">
```ruby
classifier = DSPy::ChainOfThought.new(ClassifyEmail)

# Create a properly typed email object
email = Email.new(
  subject: "URGENT: API Key Not Working!!!",
  from: "john.doe@acmecorp.com",
  to: "support@yourcompany.com",
  body: "My API key stopped working after the update. I need this fixed ASAP for our production deployment!"
)

classification = classifier.call(email: email)  # Type-checked at runtime!
```
</div>

<h3 class="text-xl font-semibold text-gray-900 mt-12 mb-6">What you get back</h3>
    <p class="text-gray-600 mb-6">Proper Ruby objects, not strings:</p>
<div markdown="1">
```ruby
irb> classification.reasoning
=> "Let me analyze this email step by step:
1. The customer mentions an API key issue - this is technical
2. They mention it stopped working after an update - suggests a system change
3. They emphasize 'ASAP' and 'production deployment' - this is urgent
4. Production issues always warrant high priority"

irb> classification.category
=> #<EmailCategory::Technical:0x00007f8b2c0a1b80>

irb> classification.category.class
=> EmailCategory::Technical

irb> classification.category == EmailCategory::Technical  # Type-safe comparison
=> true

irb> classification.priority
=> #<Priority::High:0x00007f8b2c0a1c20>

irb> classification.priority.serialize  # Get the string value when needed
=> "high"

irb> classification.summary
=> "API key authentication failure post-update affecting production"

# Your IDE knows these are the ONLY valid values:
irb> EmailCategory.values
=> [#<EmailCategory::Technical>, #<EmailCategory::Billing>, #<EmailCategory::General>]

# Type errors caught at runtime (or by Sorbet static analysis):
irb> classification.category = "invalid"  # This would raise an error!
```
</div>
    
    <p class="text-lg text-gray-600 mt-12 mb-16">That's it. No prompt templates. No "You are a helpful assistant" nonsense. Just define what you want with real Ruby types and let DSPy handle the rest. Your category field can only ever be Technical, Billing, or General - not "technicall" or "TECHNICAL" or any other typo. The descriptions you add to fields become part of the prompt, guiding the LLM without you writing prompt engineering poetry. When you need to improve accuracy, you can optimize these programmatically with real data - not guesswork.</p>
  </div>
</div>

<div class="mx-auto max-w-7xl px-6 lg:px-8 py-16">
  <div class="mx-auto max-w-2xl lg:text-center mb-16">
    <h2 class="text-3xl font-bold tracking-tight text-gray-900 sm:text-4xl">Built for Ruby developers</h2>
    <p class="mt-4 text-lg text-gray-600">Everything you love about Ruby, now for LLM applications.</p>
  </div>
  
  <div class="mx-auto grid max-w-2xl grid-cols-1 gap-8 lg:mx-0 lg:max-w-none lg:grid-cols-3">
    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-ruby" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M5.5 17a4.5 4.5 0 01-1.44-8.765 4.5 4.5 0 018.302-3.046 3.5 3.5 0 014.504 4.272A4 4 0 0115 17H5.5zm3.75-2.75a.75.75 0 001.5 0V9.66l1.95 2.1a.75.75 0 101.1-1.02l-3.25-3.5a.75.75 0 00-1.1 0l-3.25 3.5a.75.75 0 101.1 1.02l1.95-2.1v4.59z" clip-rule="evenodd" />
        </svg>
        Type-safe from the start
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Catch errors before runtime. Your IDE knows what fields exist, what types they are, and what methods you can call. No more KeyError surprises in production.</p>
      </div>
    </div>
    
    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-ruby" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M15.312 11.424a5.5 5.5 0 01-9.201 2.466l-.312-.311h2.433a.75.75 0 000-1.5H3.989a.75.75 0 00-.75.75v4.242a.75.75 0 001.5 0v-2.43l.31.31a7 7 0 0011.712-3.138.75.75 0 00-1.449-.39zm1.23-3.723a.75.75 0 00.219-.53V2.929a.75.75 0 00-1.5 0V5.36l-.31-.31A7 7 0 003.239 8.188a.75.75 0 101.448.389A5.5 5.5 0 0113.89 6.11l.311.31h-2.432a.75.75 0 000 1.5h4.243a.75.75 0 00.53-.219z" clip-rule="evenodd" />
        </svg>
        Test like normal code
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Write RSpec tests for your LLM logic. Mock responses, test edge cases, measure accuracy. Your CI/CD pipeline just works - no special tooling needed.</p>
      </div>
    </div>
    
    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-ruby" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path d="M15.98 1.804a1 1 0 00-1.96 0l-.24 1.192a3.995 3.995 0 01-.784 1.785l-.874.874a3.995 3.995 0 01-1.785.784l-1.192.24a1 1 0 000 1.96l1.192.24a3.995 3.995 0 011.785.784l.874.874a3.995 3.995 0 01.784 1.785l.24 1.192a1 1 0 001.96 0l.24-1.192a3.995 3.995 0 01.784-1.785l.874-.874a3.995 3.995 0 011.785-.784l1.192-.24a1 1 0 000-1.96l-1.192-.24a3.995 3.995 0 01-1.785-.784l-.874-.874a3.995 3.995 0 01-.784-1.785l-.24-1.192zM4.5 5.5a1 1 0 00-1.97 0l-.12.593a1.995 1.995 0 01-.392.893l-.437.437a1.995 1.995 0 01-.893.392l-.593.12a1 1 0 000 1.97l.593.12a1.995 1.995 0 01.893.392l.437.437a1.995 1.995 0 01.392.893l.12.593a1 1 0 001.97 0l.12-.593a1.995 1.995 0 01.392-.893l.437-.437a1.995 1.995 0 01.893-.392l.593-.12a1 1 0 000-1.97l-.593-.12a1.995 1.995 0 01-.893-.392l-.437-.437a1.995 1.995 0 01-.392-.893l-.12-.593z" />
        </svg>
        Optimize with data
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Stop guessing what prompts work. Feed your examples to the optimizer and let it find the best instructions and few-shot examples automatically. Science, not art.</p>
      </div>
    </div>
    
    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-ruby" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M3 4.25A2.25 2.25 0 015.25 2h5.5A2.25 2.25 0 0113 4.25v2a.75.75 0 01-1.5 0v-2a.75.75 0 00-.75-.75h-5.5a.75.75 0 00-.75.75v11.5c0 .414.336.75.75.75h5.5a.75.75 0 00.75-.75v-2a.75.75 0 011.5 0v2A2.25 2.25 0 0110.75 18h-5.5A2.25 2.25 0 013 15.75V4.25z" clip-rule="evenodd" />
          <path fill-rule="evenodd" d="M6 10a.75.75 0 01.75-.75h9.546l-1.048-.943a.75.75 0 111.004-1.114l2.5 2.25a.75.75 0 010 1.114l-2.5 2.25a.75.75 0 11-1.004-1.114l1.048-.943H6.75A.75.75 0 016 10z" clip-rule="evenodd" />
        </svg>
        Compose and reuse
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Build complex workflows from simple modules. Chain them, compose them, swap them out. Your email classifier can feed into your priority ranker. Just like regular code.</p>
      </div>
    </div>
    
    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-ruby" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M10 1a4.5 4.5 0 00-4.5 4.5V9H5a2 2 0 00-2 2v6a2 2 0 002 2h10a2 2 0 002-2v-6a2 2 0 00-2-2h-.5V5.5A4.5 4.5 0 0010 1zm3 8V5.5a3 3 0 10-6 0V9h6z" clip-rule="evenodd" />
        </svg>
        Control your prompts
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Version control your LLM logic. Roll back when needed. A/B test different approaches. Know exactly what prompt is running in production. No more mystery meat.</p>
      </div>
    </div>
    
    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-ruby" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path d="M3.196 12.87l-.825.483a.75.75 0 000 1.294l7.25 4.25a.75.75 0 00.758 0l7.25-4.25a.75.75 0 000-1.294l-.825-.484-5.666 3.322a2.25 2.25 0 01-2.276 0L3.196 12.87z" />
          <path d="M3.196 8.87l-.825.483a.75.75 0 000 1.294l7.25 4.25a.75.75 0 00.758 0l7.25-4.25a.75.75 0 000-1.294l-.825-.484-5.666 3.322a2.25 2.25 0 01-2.276 0L3.196 8.87z" />
          <path d="M10.38 1.103a.75.75 0 00-.76 0l-7.25 4.25a.75.75 0 000 1.294l7.25 4.25a.75.75 0 00.76 0l7.25-4.25a.75.75 0 000-1.294l-7.25-4.25z" />
        </svg>
        Production ready
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Built-in observability, error handling, and performance monitoring. Track token usage, response times, and accuracy. Deploy with confidence.</p>
      </div>
    </div>
  </div>
</div>
