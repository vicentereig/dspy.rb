# DSPy.rb house voice

Write for a Ruby developer making a technical decision. Be direct, specific,
and willing to name what the library does not own. Keep personality where it
sharpens the decision; cut it where it substitutes for evidence.

## The unit of useful prose

Prefer this sequence:

> **Claim → mechanism → boundary or decision**

A **technical claim** is a falsifiable statement about behavior, compatibility,
cost, quality, or ownership. A **mechanism** names the API, data flow, trigger,
or implementation that makes the claim true. A **boundary** names a required
condition, unsupported case, failure mode, or responsibility left to the
application. The final sentence should often tell the reader what to do.

Not every paragraph needs three sentences. A code sample can supply the
mechanism; a nearby table can supply the boundary. The pieces must still be
close enough that a reader can test the claim without hunting through the site.

**Earned compression** is a short line whose contrast or conclusion is already
supported by nearby facts. “Types give shape. Descriptions give meaning.” is
earned when the surrounding section shows the schema and the semantic guidance
each supplies. An **AI aphorism** is a portable maxim about AI, software, the
future, or “better” engineering that makes no local, testable distinction. It
sounds complete after its mechanism and boundary have been removed. Delete it
or replace it with the decision it was trying to carry.

## Contrast, headlines, and voice

Keep a contrast when it names real alternatives and changes a decision: native
structured output versus prompt-based JSON, or ReAct versus CodeAct. A compact
or playful headline may invite the reader into an article when its deck or
opening promptly supplies scope and evidence. Do not repeat that headline as a
framework guarantee.

Cut slogans that could advertise any LLM framework: “build the future,”
“production-ready,” “AI needs X,” or symmetrical “not prompts, programs” lines
with no named behavior. These phrases are not banned. The same words may be
accurate in a quoted historical title, a bounded comparison, or a claim backed
by the required evidence.

## Qualifiers must carry their scope

`automatic`, `zero-config`, `simple`, `robust`, `flexible`, and
`production-ready` trigger a claim check, not a word ban.

- **Automatic** names the trigger, the behavior performed, and what remains
  manual. “Requiring `sorbet/toon` installs the extensions automatically” is
  useful; “automatic optimization” is not.
- **Zero-config** is accurate only when the documented path requires no user
  configuration. Environment variables, optional gems, network setup, or
  provider credentials are configuration; name the actual auto-configuration
  step instead.
- **Simple** names the dimension: fewer fields, one process, no persistence, or
  a minimal example. It does not declare the whole task easy.
- **Robust** names the failure modes handled and the evidence used to test them.
- **Flexible** enumerates the supported variants or extension point.
- **Production-ready** names the production concerns actually supplied and the
  ones still owned by the application. If that list would be long, replace the
  label with the list.

Qualifiers expire when the code changes. Check current source and tests before
preserving one merely because it appears in a protected or familiar line.

## Economy without hiding limits

Put the decisive boundary beside the claim. Do not announce “zero
configuration,” add a dependency note, add an environment-variable section,
then add an “Important” qualification. Replace the opening claim with the
narrow truth and keep only caveats that change setup or failure handling.

Avoid defensive piles of `may`, `can`, `typically`, and `in some cases`. State
the supported path first, then one consolidated boundary. If multiple limits
lead to different decisions, use a table or split the tasks.

## Correctness outranks protected wording

Protect the semantic job of a strong line—its claim, mechanism, boundary, or
voice—not its exact wording. Exact wording never outranks current behavior.
When code makes a brand claim stale, edit or delete the line and preserve its
useful job elsewhere. Historical articles may retain dated voice, but current
landing pages, READMEs, and generated references must not inherit stale claims
from them.

## Rhetorical exceptions

An editor may keep a rhetorical line that does not follow the default sequence
only when the adjudication record names all four items:

1. **Audience:** who benefits from the compression or play.
2. **Evidence:** the nearby code, measurements, or explanation that earns it.
3. **Scope:** where the exception applies and where it must not be reused.
4. **Named editor:** the person accepting the tradeoff.

An exception must live durably in `house-voice-samples.yml` or the future
semantic-anchor ledger, and must include an evidence locator, review date, and
re-review trigger. A change description may link to that durable record; it
may never replace the record. An exception approves only the rhetorical form.
It never approves a factual claim or allows correctness to age without review.
Exceptions are revisited when their evidence, audience, scope, or named trigger
changes. They do not create a reusable slogan.

## Review

Use [`house-voice-samples.yml`](house-voice-samples.yml) to calibrate edits.
Two reviewers should classify a proposed line independently as `KEEP technical`,
`KEEP voice`, `EDIT`, or `DELETE`, then adjudicate disagreements. A disagreement
should refine a decision rule or exception record, not produce a banned-word
list. Samples are observed inputs, not protected snapshots: mark current copy
`present`; after an `EDIT` or `DELETE`, mark it `resolved`, name the change that
resolved it, and confirm the stale excerpt is gone; mark an irrelevant
historical test `retired` with a reason. Run
`ruby docs/scripts/validate_house_voice_charter.rb` to verify that current
excerpts and the edge-case set remain complete without fossilizing bad copy.
