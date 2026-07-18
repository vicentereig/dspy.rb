---
layout: home
title: "DSPy.rb | Typed AI Agents in Ruby"
description: "Build typed agents in Ruby with Sorbet contracts, model tools, evaluation, and prompt optimization."
date: 2025-06-28 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
<!-- ============================ HERO — Workbench ============================ -->
<section class="border-b border-rule">
  <div class="mx-auto max-w-6xl px-6 lg:px-8 py-16 sm:py-24">
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-x-12 gap-y-12 items-center">
      <div class="lg:col-span-6 min-w-0" data-hm-enter>
        <p class="text-sm text-ink-3">
          Ruby-native agents on <a href="https://dspy.ai" rel="noopener noreferrer" class="text-link underline underline-offset-4 decoration-1 hover:decoration-2">DSPy's programming model</a>
          &middot; <a href="{{ site.config.dspy_release_url }}" class="text-ink hover:text-dspy-coral">v{{ site.config.dspy_version }}</a>
        </p>
        <h1 class="mt-4 font-serif font-bold text-ink tracking-[-0.02em] leading-[1.02] text-[clamp(2.5rem,6vw,4.5rem)] [overflow-wrap:anywhere]">Build typed AI agents in Ruby</h1>
        <p class="mt-6 text-lg leading-8 text-ink-2 max-w-xl">Define task contracts with Sorbet. Give models typed tools. Keep state, limits, errors, and side effects in Ruby.</p>
        <ul class="mt-6 space-y-2 text-sm text-ink-2">
          <li class="flex items-baseline gap-x-2"><span class="text-dspy-coral" aria-hidden="true">&mdash;</span>Typed agent contracts with Sorbet</li>
          <li class="flex items-baseline gap-x-2"><span class="text-dspy-coral" aria-hidden="true">&mdash;</span>Evaluation and prompt optimization</li>
          <li class="flex items-baseline gap-x-2"><span class="text-dspy-coral" aria-hidden="true">&mdash;</span>OpenAI, Anthropic, Gemini, Ollama</li>
        </ul>
        <div class="mt-10 flex flex-wrap items-center gap-x-6 gap-y-3">
          <a href="{{ '/getting-started/' | relative_url }}" class="rounded-[6px] bg-dspy-coral px-4 py-2.5 text-sm font-semibold text-white hover:bg-[color:var(--color-accent-hover)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-dspy-coral">Get started</a>
          <a href="{{ '/core-concepts/' | relative_url }}" class="text-sm font-semibold text-ink hover:underline underline-offset-4">Learn the concepts <span aria-hidden="true">&rarr;</span></a>
        </div>
      </div>
      <div class="lg:col-span-6 min-w-0" data-hm-enter style="animation-delay:80ms">
        <div class="rounded-[10px] border border-rule p-1 shadow-sm">
<div markdown="1">
```ruby
class AnswerWeather < DSPy::Signature
  description "Answer weather questions with tools"

  input  { const :question, String }
  output { const :answer,   String }
end

agent = DSPy::ReAct.new(
  AnswerWeather,
  tools: [WeatherTool.new],
  max_iterations: 3
)

agent.call(question: "Weather in Valencia?").answer
# => "72°F and sunny in Valencia"
```
</div>
        </div>
        <p class="mt-3 text-xs text-ink-3">A signature types the boundary; Ruby owns the tools and the loop.</p>
      </div>
    </div>
  </div>
</section>

<!-- ============= THE SHAPE OF AN AGENT — anatomy, then in the wild ============= -->
<section class="mx-auto max-w-4xl px-6 lg:px-8 py-16 sm:py-24">
  <div class="max-w-2xl">
    <p class="text-sm font-medium text-dspy-coral">The shape of an agent</p>
    <h2 class="mt-2 font-serif font-bold text-ink text-3xl sm:text-4xl tracking-[-0.01em]">A contract, a tool, a bounded loop</h2>
    <p class="mt-5 text-lg leading-8 text-ink-2">A signature defines the task and result. Ruby implements the tools and owns permissions, errors, side effects, and iteration limits &mdash; the same shape every program on this page is built from.</p>
  </div>

  <!-- Horizontal pipeline: Define → Run → Inspect (native snap; JS adds arrows/dots/keyboard) -->
  <div class="mt-12" data-agent-pipeline>
    <div data-agent-controls hidden class="mb-6 items-center gap-x-4">
      <div class="flex gap-x-2">
        <button type="button" data-agent-prev aria-label="Previous step" class="grid h-9 w-9 place-items-center rounded-full border border-rule text-ink-2 transition hover:border-ink hover:text-ink disabled:opacity-30 disabled:hover:border-rule disabled:hover:text-ink-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-dspy-coral"><span aria-hidden="true">&larr;</span></button>
        <button type="button" data-agent-next aria-label="Next step" class="grid h-9 w-9 place-items-center rounded-full border border-rule text-ink-2 transition hover:border-ink hover:text-ink disabled:opacity-30 disabled:hover:border-rule disabled:hover:text-ink-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-dspy-coral"><span aria-hidden="true">&rarr;</span></button>
      </div>
      <ol data-agent-dots aria-hidden="true" class="flex items-center gap-x-2"></ol>
      <span data-agent-status class="ml-auto font-mono text-xs text-ink-3">01 / 03</span>
    </div>
    <ol data-agent-track tabindex="0" role="list" aria-label="How an agent runs, in three steps" class="flex flex-col gap-10 lg:ml-[calc(50%-50vw)] lg:mr-[calc(50%-50vw)] lg:w-screen lg:flex-row lg:gap-6 lg:overflow-x-auto lg:scroll-smooth lg:snap-x lg:snap-mandatory lg:pb-3 lg:pl-[calc(50vw-28rem+2rem)] lg:pr-8 lg:scroll-pl-[calc(50vw-28rem+2rem)] lg:[scrollbar-width:none] lg:[&::-webkit-scrollbar]:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-dspy-coral">
      <li class="agent-panel flex min-w-0 flex-col lg:shrink-0 lg:snap-start lg:basis-[38rem]">
        <div data-agent-head>
          <div class="flex items-baseline gap-x-3">
            <span class="font-mono text-sm text-dspy-coral">01</span>
            <h3 class="font-serif text-xl font-semibold text-ink">Define the contract and tool</h3>
          </div>
          <p class="mt-2 text-ink-2">The signature types the agent's boundary. The tool exposes one narrow Ruby capability.</p>
        </div>
        <div class="mt-4 rounded-[10px] border border-rule p-1">
<div markdown="1">
```ruby
class AnswerWeather < DSPy::Signature
  description "Answer weather questions with tools"

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
        </div>
      </li>
      <li class="agent-panel flex min-w-0 flex-col lg:shrink-0 lg:snap-start lg:basis-[38rem]">
        <div data-agent-head>
          <div class="flex items-baseline gap-x-3">
            <span class="font-mono text-sm text-dspy-coral">02</span>
            <h3 class="font-serif text-xl font-semibold text-ink">Run a bounded tool loop</h3>
          </div>
          <p class="mt-2 text-ink-2"><code>ReAct</code> lets the model call the weather tool, observe its result, and finish with a typed answer.</p>
        </div>
        <div class="mt-4 rounded-[10px] border border-rule p-1">
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
        </div>
      </li>
      <li class="agent-panel flex min-w-0 flex-col lg:shrink-0 lg:snap-start lg:basis-[38rem]">
        <div data-agent-head>
          <div class="flex items-baseline gap-x-3">
            <span class="font-mono text-sm text-dspy-coral">03</span>
            <h3 class="font-serif text-xl font-semibold text-ink">Inspect what happened</h3>
          </div>
          <p class="mt-2 text-ink-2">The answer follows the declared type. The history records tool choices and results.</p>
        </div>
        <div class="mt-4 rounded-[10px] border border-rule p-1">
<div markdown="1">
```ruby
result.answer.class
# => String

result.history.each do |step|
  puts [step[:action], step[:tool_input], step[:observation]].inspect
end
```
</div>
        </div>
      </li>
    </ol>
  </div>

  <p class="mt-10 text-lg leading-8 text-ink-2">The model chooses whether to call a tool or finish; Ruby executes each tool and enforces the loop limit. Evaluate complete runs with examples and metrics, then use an optimizer to search for better instructions and demonstrations.</p>

  <!-- ===== Movement 2 — the same shape, real programs ===== -->
  <div class="mt-20 max-w-2xl border-t border-rule pt-14">
    <h3 class="font-serif font-bold text-ink text-2xl sm:text-3xl tracking-[-0.01em]">The same shape, real programs</h3>
    <p class="mt-4 text-lg text-ink-2">Each runs from a checkout of the repository. Here is the piece that matters; the rest is in the example's README.</p>
  </div>

  <!-- Program · Agents & tools -->
  <div class="mt-14 grid grid-cols-1 gap-x-10 gap-y-5 lg:grid-cols-[13rem_minmax(0,1fr)] lg:items-start">
    <div class="lg:pt-1">
      <p class="text-sm font-medium text-dspy-coral">Agents &amp; tools</p>
      <h3 class="mt-2 font-serif text-xl font-semibold text-ink">A read-only GitHub agent</h3>
      <p class="mt-2 text-ink-2">A <code>ReAct</code> agent handed the GitHub CLI as read-only tools &mdash; it inspects repos, issues, and pull requests, and cannot write.</p>
      <a href="https://github.com/vicentereig/dspy.rb/tree/main/examples/github-assistant" rel="noopener noreferrer" class="mt-3 inline-block font-mono text-sm text-link underline underline-offset-4 decoration-1 hover:decoration-2 [overflow-wrap:anywhere]">examples/github-assistant <span aria-hidden="true">&rarr;</span></a>
    </div>
    <div class="min-w-0 rounded-[10px] border border-rule p-1">
<div markdown="1">
```ruby
class GitHubAssistant < DSPy::Signature
  description "Operate on a repo with the GitHub CLI"

  input do
    const :task, String
    const :repository, String, default: ""
  end
  output { const :result, String }
end

# Read-only GitHub CLI tools — inspect only, no writes
tools = DSPy::Tools::GitHubCLIToolset.to_tools
agent = DSPy::ReAct.new(
  GitHubAssistant,
  tools: tools,
  max_iterations: 15
)

agent.call(
  task: "List open PRs and flag those ready for review",
  repository: "vicentereig/dspy.rb"
).result
```
</div>
    </div>
  </div>

  <!-- Program · Type-driven control -->
  <div class="mt-14 grid grid-cols-1 gap-x-10 gap-y-5 border-t border-rule pt-14 lg:grid-cols-[13rem_minmax(0,1fr)] lg:items-start">
    <div class="lg:pt-1">
      <p class="text-sm font-medium text-dspy-coral">Type-driven control</p>
      <h3 class="mt-2 font-serif text-xl font-semibold text-ink">Union types choose the action</h3>
      <p class="mt-2 text-ink-2">The model returns one of several typed actions in a single union field; Ruby pattern matching dispatches on the <code>T::Struct</code> it chose.</p>
      <a href="https://github.com/vicentereig/dspy.rb/tree/main/examples/coffee-shop-agent" rel="noopener noreferrer" class="mt-3 inline-block font-mono text-sm text-link underline underline-offset-4 decoration-1 hover:decoration-2 [overflow-wrap:anywhere]">examples/coffee-shop-agent <span aria-hidden="true">&rarr;</span></a>
    </div>
    <div class="min-w-0 rounded-[10px] border border-rule p-1">
<div markdown="1">
```ruby
class CoffeeShopSignature < DSPy::Signature
  description "Analyze a request and pick an action"

  input { const :customer_request, String }
  output do
    # one typed action from a union
    const :action, T.any(
      CoffeeShopActions::MakeDrink,
      CoffeeShopActions::RefundOrder,
      CoffeeShopActions::CallManager
    )
  end
end

# Ruby pattern-matches the action the model chose
case (action = result.action)
when CoffeeShopActions::MakeDrink
  "Making a #{action.size.serialize} #{action.drink_type}"
when CoffeeShopActions::RefundOrder
  "Refunding $#{action.refund_amount}"
when CoffeeShopActions::CallManager
  "Escalating: #{action.issue}"
end
```
</div>
    </div>
  </div>

  <!-- Program · Optimization -->
  <div class="mt-14 grid grid-cols-1 gap-x-10 gap-y-5 border-t border-rule pt-14 lg:grid-cols-[13rem_minmax(0,1fr)] lg:items-start">
    <div class="lg:pt-1">
      <p class="text-sm font-medium text-dspy-coral">Optimization</p>
      <h3 class="mt-2 font-serif text-xl font-semibold text-ink">Compile a classifier with MIPROv2</h3>
      <p class="mt-2 text-ink-2">Give the optimizer a program, a metric, and labelled examples; it searches instructions and demonstrations and keeps the best.</p>
      <a href="https://github.com/vicentereig/dspy.rb/tree/main/examples/ade_optimizer_miprov2" rel="noopener noreferrer" class="mt-3 inline-block font-mono text-sm text-link underline underline-offset-4 decoration-1 hover:decoration-2 [overflow-wrap:anywhere]">examples/ade_optimizer_miprov2 <span aria-hidden="true">&rarr;</span></a>
    </div>
    <div class="min-w-0 rounded-[10px] border border-rule p-1">
<div markdown="1">
```ruby
class ADETextClassifier < DSPy::Signature
  description "Flag adverse drug events in clinical text"

  input  { const :text, String }
  output { const :label, ADELabel }
end

# Search instructions + demonstrations against a metric
optimizer = DSPy::Teleprompt::MIPROv2.new(metric: metric)
result = optimizer.compile(
  baseline_program,
  trainset: train_examples,
  valset: val_examples
)

optimized_program = result.optimized_program
```
</div>
    </div>
  </div>

  <!-- More examples · compact list -->
  <div class="mt-16 border-t border-rule pt-10">
    <p class="text-sm font-medium text-ink-3">More in the repository</p>
    <div class="mt-4 divide-y divide-rule border-y border-rule">
      <a href="https://github.com/vicentereig/dspy.rb/tree/main/examples/react_loop" rel="noopener noreferrer" class="group grid grid-cols-1 min-w-0 sm:grid-cols-[minmax(0,17rem)_minmax(0,1fr)] gap-x-8 gap-y-1 py-4 sm:items-baseline">
        <span class="font-mono text-sm text-ink group-hover:text-dspy-coral [overflow-wrap:anywhere]">examples/react_loop</span>
        <span class="text-ink-2">Calculator, unit-conversion, and date tools driven in a bounded <code>ReAct</code> loop. <span class="text-ink-3 transition-transform group-hover:text-ink group-hover:translate-x-0.5 inline-block" aria-hidden="true">&rarr;</span></span>
      </a>
      <a href="https://github.com/vicentereig/dspy.rb/tree/main/examples/sentiment-evaluation" rel="noopener noreferrer" class="group grid grid-cols-1 min-w-0 sm:grid-cols-[minmax(0,17rem)_minmax(0,1fr)] gap-x-8 gap-y-1 py-4 sm:items-baseline">
        <span class="font-mono text-sm text-ink group-hover:text-dspy-coral [overflow-wrap:anywhere]">examples/sentiment-evaluation</span>
        <span class="text-ink-2">A sentiment classifier compared across a built-in, a custom, and a weighted-demonstration metric. <span class="text-ink-3 transition-transform group-hover:text-ink group-hover:translate-x-0.5 inline-block" aria-hidden="true">&rarr;</span></span>
      </a>
      <a href="https://github.com/vicentereig/dspy.rb/tree/main/examples/multimodal" rel="noopener noreferrer" class="group grid grid-cols-1 min-w-0 sm:grid-cols-[minmax(0,17rem)_minmax(0,1fr)] gap-x-8 gap-y-1 py-4 sm:items-baseline">
        <span class="font-mono text-sm text-ink group-hover:text-dspy-coral [overflow-wrap:anywhere]">examples/multimodal</span>
        <span class="text-ink-2">Image analysis and bounding-box extraction returned as typed outputs. <span class="text-ink-3 transition-transform group-hover:text-ink group-hover:translate-x-0.5 inline-block" aria-hidden="true">&rarr;</span></span>
      </a>
    </div>
    <p class="mt-6">
      <a href="https://github.com/vicentereig/dspy.rb/tree/main/examples" rel="noopener noreferrer" class="text-sm font-semibold text-link underline underline-offset-4 decoration-1 hover:decoration-2">Browse all examples <span aria-hidden="true">&rarr;</span></a>
    </p>
  </div>
</section>

<!-- ==================== CAPABILITIES — editorial rows ==================== -->
<section class="border-t border-rule bg-paper-2">
  <div class="mx-auto max-w-5xl px-6 lg:px-8 py-16 sm:py-24">
    <div class="max-w-2xl">
      <h2 class="font-serif font-bold text-ink text-3xl sm:text-4xl tracking-[-0.01em]">Built for Ruby developers</h2>
      <p class="mt-4 text-lg text-ink-2">Ruby types and control flow for agents and model-backed programs.</p>
    </div>
    <dl class="mt-14 grid grid-cols-1 md:grid-cols-2 gap-x-16 gap-y-12">
      <div class="border-t border-rule pt-5">
        <dt class="font-serif text-lg font-semibold text-ink">Type-safe from the start</dt>
        <dd class="mt-2 text-ink-2 leading-7">Signatures validate inputs and convert provider responses into declared Ruby types. Invalid outputs fail before application code uses them.</dd>
      </div>
      <div class="border-t border-rule pt-5">
        <dt class="font-serif text-lg font-semibold text-ink">Test like normal code</dt>
        <dd class="mt-2 text-ink-2 leading-7">Use RSpec for deterministic behavior and evaluation sets for model behavior. Tests and metrics answer different questions.</dd>
      </div>
      <div class="border-t border-rule pt-5">
        <dt class="font-serif text-lg font-semibold text-ink">Optimize with data</dt>
        <dd class="mt-2 text-ink-2 leading-7">Give an optimizer examples and a metric. It can search instructions and demonstrations, then persist the resulting prompt artifacts.</dd>
      </div>
      <div class="border-t border-rule pt-5">
        <dt class="font-serif text-lg font-semibold text-ink">Compose and reuse</dt>
        <dd class="mt-2 text-ink-2 leading-7">Compose modules with Ruby control flow. Keep fixed steps deterministic; use an agent when the model has a useful choice among tools or actions.</dd>
      </div>
      <div class="border-t border-rule pt-5">
        <dt class="font-serif text-lg font-semibold text-ink">Control the runtime</dt>
        <dd class="mt-2 text-ink-2 leading-7">Ruby owns state, permissions, budgets, errors, and termination. Traces and persisted prompt artifacts make executions inspectable.</dd>
      </div>
      <div class="border-t border-rule pt-5">
        <dt class="font-serif text-lg font-semibold text-ink">Observe behavior</dt>
        <dd class="mt-2 text-ink-2 leading-7">Modules emit events and tracing attributes. Optional integrations export spans; evaluation measures behavior against examples and metrics.</dd>
      </div>
    </dl>
  </div>
</section>

<!-- ==================== PROVIDERS — hairline row ==================== -->
<section class="mx-auto max-w-5xl px-6 lg:px-8 py-16 sm:py-24">
  <div class="max-w-2xl">
    <h2 class="font-serif font-bold text-ink text-3xl sm:text-4xl tracking-[-0.01em]">Choose the adapter for the model you deploy</h2>
    <p class="mt-4 text-lg text-ink-2">DSPy.rb keeps provider SDKs in separate packages. Model capabilities still depend on the selected provider, endpoint, and SDK version.</p>
  </div>
  <dl class="mt-12 divide-y divide-rule border-y border-rule">
    <div class="grid grid-cols-1 sm:grid-cols-[10rem_1fr] gap-x-8 gap-y-1 py-5">
      <dt class="font-serif text-lg font-semibold text-ink">OpenAI</dt>
      <dd class="text-ink-2">Install <code>dspy-openai</code>. Check the selected model and endpoint for structured output, tools, media, and streaming support.</dd>
    </div>
    <div class="grid grid-cols-1 sm:grid-cols-[10rem_1fr] gap-x-8 gap-y-1 py-5">
      <dt class="font-serif text-lg font-semibold text-ink">Google Gemini</dt>
      <dd class="text-ink-2">Install <code>dspy-gemini</code>. Verify model capabilities before relying on structured output, tools, media, or streaming.</dd>
    </div>
    <div class="grid grid-cols-1 sm:grid-cols-[10rem_1fr] gap-x-8 gap-y-1 py-5">
      <dt class="font-serif text-lg font-semibold text-ink">Anthropic Claude</dt>
      <dd class="text-ink-2">Install <code>dspy-anthropic</code>. Verify model capabilities before relying on structured output, tools, media, or streaming.</dd>
    </div>
    <div class="grid grid-cols-1 sm:grid-cols-[10rem_1fr] gap-x-8 gap-y-1 py-5">
      <dt class="font-serif text-lg font-semibold text-ink">RubyLLM</dt>
      <dd class="text-ink-2">Install <code>dspy-ruby_llm</code> to route models through <a href="https://rubyllm.com" rel="noopener noreferrer" class="text-link underline underline-offset-4 decoration-1 hover:decoration-2">RubyLLM</a>&rsquo;s registry with the <code>ruby_llm/&hellip;</code> prefix. It reaches every provider RubyLLM supports and reuses an existing RubyLLM configuration.</dd>
    </div>
    <div class="grid grid-cols-1 sm:grid-cols-[10rem_1fr] gap-x-8 gap-y-1 py-5">
      <dt class="font-serif text-lg font-semibold text-ink">Local &amp; compatible</dt>
      <dd class="text-ink-2">Use Ollama or an OpenAI-compatible endpoint. Confirm the server and model support each capability your agent needs.</dd>
    </div>
  </dl>
  <p class="mt-6 text-ink-2">One agent, different models: keep the signature, tools, and Ruby control flow stable when changing adapters. Re-evaluate the agent &mdash; model behavior and capabilities can change.</p>
  <p class="mt-6">
    <a href="{{ '/getting-started/installation/#provider-setup' | relative_url }}" class="text-sm font-semibold text-link underline underline-offset-4 decoration-1 hover:decoration-2">Learn more about provider setup <span aria-hidden="true">&rarr;</span></a>
  </p>
</section>

<!-- ==================== CLOSE — quiet editorial CTA ==================== -->
<section class="border-t border-rule bg-paper-2">
  <div class="mx-auto max-w-5xl px-6 lg:px-8 py-16 sm:py-20">
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-x-12 gap-y-6 items-end">
      <div class="lg:col-span-8">
        <h2 class="font-serif font-bold text-ink text-3xl sm:text-4xl tracking-[-0.01em]">Build your first typed program</h2>
        <p class="mt-4 text-lg leading-8 text-ink-2 max-w-xl">Define the contract, evaluate the output, and run an optimizer when examples, a metric, and a budget are ready.</p>
      </div>
      <div class="lg:col-span-4 flex flex-wrap items-center gap-x-6 gap-y-3 lg:justify-end">
        <a href="{{ '/getting-started/' | relative_url }}" class="rounded-[6px] bg-dspy-coral px-4 py-2.5 text-sm font-semibold text-white hover:bg-[color:var(--color-accent-hover)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-dspy-coral">Get started</a>
        <a href="https://github.com/vicentereig/dspy.rb" rel="noopener noreferrer" class="text-sm font-semibold text-ink hover:underline underline-offset-4">View on GitHub <span aria-hidden="true">&rarr;</span></a>
      </div>
    </div>
  </div>
</section>
