---
layout: home
title: "DSPy.rb | Typed AI Agents in Ruby"
description: "Build typed agents in Ruby with Sorbet contracts, model tools, evaluation, and prompt optimization."
date: 2025-06-28 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
<div class="mx-auto max-w-2xl py-8 sm:py-16 lg:py-32">
  <div class="mb-6 flex justify-center sm:mb-8">
    <div class="relative rounded-full px-3 py-1 text-sm leading-6 text-gray-600 ring-1 ring-gray-900/10 hover:ring-gray-900/20">
      Version {{ site.config.dspy_version }} is now available. <a href="{{ site.config.dspy_release_url }}" class="font-semibold text-dspy-coral hover:text-[#e05d3d]"><span class="absolute inset-0" aria-hidden="true"></span>See what's new <span aria-hidden="true">&rarr;</span></a>
    </div>
  </div>
  <div class="text-center">
    <p class="text-sm font-medium text-dspy-coral mb-4">Ruby-native agents powered by <a href="https://dspy.ai" rel="noopener noreferrer" class="underline hover:text-[#e05d3d]">DSPy's programming model</a></p>
    <h1 class="text-4xl font-bold font-serif tracking-tight text-gray-900 sm:text-6xl">Build typed AI agents in Ruby</h1>
    <p class="mt-6 text-lg leading-8 text-gray-600">Define task contracts with Sorbet. Give models typed tools. Keep state, limits, errors, and side effects in Ruby.</p>
    <div class="mt-6 flex flex-wrap justify-center gap-x-6 gap-y-2 text-sm text-gray-500">
      <span class="flex items-center gap-x-1.5"><svg class="h-4 w-4 text-green-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" /></svg>Typed agent contracts with Sorbet</span>
      <span class="flex items-center gap-x-1.5"><svg class="h-4 w-4 text-green-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" /></svg>Evaluation and prompt optimization</span>
      <span class="flex items-center gap-x-1.5"><svg class="h-4 w-4 text-green-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" /></svg>OpenAI, Anthropic, Gemini, Ollama</span>
    </div>
    <div class="mt-10 flex items-center justify-center gap-x-6">
      <a href="{{ '/getting-started/' | relative_url }}" class="rounded-md bg-dspy-coral px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-[#e05d3d] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-dspy-coral">Get started</a>
      <a href="{{ '/core-concepts/' | relative_url }}" class="inline-flex items-center py-2.5 text-sm font-semibold text-gray-900 hover:text-dspy-link">Learn the concepts <span aria-hidden="true" class="ml-2">&rarr;</span></a>
    </div>
  </div>
</div>

<div class="mx-auto max-w-5xl px-6 lg:px-8">
  <div class="mx-auto max-w-3xl">

    <h2 class="text-2xl font-bold font-serif text-gray-900 mb-6">Build a tool-using agent</h2>
    <p class="text-lg text-gray-600 mb-12">An agent is a model using tools in a bounded loop to reach a goal. A signature defines the task and result. Ruby implements the tools and owns permissions, errors, side effects, and iteration limits.</p>

    <h3 class="text-xl font-semibold font-serif text-gray-900 mb-6">Define the contract and tool</h3>

    <p class="text-gray-600 mb-6">The signature types the agent's boundary. The tool exposes one narrow Ruby capability:</p>
<div markdown="1">
```ruby
class AnswerWeather < DSPy::Signature
  description "Answer weather questions with the available tools"

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

class WeatherTool < DSPy::Tools::Base
  tool_name "weather"
  tool_description "Get weather for a location"

  sig { params(location: String).returns(String) }
  def call(location:)
    "72°F and sunny in #{location}"
  end
end
```
</div>

<h3 class="text-xl font-semibold font-serif text-gray-900 mt-12 mb-6">Run a bounded tool loop</h3>
    <p class="text-gray-600 mb-6"><code>ReAct</code> lets the model call the weather tool, observe its result, and finish with a typed answer:</p>
<div markdown="1">
```ruby
agent = DSPy::ReAct.new(
  AnswerWeather,
  tools: [WeatherTool.new],
  max_iterations: 3
)

result = agent.call(question: "What is the weather in Valencia?")
puts result.answer
```
</div>

<h3 class="text-xl font-semibold font-serif text-gray-900 mt-12 mb-6">Inspect what happened</h3>
    <p class="text-gray-600 mb-6">The answer follows the declared type. The history records tool choices and results:</p>
<div markdown="1">
```ruby
result.answer.class
# => String

result.history.each do |step|
  puts [step[:action], step[:tool_input], step[:observation]].inspect
end
```
</div>

    <p class="text-lg text-gray-600 mt-12 mb-16">The model chooses whether to call a tool or finish; Ruby executes each tool and enforces the loop limit. Evaluate complete runs with examples and metrics, then use an optimizer to search for better instructions and demonstrations.</p>
  </div>
</div>

<div class="mx-auto max-w-7xl px-6 lg:px-8 py-16">
  <div class="mx-auto max-w-2xl lg:text-center mb-16">
    <h2 class="text-3xl font-bold font-serif tracking-tight text-gray-900 sm:text-4xl">Built for Ruby developers</h2>
    <p class="mt-4 text-lg text-gray-600">Ruby types and control flow for agents and model-backed programs.</p>
  </div>

  <div class="mx-auto grid max-w-2xl grid-cols-1 gap-8 lg:mx-0 lg:max-w-none lg:grid-cols-3">
    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-coral" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M5.5 17a4.5 4.5 0 01-1.44-8.765 4.5 4.5 0 018.302-3.046 3.5 3.5 0 014.504 4.272A4 4 0 0115 17H5.5zm3.75-2.75a.75.75 0 001.5 0V9.66l1.95 2.1a.75.75 0 101.1-1.02l-3.25-3.5a.75.75 0 00-1.1 0l-3.25 3.5a.75.75 0 101.1 1.02l1.95-2.1v4.59z" clip-rule="evenodd" />
        </svg>
        Type-safe from the start
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Signatures validate inputs and convert provider responses into declared Ruby types. Invalid outputs fail before application code uses them.</p>
      </div>
    </div>

    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-coral" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M15.312 11.424a5.5 5.5 0 01-9.201 2.466l-.312-.311h2.433a.75.75 0 000-1.5H3.989a.75.75 0 00-.75.75v4.242a.75.75 0 001.5 0v-2.43l.31.31a7 7 0 0011.712-3.138.75.75 0 00-1.449-.39zm1.23-3.723a.75.75 0 00.219-.53V2.929a.75.75 0 00-1.5 0V5.36l-.31-.31A7 7 0 003.239 8.188a.75.75 0 101.448.389A5.5 5.5 0 0113.89 6.11l.311.31h-2.432a.75.75 0 000 1.5h4.243a.75.75 0 00.53-.219z" clip-rule="evenodd" />
        </svg>
        Test like normal code
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Use RSpec for deterministic behavior and evaluation sets for model behavior. Tests and metrics answer different questions.</p>
      </div>
    </div>

    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-coral" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path d="M15.98 1.804a1 1 0 00-1.96 0l-.24 1.192a3.995 3.995 0 01-.784 1.785l-.874.874a3.995 3.995 0 01-1.785.784l-1.192.24a1 1 0 000 1.96l1.192.24a3.995 3.995 0 011.785.784l.874.874a3.995 3.995 0 01.784 1.785l.24 1.192a1 1 0 001.96 0l.24-1.192a3.995 3.995 0 01.784-1.785l.874-.874a3.995 3.995 0 011.785-.784l1.192-.24a1 1 0 000-1.96l-1.192-.24a3.995 3.995 0 01-1.785-.784l-.874-.874a3.995 3.995 0 01-.784-1.785l-.24-1.192zM4.5 5.5a1 1 0 00-1.97 0l-.12.593a1.995 1.995 0 01-.392.893l-.437.437a1.995 1.995 0 01-.893.392l-.593.12a1 1 0 000 1.97l.593.12a1.995 1.995 0 01.893.392l.437.437a1.995 1.995 0 01.392.893l.12.593a1 1 0 001.97 0l.12-.593a1.995 1.995 0 01.392-.893l.437-.437a1.995 1.995 0 01.893-.392l.593-.12a1 1 0 000-1.97l-.593-.12a1.995 1.995 0 01-.893-.392l-.437-.437a1.995 1.995 0 01-.392-.893l-.12-.593z" />
        </svg>
        Optimize with data
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Give an optimizer examples and a metric. It can search instructions and demonstrations, then persist the resulting prompt artifacts.</p>
      </div>
    </div>

    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-coral" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M3 4.25A2.25 2.25 0 015.25 2h5.5A2.25 2.25 0 0113 4.25v2a.75.75 0 01-1.5 0v-2a.75.75 0 00-.75-.75h-5.5a.75.75 0 00-.75.75v11.5c0 .414.336.75.75.75h5.5a.75.75 0 00.75-.75v-2a.75.75 0 011.5 0v2A2.25 2.25 0 0110.75 18h-5.5A2.25 2.25 0 013 15.75V4.25z" clip-rule="evenodd" />
          <path fill-rule="evenodd" d="M6 10a.75.75 0 01.75-.75h9.546l-1.048-.943a.75.75 0 111.004-1.114l2.5 2.25a.75.75 0 010 1.114l-2.5 2.25a.75.75 0 11-1.004-1.114l1.048-.943H6.75A.75.75 0 016 10z" clip-rule="evenodd" />
        </svg>
        Compose and reuse
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Compose modules with Ruby control flow. Keep fixed steps deterministic; use an agent when the model has a useful choice among tools or actions.</p>
      </div>
    </div>

    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-coral" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path fill-rule="evenodd" d="M10 1a4.5 4.5 0 00-4.5 4.5V9H5a2 2 0 00-2 2v6a2 2 0 002 2h10a2 2 0 002-2v-6a2 2 0 00-2-2h-.5V5.5A4.5 4.5 0 0010 1zm3 8V5.5a3 3 0 10-6 0V9h6z" clip-rule="evenodd" />
        </svg>
        Control the runtime
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Ruby owns state, permissions, budgets, errors, and termination. Traces and persisted prompt artifacts make executions inspectable.</p>
      </div>
    </div>

    <div class="flex flex-col">
      <div class="flex items-center gap-x-3 text-base font-semibold leading-7 text-gray-900">
        <svg class="h-5 w-5 flex-none text-dspy-coral" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path d="M3.196 12.87l-.825.483a.75.75 0 000 1.294l7.25 4.25a.75.75 0 00.758 0l7.25-4.25a.75.75 0 000-1.294l-.825-.484-5.666 3.322a2.25 2.25 0 01-2.276 0L3.196 12.87z" />
          <path d="M3.196 8.87l-.825.483a.75.75 0 000 1.294l7.25 4.25a.75.75 0 00.758 0l7.25-4.25a.75.75 0 000-1.294l-.825-.484-5.666 3.322a2.25 2.25 0 01-2.276 0L3.196 8.87z" />
          <path d="M10.38 1.103a.75.75 0 00-.76 0l-7.25 4.25a.75.75 0 000 1.294l7.25 4.25a.75.75 0 00.76 0l7.25-4.25a.75.75 0 000-1.294l-7.25-4.25z" />
        </svg>
        Observe behavior
      </div>
      <div class="mt-2 flex flex-auto flex-col text-base leading-7 text-gray-600">
        <p class="flex-auto">Modules emit events and tracing attributes. Optional integrations export spans; evaluation measures behavior against examples and metrics.</p>
      </div>
    </div>
  </div>
</div>

<div class="mx-auto max-w-7xl px-6 lg:px-8 py-16 bg-gray-50">
  <div class="mx-auto max-w-2xl lg:text-center mb-12">
    <h2 class="text-3xl font-bold font-serif tracking-tight text-gray-900 sm:text-4xl">Choose the adapter for the model you deploy</h2>
    <p class="mt-4 text-lg text-gray-600">DSPy.rb keeps provider SDKs in separate packages. Model capabilities still depend on the selected provider, endpoint, and SDK version.</p>
  </div>

  <div class="mx-auto max-w-4xl">
    <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
      <div class="rounded-lg bg-white p-4 sm:p-6 shadow-sm ring-1 ring-gray-900/5">
        <h3 class="text-lg font-semibold text-gray-900 mb-3">OpenAI</h3>
        <p class="text-sm text-gray-600">Install <code>dspy-openai</code>. Check the selected model and endpoint for structured output, tools, media, and streaming support.</p>
      </div>

      <div class="rounded-lg bg-white p-4 sm:p-6 shadow-sm ring-1 ring-gray-900/5">
        <h3 class="text-lg font-semibold text-gray-900 mb-3">Google Gemini</h3>
        <p class="text-sm text-gray-600">Install <code>dspy-gemini</code>. Verify model capabilities before relying on structured output, tools, media, or streaming.</p>
      </div>

      <div class="rounded-lg bg-white p-4 sm:p-6 shadow-sm ring-1 ring-gray-900/5">
        <h3 class="text-lg font-semibold text-gray-900 mb-3">Anthropic Claude</h3>
        <p class="text-sm text-gray-600">Install <code>dspy-anthropic</code>. Verify model capabilities before relying on structured output, tools, media, or streaming.</p>
      </div>

      <div class="rounded-lg bg-white p-4 sm:p-6 shadow-sm ring-1 ring-gray-900/5">
        <h3 class="text-lg font-semibold text-gray-900 mb-3">Local and compatible APIs</h3>
        <p class="text-sm text-gray-600">Use Ollama or an OpenAI-compatible endpoint. Confirm the server and model support each capability your agent needs.</p>
      </div>
    </div>

    <div class="mt-8 rounded-lg bg-dspy-coral/5 p-6 ring-1 ring-dspy-coral/20">
      <div class="flex items-start gap-x-3">
        <svg class="h-6 w-6 flex-none text-dspy-coral mt-1" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456zM16.894 20.567L16.5 21.75l-.394-1.183a2.25 2.25 0 00-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 001.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 001.423 1.423l1.183.394-1.183.394a2.25 2.25 0 00-1.423 1.423z" />
        </svg>
        <div class="flex-1">
          <h4 class="text-base font-semibold text-gray-900">One agent, different models</h4>
          <p class="mt-2 text-sm text-gray-600">Keep the signature, tools, and Ruby control flow stable when changing adapters. Re-evaluate the agent because model behavior and capabilities can change.</p>
        </div>
      </div>
    </div>

    <div class="mt-8 text-center">
      <a href="{{ '/getting-started/installation/#provider-setup' | relative_url }}" class="inline-flex items-center text-sm font-semibold text-dspy-coral hover:text-[#e05d3d]">
        Learn more about provider setup <span aria-hidden="true" class="ml-2">&rarr;</span>
      </a>
    </div>
  </div>
</div>
