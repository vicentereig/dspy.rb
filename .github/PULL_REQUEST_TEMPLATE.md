## Summary

<!-- What changed, and why? -->

## Verification

<!-- List the tests or checks you ran. -->

<details>
<summary><strong>Public documentation review</strong> — open only for public or historical documentation changes</summary>

Code-only change? Skip this section. Use the paths classified as `public` or
`history` in
[`public-doc-corpus.yml`](https://github.com/vicentereig/dspy.rb/blob/main/docs/editorial/public-doc-corpus.yml)
to decide whether it applies.

### Meaning-changing author self-check

For a meaning-changing documentation edit, complete all five prompts and leave
the typo-only attestation unchecked.

1. **Reader change or decision:** <!-- What can the reader now understand, choose, or do differently? -->
2. **Supporting mechanism, source, or test:** <!-- Link the API, implementation, test, measurement, or dated source. -->
3. **Guarantee and application-owned limit:** <!-- State what is guaranteed, its conditions, and what the application still owns. -->
4. **Public pages and semantic anchors:** <!-- List changed public/history paths plus affected IDs from semantic-anchors.yml, or write exactly: reviewed, none — reason -->
5. **Slogan or portable-claim risk:** <!-- Could a claim travel without its mechanism/boundary or be reused as a framework guarantee? Explain. -->

This author self-check gives the reviewer context; it is not approval.

### Typo-only alternative

Use this path only for spelling, grammar, or punctuation edits that do not
change meaning, headings, links, code, frontmatter, routes, or anchor locators.
It bypasses the five prompts and scanner queue.

- **Pages touched:** <!-- List every public/history path. -->
- [ ] **Typo-only attestation:** I confirm every edit meets the definition above.

If this box is unchecked and public/history documentation changed, complete the
meaning-changing path. If any edit falls outside the definition, the reviewer
must reject the typo-only path.

### Reviewer path check

- [ ] Reviewer verified that the completed path matches the diff.

### Meaning-changing reviewer disposition queue

The reviewer—not the author—owns this PR-local queue. Run the informational
scanner on the exact changed public/history files. Findings are candidates;
zero findings are not required for approval and findings do not create a
subjective CI failure.

| Finding (`path:line`, category/rule) | Disposition (`DELETE`, `EDIT`, `KEEP technical`, or `KEEP voice`) | Rationale or link |
| --- | --- | --- |
| <!-- one reported candidate per row; use “scanner reported none” when empty --> |  |  |

`KEEP voice` must link an existing or newly added durable rhetorical exception
in
[`house-voice-samples.yml`](https://github.com/vicentereig/dspy.rb/blob/main/docs/editorial/house-voice-samples.yml)
with its audience, evidence, evidence locator, scope, named editor, review date,
and re-review trigger. The exception approves rhetorical form only. Prior
approval never makes a new or changed factual claim accurate.

</details>
