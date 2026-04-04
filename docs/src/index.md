---
layout: essay_docs
title: "Build One Agent Properly"
description: "A single-page DSPy.rb tutorial for building type-safe, async, observable agents in modern Ruby."
date: 2026-04-04 00:00:00 +0000
last_modified_at: 2026-04-04 00:00:00 +0000
toc:
  - id: why-this-page-exists
    label: Why This Page Exists
  - id: the-agent-we-are-building
    label: The Agent We Are Building
  - id: step-1-a-contract-before-a-prompt
    label: "Step 1: A Contract Before A Prompt"
  - id: step-2-give-the-agent-real-tools
    label: "Step 2: Give The Agent Real Tools"
  - id: step-3-put-the-loop-in-a-module
    label: "Step 3: Put The Loop In A Module"
  - id: step-4-separate-finding-from-answering
    label: "Step 4: Separate Finding From Answering"
  - id: step-5-make-state-explicit
    label: "Step 5: Make State Explicit"
  - id: step-6-add-async-fan-out
    label: "Step 6: Add Async Fan-Out"
  - id: step-7-make-the-loop-observable
    label: "Step 7: Make The Loop Observable"
  - id: what-to-ship
    label: What To Ship
  - id: what-to-read-next
    label: What To Read Next
---

<div class="essay-callout">
  <p>
    <strong>DSPy.rb is the MVC moment for Ruby agents.</strong> Signatures define the contract.
    Modules hold the loop. Tools connect the agent to the world. Typed state keeps the runtime honest.
    The result is not "better prompts." It is software you can read, test, and operate.
  </p>
</div>

<h2 id="why-this-page-exists">Why This Page Exists</h2>

**What?**

This site used to look like a documentation website. It now starts with a single page because the shortest path to understanding DSPy.rb is not a taxonomy. It is one agent, built properly, step by step.

The page is intentionally written for both humans and humans with agents:

- explicit sections
- explicit diffs
- explicit tradeoffs
- no assumption that "advanced" concepts belong in a different room

**So What?**

If you can build one good agent, the rest of the framework starts making sense:

- why signatures matter
- why tool schemas beat prompt sprawl
- why state should be typed
- why observability belongs in the loop
- why async Ruby is a real advantage

This is the same reason Rails clicked for web apps. Once the architecture is visible, the abstractions stop feeling magical.

**What Not?**

- Not a docs portal with ten entry points and no argument.
- Not a workflow cookbook.
- Not a landing page pretending to be documentation.

---

<h2 id="the-agent-we-are-building">The Agent We Are Building</h2>

We are going to build an **Evidence Brief Agent**.

Its job is simple:

1. accept a research question
2. search a corpus for likely documents
3. fetch the relevant evidence
4. keep track of what it already knows
5. produce a typed answer with citations

Here is the destination:

```text
question
  -> search_corpus
  -> fetch_document
  -> typed TurnState
  -> synthesize evidence
  -> EvidenceBrief(answer, citations, open_questions)
```

And here is the shape of the final answer:

```ruby
class Citation < T::Struct
  const :document_id, String
  const :excerpt, String
  const :why_it_matters, String
end

class EvidenceBrief < DSPy::Signature
  description "Answer the question using gathered evidence only."

  input do
    const :question, String
    const :evidence, T::Array[Citation]
  end

  output do
    const :answer, String
    const :citations, T::Array[Citation]
    const :open_questions, T::Array[String], default: []
  end
end
```

**What?**

This is an agent, not a pipeline. It decides what to look at next based on what it has already found.

**So What?**

This example is rich enough to justify the architecture:

- typed inputs and outputs
- tools with real contracts
- long-context navigation
- async fetches
- step-level traces

**What Not?**

- Not a toy chatbot.
- Not a sequential chain of fixed steps.
- Not a "general AI assistant" with no bounded job.

---

<h2 id="step-1-a-contract-before-a-prompt">Step 1: A Contract Before A Prompt</h2>

Start with the boundary.

```ruby
class AskResearchQuestion < DSPy::Signature
  description "Answer a research question with concrete evidence."

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end
```

That is already better than a prompt string in a service object, but it is still too soft. A real agent answer should say what evidence it used.

```diff
 class AskResearchQuestion < DSPy::Signature
   description "Answer a research question with concrete evidence."
 
   input do
     const :question, String
   end
 
   output do
-    const :answer, String
+    const :answer, String
+    const :citations, T::Array[Citation]
+    const :open_questions, T::Array[String], default: []
   end
 end
```

**What?**

The signature becomes the agent contract. The output shape says what "done" looks like.

**So What?**

Now the rest of your code can depend on something real:

- UI code can render citations directly
- tests can assert on evidence, not prose vibes
- the model is asked for structure, not just eloquence

**What Not?**

- Do not wait until later to make the output typed.
- Do not return a blob and promise to "clean it up downstream."
- Do not make citations optional if evidence is the point of the agent.

---

<h2 id="step-2-give-the-agent-real-tools">Step 2: Give The Agent Real Tools</h2>

The fastest way to create a fake agent is to write a prompt that says "search the corpus if needed" and then give it no search capability.

In DSPy.rb, capabilities become tools:

```ruby
class SearchHit < T::Struct
  const :document_id, String
  const :title, String
  const :snippet, String
end

class SearchCorpusTool < DSPy::Tools::Base
  tool_name "search_corpus"
  tool_description "Find relevant documents for a research question"

  sig { params(query: String).returns(T::Array[SearchHit]) }
  def call(query:)
    Corpus.search(query)
  end
end

class FetchDocumentTool < DSPy::Tools::Base
  tool_name "fetch_document"
  tool_description "Fetch the full content of one document by id"

  sig { params(document_id: String).returns(String) }
  def call(document_id:)
    Corpus.fetch(document_id)
  end
end
```

And the shift is architectural, not cosmetic:

```diff
- context = "You may search the corpus and quote relevant passages."
- result = predictor.call(question: question, context: context)
+ tools = [SearchCorpusTool.new, FetchDocumentTool.new]
+ agent = DSPy::ReAct.new(ResearchNavigator, tools: tools)
+ result = agent.call(question: question)
```

**What?**

The agent is now connected to the world through typed interfaces.

**So What?**

This solves three problems immediately:

- the model gets a real capability surface
- the runtime validates tool arguments
- your system stops relying on imaginary side effects hidden in prompt text

**What Not?**

- Do not stuff tool descriptions into the prompt and call that tool use.
- Do not use untyped hashes for search hits if you already know the shape.
- Do not make the tool layer return "whatever came back."

---

<h2 id="step-3-put-the-loop-in-a-module">Step 3: Put The Loop In A Module</h2>

Once the agent has more than one moving part, the loop needs a home. In DSPy.rb that home is `DSPy::Module`.

```ruby
class EvidenceBriefAgent < DSPy::Module
  def initialize
    super()
    @navigator = DSPy::ReAct.new(
      ResearchNavigator,
      tools: [SearchCorpusTool.new, FetchDocumentTool.new]
    )
    @synthesizer = DSPy::Predict.new(EvidenceBrief)
  end

  def forward(question:)
    findings = @navigator.call(question: question)
    @synthesizer.call(question: question, evidence: findings.evidence)
  end
end
```

**What?**

`DSPy::Module` is the orchestration seam. It is where dependencies, callbacks, per-instance configuration, and step wiring belong.

**So What?**

This is where the framework starts feeling like Ruby again:

- you can inject dependencies cleanly
- you can wrap `forward`
- you can expose named predictors
- you can test the loop as a real object

**What Not?**

- Do not leave the agent as a script full of globals.
- Do not spread orchestration across controllers, jobs, and helpers.
- Do not bury the actual loop under ad hoc service names with no DSPy boundary.

---

<h2 id="step-4-separate-finding-from-answering">Step 4: Separate Finding From Answering</h2>

This is the design move that shows up over and over in real agent systems.

Your inner loop should gather evidence. Your final step should answer for the user. Those are different jobs.

```ruby
class NavigateEvidence < DSPy::Signature
  description "Choose the next action needed to gather evidence."

  input do
    const :question, String
    const :current_context, String
    const :evidence, T::Array[Citation], default: []
  end

  output do
    const :reasoning, String
    const :action, String
    const :tool_name, String
    const :tool_args, T::Hash[String, T.untyped], default: {}
  end
end

class SynthesizeEvidenceBrief < DSPy::Signature
  description "Write the final answer using gathered evidence only."

  input do
    const :question, String
    const :evidence, T::Array[Citation]
  end

  output do
    const :answer, String
    const :citations, T::Array[Citation]
    const :open_questions, T::Array[String], default: []
  end
end
```

The diff is the whole lesson:

```diff
- class NavigateEvidence < DSPy::Signature
-   output do
-     const :answer, String
-     const :next_action, String
-   end
- end
+ class NavigateEvidence < DSPy::Signature
+   output do
+     const :reasoning, String
+     const :action, String
+     const :tool_name, String
+     const :tool_args, T::Hash[String, T.untyped], default: {}
+   end
+ end
+
+ class SynthesizeEvidenceBrief < DSPy::Signature
+   output do
+     const :answer, String
+     const :citations, T::Array[Citation]
+     const :open_questions, T::Array[String], default: []
+   end
+ end
```

**What?**

One predictor decides how to explore. Another predictor turns evidence into the final response.

**So What?**

This prevents a subtle but common failure mode: the loop answers too early because it cannot distinguish internal context from user-visible output.

It also gives you two clean places to tune:

- exploration quality
- answer quality

**What Not?**

- Do not ask the same predictor to navigate and to finish.
- Do not rely on "only answer when ready" as the primary control mechanism.
- Do not pass raw context windows directly to the user-facing layer.

---

<h2 id="step-5-make-state-explicit">Step 5: Make State Explicit</h2>

If the agent is going to search, fetch, stop, retry, or resume, state should stop living in instance variables and start living in a type.

```ruby
class TurnState < T::Struct
  const :iteration, Integer, default: 0
  const :searches_run, Integer, default: 0
  const :fetched_document_ids, T::Array[String], default: []
  const :citations, T::Array[Citation], default: []
  const :current_context, String, default: ""
end
```

```diff
- @iteration += 1
- @fetched_ids << hit.document_id
- @citations << citation
- @current_context = document_text
+ state = TurnState.new(
+   iteration: state.iteration + 1,
+   searches_run: state.searches_run,
+   fetched_document_ids: state.fetched_document_ids + [hit.document_id],
+   citations: state.citations + [citation],
+   current_context: document_text
+ )
```

**What?**

`TurnState` is the runtime truth of the loop.

**So What?**

Typed state unlocks the parts that usually get bolted on too late:

- checkpointing
- resuming
- observability
- deterministic tests around loop control

It also keeps the prompt honest. The model sees the parts of state it should see. The runtime owns the rest.

**What Not?**

- Do not put crucial loop state only in natural-language history.
- Do not use raw hashes if the shape is stable.
- Do not let state mutate in five places with no central type.

---

<h2 id="step-6-add-async-fan-out">Step 6: Add Async Fan-Out</h2>

Agents are usually I/O bound. Modern Ruby should show up in the design, not just in the Gemfile.

If the search tool returns five promising documents, fetch them concurrently:

```ruby
require "async"
require "async/barrier"

def fetch_candidates_concurrently(hits)
  Async do |task|
    barrier = Async::Barrier.new(parent: task)

    tasks = hits.map do |hit|
      barrier.async do
        [hit.document_id, @fetch_document.call(document_id: hit.document_id)]
      end
    end

    barrier.wait
    tasks.map(&:wait).to_h
  end.wait
end
```

```diff
- documents = hits.each_with_object({}) do |hit, acc|
-   acc[hit.document_id] = @fetch_document.call(document_id: hit.document_id)
- end
+ documents = fetch_candidates_concurrently(hits)
```

**What?**

Async enters where the agent has real independent work to do.

**So What?**

This is not decorative concurrency. It changes the shape of the system:

- the loop stays responsive
- slow documents stop blocking unrelated fetches
- retries do less collateral damage
- Ruby feels like a good fit for agents, not a compromise

**What Not?**

- Do not parallelize everything because you can.
- Do not hide concurrency inside magic middleware if the tutorial is about architecture.
- Do not serialize obviously independent I/O just because it is easier to explain.

---

<h2 id="step-7-make-the-loop-observable">Step 7: Make The Loop Observable</h2>

If you cannot answer "what did the agent do?" then you do not have an operable agent. You have a demo.

Add step events directly to the module boundary:

```ruby
def forward(question:, &on_step)
  on_step&.call(step_type: "selecting_action", status: "started")

  hits = @search_tool.call(query: question)

  on_step&.call(
    step_type: "tool_call",
    status: "complete",
    tool_name: "search_corpus",
    result: hits.map(&:document_id)
  )

  brief = @synthesizer.call(question: question, evidence: collect_citations(hits))

  on_step&.call(
    step_type: "synthesizing",
    status: "complete",
    result: { citations: brief.citations.length }
  )

  brief
end
```

That is enough to wire traces, UI updates, checkpointing, or step timelines without rewriting the agent later.

**What?**

Observability becomes part of the loop contract.

**So What?**

This is where the auditability argument cashes out:

- operators can debug failures
- users can watch the agent work
- tests can assert that the right steps happened
- product teams can tell whether the agent stopped for a good reason

**What Not?**

- Do not treat observability as dashboards only.
- Do not log only the final answer.
- Do not add traces as an afterthought once production bugs arrive.

---

<h2 id="what-to-ship">What To Ship</h2>

If you are building an agent with DSPy.rb, this is the minimum bar:

1. A typed signature at the entry point.
2. Tools or toolsets for real capabilities.
3. A `DSPy::Module` as the orchestration boundary.
4. Separate exploration from final answer generation when the task is multi-step.
5. Typed state for budgets, evidence, and progress.
6. Async fan-out where the work is genuinely independent.
7. Step-level observability.
8. Tests for both happy path and control-path failures.

If you only do one thing after reading this page, do this:

> Take one existing prompt-heavy agent and turn its output, tools, and state into types.

Everything else gets easier after that.

---

<h2 id="what-to-read-next">What To Read Next</h2>

If you want more depth after the one-page version:

- Read [AI Needs Its MVC Moment]({{ '/blog/articles/ai-needs-its-mvc-moment/' | relative_url }}) for the argument behind this style of system.
- Read [Building Your First ReAct Agent in Ruby]({{ '/blog/articles/react-agent-tutorial/' | relative_url }}) for the lower-level `ReAct` mechanics.
- Read [True Concurrency: How DSPy.rb's Async Retry System Makes Your Applications Faster]({{ '/blog/articles/async-telemetry-optimization/' | relative_url }}) for the runtime angle.
- Use [llms.txt]({{ '/llms.txt' | relative_url }}) when an agent needs the compact version.

The reference material still matters. It just should not be the first thing people see.
