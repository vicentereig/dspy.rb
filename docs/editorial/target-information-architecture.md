# Public documentation information architecture

This is the approved target for the documentation restructuring epic. It
describes future ownership and link behavior; it does not move or rewrite a
page. The checked source inventory and each source's disposition live in
[`public-doc-corpus.yml`](public-doc-corpus.yml). Run
`ruby docs/scripts/validate_public_doc_corpus.rb` after changing either the
corpus or local Markdown/ERB sources.

## Reader journey

| Section | Reader question | Canonical material |
| --- | --- | --- |
| Start | What is DSPy.rb and can I run it? | Root README, site home, one executable Quick Start |
| Understand | What do signatures, modules, and predictors mean? | Core Concepts |
| Build | How do I make a program or agent do work? | Build selector, examples, Toolsets primary guide |
| Evaluate / Optimize | How do I measure and improve the program? | Evaluation, benchmarking, GEPA, MIPROv2 |
| Operate | How do I observe, persist, register, and troubleshoot it? | Production |
| Extend | How do I change the system or add integrations? | Advanced guides and package READMEs |

The blog and changelog remain public history, not a competing learning path.
`llms.txt` and `llms-full.txt` remain public, derived entry points. This issue
declares their inputs and sync contract without asserting current route parity;
drift enforcement belongs to `dspy.rb-2ey.10`.

## Page ownership decisions

### Getting Started

`docs/src/getting-started/quick-start.md` is the single executable onboarding
owner. `installation.md` remains canonical for provider setup and keeps its
URL. `first-program.md` merges into Quick Start and redirects to its stable
first-program anchor. `getting-started/core-concepts.md` redirects to the Core Concepts
landing page. The section landing remains a short route selector rather than a
second tutorial.

### Toolsets

`docs/src/core-concepts/toolsets.md` owns the default question: how to define,
attach, and use a Toolset. `toolsets-guide.md` merges into that guide and its
current URL redirects to the relevant anchor. `advanced/custom-toolsets.md`
owns its distinct extension task, links back to the primary guide, and does
not re-explain the baseline contract. This gives the baseline topic one owner
without erasing the separately owned advanced task.

### Packages and generated references

Each package README owns package-specific usage and caveats. A future
capability matrix will own cross-package comparison claims. General provider
selection belongs in Installation, so package READMEs should link there rather
than duplicate it. Today, `llms.txt.erb` and `llms-full.txt.erb` are manually
maintained static ERB sources; they do not consume this manifest, page front
matter, rendered guides, or the article collection. Their target owner type is
`derived`: the documentation build will generate them from the planned inputs,
and they will not become canonical factual owners.
Generated-reference drift enforcement, including fragments, is explicitly
deferred to `dspy.rb-2ey.10`; this inventory does not assert identical current
route sets.

## URL contract

Every existing public site route is either kept or receives one explicit
redirect target in the corpus manifest. Repository READMEs retain their
repository URLs. Historical article routes are retained, even when their
content is no longer a current guide. No migration may silently remove a
deep-link, fragment, `llms.txt`, or `llms-full.txt` entry.
Manifest site routes are normalized logical routes and exclude the deployment
base path `/dspy.rb`; deployment configuration adds that prefix. Article
history routes follow Bridgetown's `/blog/articles/:slug/` collection pattern.

## Persona traces

These traces are acceptance checks for the target navigation, not idealized
marketing funnels.

1. **New Ruby developer:** `README.md` → `/getting-started/installation/` →
   `/getting-started/quick-start/` → `/core-concepts/signatures/` →
   `/core-concepts/predictors/` then `/core-concepts/modules/` →
   `/core-concepts/examples/` for Ruby composition → `/core-concepts/toolsets/`
   and `/advanced/stateful-agents/`. This preserves the novice prerequisite
   order: signature → predictor/module → Ruby composition → tools/agents.
2. **Agent builder:** `/core-concepts/toolsets/` →
   `repository:examples/coffee-shop-agent/README.md` →
   `/advanced/custom-toolsets/` only for the distinct extension task →
   `/production/observability/`.
3. **Quality owner:** `/getting-started/quick-start/` →
   `/optimization/evaluation/` → `/optimization/benchmarking-raw-prompts/` →
   `/optimization/gepa/` or `/optimization/miprov2/` →
   `/production/registry/` and `/production/observability/`.
4. **Maintainer extending an integration:**
   `repository:lib/dspy/openai/README.md` (representative package path) →
   `/getting-started/installation/` → `/advanced/` →
   `/advanced/module-runtime-context/` → `/llms-full.txt`. Package-specific
   facts remain in the README; cross-package claims belong to the future matrix.

## Review checklist

Before a later issue changes navigation or prose, confirm that it preserves the
named owner, target outcome, and URL disposition for every affected source;
updates both llms templates when generated reference changes; and leaves the
four traces continuous.
