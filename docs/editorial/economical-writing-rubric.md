# Economical-writing rubric

This rubric turns the house voice's claim → mechanism → boundary sequence into
an editorial review. The audit reports narrow candidates; it does not decide a
verdict, propose replacement copy, rewrite files, or fail because candidates
exist. A human reads every candidate in context.

## Dispositions

Use exactly the shared house-voice vocabulary:

- **DELETE** when removing the passage loses no mechanism, evidence,
  prerequisite, instruction, boundary, decision, historical fact, or earned
  voice.
- **EDIT** when the passage has a useful job but its wording hides scope,
  rotates terminology, delays the instruction, or substitutes rhetoric for a
  testable claim.
- **KEEP technical** when the passage supplies a correct mechanism, evidence,
  prerequisite, instruction, boundary, or decision. Technical compression may
  look aphoristic and still be necessary.
- **KEEP voice** when personality improves comprehension or earns memorability
  from nearby evidence. Record the audience, evidence, scope, and named editor
  required by the house-voice charter.

Deletion is safe only after the reviewer can point to the same paragraph or
adjacent material and show that no mechanism, evidence, prerequisite,
instruction, qualification, ownership rule, or decision disappears. Shorter
copy is not economical when it makes a claim stronger or a boundary harder to
find. When in doubt, use EDIT or KEEP technical and explain the semantic job.

## Categories

### AI aphorism

A portable maxim about AI, prompts, software, engineering, or the future that
sounds complete without a local mechanism or boundary. Its nouns can change
without changing its advice. DELETE when it merely closes or advertises; EDIT
when it is trying to carry a real technical distinction. Do not classify an
earned compression such as a validation-versus-correctness boundary merely
because it is short or balanced.

### Synthetic flourish

A stock metaphor, dramatic reveal, or motivational ending whose emotional arc
is not earned by the surrounding evidence. Typical structure announces magic,
a journey, an adventure, or a new era instead of observable behavior. DELETE
when the adjacent instruction already lands; KEEP voice only under the
charter's bounded rhetorical-exception record.

### Chatbot cadence

Assistant-like turn-taking that asks whether the reader is ready and then
invites them to dive, jump, or explore. It simulates conversation without
learning anything from the answer. DELETE the invitation and preserve the
task; EDIT if the question is a genuine branch the reader must decide.

### Empty contrast

A reversal shaped like “not X, but Y” or “it is not X; it is Y” whose two sides
name attitudes, abstractions, or status rather than technical alternatives.
DELETE it when neither side changes a decision. EDIT it when a real distinction
is present but the mechanism is missing.

Real contrasts are allowed. Native structured output versus prompt-based JSON,
ReAct versus CodeAct, validation versus correctness, application-owned state
versus model input, and API parity versus evaluated task behavior name
different mechanisms or responsibilities. A compact contrast is KEEP technical
when nearby evidence makes the decision consequence clear.

### Tutorial patter

Lesson narration such as announcing what “we” will do, congratulating the
reader for reaching a step, or recapping progress before the next command.
DELETE narration that can be removed without changing sequence. EDIT it into a
prerequisite or transition when order matters. Numbered steps, temporal words,
and direct imperatives are not patter by themselves.

### Generic heading

A heading such as an overview, introduction, summary, or next step that labels
document position rather than reader value. Judge the heading by task value,
not by a banned-word list. The audit compares short or positional headings with
the source's declared `public-doc-corpus.yml` outcome; the same heading can be
useful for one source and taskless for another. Useful headings name a concept,
action, decision, failure, symptom, boundary, or observable result: “Choose a
JSON strategy” and “Diagnose provider timeouts” tell the reader what the
section is for. Article titles may keep earned voice under the charter.

### Vague praise

Evaluative modifiers that assert quality without naming a dimension, supported
variant, handled failure, or evidence. The audit requires a claim structure: a
subject plus multiple unsupported evaluative modifiers. “An automatic, simple,
robust framework” is a candidate because the whole phrase makes an unbounded
quality claim, not because any of those words is banned. `automatic`, `simple`,
and `robust` alone never trigger the audit. KEEP technical when the same
sentence names the trigger or measured dimension; EDIT or DELETE when praise
substitutes for it.

### Throat-clearing

A preface that tells the reader a claim is important, worth noting, or about to
be discussed before stating it. DELETE the preface when the claim stands on its
own. KEEP technical when the apparent preface is itself a safety signal or
prerequisite and removing it would change urgency or scope.

### Narrating comments

A comment that restates the visible operation or announces what the adjacent
section shows, without explaining why, ownership, lifecycle, units, side
effects, or a non-obvious constraint. DELETE redundant narration. KEEP
technical comments that explain a boundary the code cannot express. The audit
only reports narrow prose/HTML-comment shapes outside code; it never scans
fenced, indented, or quoted code mechanically.

### Elegant variation

Rotating synonyms for one concept to avoid repetition. In technical prose this
creates false distinctions and makes search harder. EDIT the passage to use one
canonical term unless two different mechanisms are genuinely meant. The audit
reports only close, declared canonical/variant pairs; it does not suggest a
replacement or decide that two terms are equivalent.

## Canonical terminology

Canonical terms follow the semantic jobs in
[`semantic-anchors.yml`](semantic-anchors.yml), not a general style thesaurus:

- **signature** defines typed inputs, outputs, and instructions;
- **predictor** executes a typed signature; use **Predict**,
  **ChainOfThought**, or **ReAct** for the named predictor;
- **module** composes predictors and deterministic Ruby behavior;
- **agent** makes a bounded model-directed action choice;
- **tool** is one callable capability and **Toolset** groups supported tools;
- **language model** is the configured inference provider/model boundary;
- **typed program** is the application-facing composition;
- **example** is an input/expected-behavior record, **metric** scores the named
  behavior, **evaluation** applies them, and **optimizer** searches within the
  supplied examples, metric, and budget;
- **trace** records what ran; it is not correctness evidence;
- **validation** constrains shape or declared types; it does not establish task
  correctness.

Do not flatten meaningful distinctions in pursuit of repetition. “Schema” is
correct when discussing a schema, “contract” is correct when discussing an
application boundary, and “workflow” is correct for fixed application-owned
sequencing. Elegant variation applies only when the prose uses those words as
interchangeable labels for the same object.

## Audit contract

Run `ruby docs/scripts/audit_economical_writing.rb`. With no paths, the audit
derives public and history sources from `public-doc-corpus.yml`, excluding
derived owners and every explicit exclusion. Explicit paths receive the same
classification checks and cannot opt generated output or internal plans back
in. `--jsonl` emits the same findings as JSON Lines.

Text output is stable:

```text
path:line: category: rule-id: message
```

Findings are sorted by path, numeric physical line, category, then rule id.
Frontmatter, backtick and tilde fences, indented code, explicitly `>`-marked
block-quote lines (including nested marked lines), inline code, Markdown
destinations, autolinks, and raw URLs are masked while link labels remain
readable. An unmarked line after a quote is ordinary prose and remains in scope.
Unterminated frontmatter, fences, or inline-code spans produce a parser
diagnostic and suppress the remainder rather than auditing uncertain text.
UTF-8 and CRLF inputs retain physical line numbers.

Candidate findings exit successfully. Only invocation, configuration, read, or
parse failures return nonzero. There is no fail-on-match option, rewrite mode,
replacement engine, or exact-copy trigger list. Future integration with the
unified documentation gate in dspy.rb-2ey.10 and the review checklist in
dspy.rb-2ey.17 remains informational; this audit adds no CI failure semantics.

Use [`economical-writing-fixtures.yml`](economical-writing-fixtures.yml) for
shared reviewer calibration. Reviewers classify samples independently before
reading the recorded adjudication.
