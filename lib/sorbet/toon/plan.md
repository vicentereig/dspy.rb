# Sorbet::Toon Plan (Living Document)

_Last updated: November 6, 2025 (afternoon PT)._

This file tracks the end-to-end plan for the `Sorbet::Toon` implementation that will live under `lib/sorbet/toon`. Update this document as milestones land or priorities shift. Treat it as the source of truth for work-in-progress and for future contributors.

---

## Goal

Enable DSPy.rb to express `DSPy::Signature` contracts in TOON format—both for prompt rendering (encode runtime values) and for parsing LLM responses (decode back into Sorbet structs). Signatures remain the anchor: the same type metadata that powers JSON/BAML schemas should power TOON data formatting.

---

## Deliverables Overview

- **Gem packaging**: New `sorbet-toon` gem exposing `Sorbet::Toon.encode` and `Sorbet::Toon.decode`, along with optional struct/enum mixins.
- **TOON codec ports**: Bottom-up Ruby ports of the official TypeScript encode/decode pipelines from <https://github.com/toon-format/toon/tree/main/packages/toon>.
- **Signature-aware formatter**: Helpers applying signature field ordering, optional field elision, and tabular detection for array outputs.
- **DSPy integration**: Adapter under `lib/dspy/schema` enabling `data_format: :toon` in `DSPy::LM` and prompt/response handling.
- **Documentation**: Rich README under `lib/sorbet/toon/README.md` (include concrete, LLM-ready examples akin to an `llms-full.txt` appendix).

---

## Current Status — November 6, 2025

- ✅ **Codec core landed:** `lib/sorbet/toon/codec.rb`, `constants.rb`, `encode/*`, `decode/*`, and `shared/*` now mirror the upstream TypeScript implementation and pass fixture-based expectations.
- ✅ **Fixture suite imported:** `spec/fixtures/sorbet_toon/{encode,decode}/*.json` plus `spec/sorbet/toon/codec_spec.rb` exercise the Ruby port (requires Bundler `2.6.5` locally before `bundle exec rspec` will run).
- ✅ **Surface API foundation:** Normalizer + encode/decode wrappers/config landed, along with struct/enum mixins, signature-aware reconstruction, and opt-in extensions (`Sorbet::Toon.enable_extensions!`).
- 🆕 **Normalizer & specs landed:** `lib/sorbet/toon/normalizer.rb` plus `spec/sorbet/toon/normalizer_spec.rb` cover Sorbet struct/enum flattening, optional field elision, `_type` toggling, and NaN/Infinity handling.
- ⚙️ **Top-level encode/decode wrappers + config:** `lib/sorbet/toon/{config,encoder,decoder,reconstructor}.rb` expose `Sorbet::Toon.encode/decode`, global configuration, and struct rehydration (`spec/sorbet/toon/{encoder,decoder,signature_reconstruction}_spec.rb`).
- ✍️ **Signature formatter + DSPy adapter:** `lib/sorbet/toon/signature_formatter.rb` and `lib/dspy/schema/sorbet_toon_adapter.rb` now power `schema_format: :toon` guidance plus `data_format: :toon` prompts/decoding in `DSPy::Prompt` and `DSPy::LM`.
- 📦 **Gem skeleton + README:** `sorbet-toon.gemspec`, `lib/sorbet/toon/version.rb`, and an llms-full README (`lib/sorbet/toon/README.md`) unblock packaging/documentation work.
- ⚠️ **Dev friction:** `bundle exec rspec` currently fails unless the environment installs Bundler `2.6.5` (`gem install bundler:2.6.5`), so call this out in setup docs.

---

## File Layout (target)

```
lib/
  sorbet/
    toon.rb
    toon/
      version.rb
      config.rb
      errors.rb
      normalizer.rb
      encoder.rb
      decoder.rb
      signature_formatter.rb
      struct_extensions.rb
      enum_extensions.rb
      encode/
        encoders.rb
        normalize.rb
        primitives.rb
        writer.rb
      decode/
        decoders.rb
        parser.rb
        scanner.rb
        validation.rb
      shared/
        string_utils.rb
        literal_utils.rb
        validation.rb
      fixtures/
        *.json
        *.toon
lib/dspy/schema/
  sorbet_toon_adapter.rb
sorbet-toon.gemspec
lib/sorbet/toon/README.md  # written in llms-full style; no separate llms-full.txt
lib/sorbet/toon/plan.md  # this file
```

---

## Detailed Work Breakdown

### 1. Scaffold the Gem

- Use `bundle gem sorbet-toon --test=rspec` (or manual scaffold) to create gem structure in repo root.
- Ensure `.gemspec` references `lib/sorbet/toon/version.rb`.
- Dependencies:
  - `sorbet-runtime` (for type metadata + runtime signatures).
  - Development: `rspec`, `rubocop`, `sorbet`, `yard` (optional).
- CI TODO: hook into existing GitHub Actions (re-use patterns from `sorbet-baml` repo at `/tmp/sorbet-baml/.github/workflows` if required).

### 2. Port TOON Encoder & Decoder (TypeScript ➜ Ruby)

_Status: Completed on November 6, 2025 — encoder/decoder, normalize, writer, parser, scanner, validation, and shared utilities now live under `lib/sorbet/toon` with parity fixtures._

Reference TypeScript sources under `/tmp/toon-format/packages/toon/src`:

| TS File | Planned Ruby Port |
| ------- | ----------------- |
| `encode/encoders.ts` | `lib/sorbet/toon/encode/encoders.rb` |
| `encode/normalize.ts` | `lib/sorbet/toon/encode/normalize.rb` |
| `encode/primitives.ts` | `lib/sorbet/toon/encode/primitives.rb` |
| `encode/writer.ts` | `lib/sorbet/toon/encode/writer.rb` |
| `decode/decoders.ts` | `lib/sorbet/toon/decode/decoders.rb` |
| `decode/parser.ts` | `lib/sorbet/toon/decode/parser.rb` |
| `decode/scanner.ts` | `lib/sorbet/toon/decode/scanner.rb` |
| `decode/validation.ts` | `lib/sorbet/toon/decode/validation.rb` |
| `shared/string-utils.ts`, `shared/literal-utils.ts`, `shared/validation.ts` | `lib/sorbet/toon/shared/*.rb` modules |

Steps:
1. Implement Ruby equivalents preserving algorithm structure for both encode (normalization, primitive formatting, `LineWriter`) and decode (`LineCursor`, array header parsing, strict validation).
2. Expose internal codec API (e.g., `Sorbet::Toon::Codec.encode/decode`) returning plain Ruby structures.
3. Maintain parity with upstream TypeScript by regularly syncing fixtures/tests; no external gem dependency.
4. Tests: port TypeScript fixtures from `/tmp/toon-format/packages/toon/test/{encode,decode}.test.ts` and associated fixture JSON files.

### 3. Normalizer (Sorbet-aware Value Expansion)

_Status: Core normalizer shipped November 6 with T::Struct/T::Enum handling, optional `_type` injection, and spec coverage; signature-sensitive ordering hooks still pending._

Purpose: Convert runtime values (struct instances, enums, arrays, etc.) into plain Ruby primitives that TOON can encode.

Responsibilities:
- Accept any Ruby object plus optional `signature` and `role` (`:input` or `:output`).
- For `T::Struct`:
  - Iterate `klass.props` in declaration order (check `sorbet-runtime` docs and existing logic in `lib/dspy/type_serializer.rb`).
  - Skip nil values when `prop_info[:fully_optional]` true.
  - Convert nested structs/enums recursively.
  - Optionally inject `_type` field if configured in `Sorbet::Toon::Config`.
- For `T::Enum`: call `.serialize`.
- For arrays/sets/maps: map and normalise (mirror `packages/toon/src/encode/normalize.ts`).
- For primitives: ensure `Float::NAN`, `Infinity` → `nil` (TOON uses `null`).
- Provide diagnostics when arrays of structs have mismatched keys (so we understand when TOON must fall back to list mode).

Deliverable: `Sorbet::Toon::Normalizer.normalize(value, signature: nil, role: :output)`.

### 4. Encoder

_Status: Shared encoder wrapper + config plus struct/enum mixins now live; future work is ergonomics (prompt helpers, logging, DSPy hooks)._

Relies on in-repo TypeScript port (`Sorbet::Toon::Codec.encode`).

- `Sorbet::Toon.encode(value, signature: nil, role: :output, **options)`:
  1. Normalize value (`Normalizer.normalize`).
  2. Pass to codec encoder with options resolved from `Sorbet::Toon::Config`.
  3. Provide helpful errors/warnings if normalization outputs non-tabular arrays (log via DSPy logger hook later).
- Provide convenience mixins:
  - `Sorbet::Toon::StructExtensions#to_toon(options = {})`.
  - `Sorbet::Toon::EnumExtensions#to_toon`.
  - These should be opt-in via `Sorbet::Toon.enable_extensions!` to avoid polluting all structs automatically.

### 5. Decoder & Reconstruction

_Status: Wrapper exposes `Sorbet::Toon.decode`, including strict defaults, overrides, Sorbet signature reconstruction via `Reconstructor`, and DSPy adapter parsing._

- `Sorbet::Toon.decode(toon_string, signature: nil, role: :output)`:
  1. Call codec decoder → plain Ruby structure.
  2. If signature provided, reconstruct Sorbet types:
     - For output role, instantiate `signature.output_struct_class.new(**attrs)`.
     - Convert string keys to symbols as needed (respect signature prop names).
     - Coerce enums: map strings back to `T::Enum` members via `.deserialize` or `.values.find`.
     - Apply defaults from `signature.output_field_descriptors` when fields missing.
  3. Return plain structure if no signature given (still useful for general encode/decode).
- Provide inverse convenience: `MyStruct.from_toon(string)` when extensions enabled.

### 6. Signature Formatter
_Status: Implemented November 6 — `lib/sorbet/toon/signature_formatter.rb` describes fields, optionality, and tabular hints for prompt rendering._

### 7. DSPy Integration Adapter
_Status: `lib/dspy/schema/sorbet_toon_adapter.rb` now renders/decodes TOON inputs/outputs, `DSPy::Prompt` supports `data_format: :toon`, and `DSPy::LM` parses TOON responses (non-structured-output path only)._

### 8. Documentation

- `lib/sorbet/toon/README.md` must:
  - Follow an llms-full narrative style (step-by-step, copy-pastable examples); no separate `llms-full.txt`.
  - Installation instructions (`gem 'sorbet-toon'`).
  - Signature definition example:
    ```ruby
    class ResearchResult < DSPy::Signature
      input { const :query, String }
      output do
        const :summary, String
        const :sources, T::Array[Source]
      end
    end
    ```
  - Encoding example showing TOON output (tabular for arrays).
  - Decoding example reconstructing structs.
  - DSPy integration snippet (`DSPy.configure { |c| c.lm = DSPy::LM.new(..., data_format: :toon) }`).
  - Troubleshooting (arrays with mixed keys, unsupported types, strict mode errors).
  - Explicit guidance: TOON targets enhanced prompting only; structured outputs/tool schemas remain JSON-native.

### 9. Testing Strategy

_Status: Codec fixtures + spec landed; normalizer + encode/decode + reconstruction/mixin specs added; TOON-specific prompt/adapter integration specs added; DSPy e2e tests still expanding._

1. **Unit tests (RSpec)**:
   - `spec/sorbet/toon/codec_spec.rb` – parity with upstream encode/decode fixtures.
   - `spec/sorbet/toon/normalizer_spec.rb` – cover primitives, structs, enums, optional fields.
   - `spec/sorbet/toon/encoder_spec.rb` – verify TOON output vs expected strings (use fixtures).
   - `spec/sorbet/toon/decoder_spec.rb` – decode valid/invalid TOON (assert errors for indentation issues, mismatched counts).
   - `spec/sorbet/toon/signature_formatter_spec.rb` – ensure ordering matches signature definition.
2. **Integration tests**:
   - Round-trip signature scenario: instantiate signature, encode inputs/outputs, decode back, compare to original struct instances (taking defaults into account).
   - Mirror existing DSPy integration spec for BAML (`spec/integration/baml_schema_format_spec.rb`) with TOON counterpart.
3. **Fixture management**:
   - Create `lib/sorbet/toon/fixtures` with canonical TOON/JSON pairs reused across tests.
   - Document fixture sources (e.g., imported from `packages/toon/test/fixtures/{encode,decode}/*.json`).

### 10. Release Process

- Version file `lib/sorbet/toon/version.rb` controls semantic version.
- Add `rake release` tasks similar to `sorbet-baml` (see `/tmp/sorbet-baml/Rakefile`).
- Before release:
  - Ensure `bundle exec rspec`, `bundle exec srb tc`, and `bundle exec rubocop` pass.
  - Update README + CHANGELOG.
  - Tag and push `v0.1.0`.
- DSPy gemspec: add dependency `spec.add_dependency "sorbet-toon", "~> 0.1"`.

---

## Dependencies & External References

- TypeScript TOON reference implementation: `/tmp/toon-format/packages/toon/src` and `README.md`.
- Existing Sorbet integration patterns:
  - `lib/dspy/type_serializer.rb`
  - `lib/dspy/prompt.rb`
  - `lib/dspy/lm/json_strategy.rb`
  - `lib/sorbet_baml/*` for extension patterns.
- Potential JSON fallback logic: `DSPy::LM#parse_response` (needs update to branch on TOON).

---

## Open Questions / Decision Log

1. **In-repo codec maintenance**: Entire encode/decode stack lives here; establish process to sync with upstream TypeScript changes (track upstream commits, update fixtures).
2. **Structured outputs compatibility**: TOON is for enhanced prompting only; structured outputs tooling stays JSON-native and should be clearly documented as such.
3. **Field defaults**: Confirm `signature.output_field_descriptors` exposes defaults; if not, fall back to Sorbet struct defaults via `props`.
4. **Performance**: Large tabular arrays may require streaming; monitor codec encoding performance with big datasets.
5. **Future refactor**: After parity and solid tests, revisit the decoder/encoder using a formal grammar + lexer/parser + AST to simplify maintenance. Extract grammar from the TypeScript implementation before attempting the redesign.

---

## Progress Checklist

> **Testing discipline:** Each task should follow TDD—write or adapt specs first, watch them fail, then implement to make them pass. Use `rbenv` to select the Ruby version (matching DSPy’s baseline) before running specs (`rbenv exec bundle exec rspec`, etc.).

Use `[ ]` → `[x]` as tasks complete.

- [x] Scaffold gem + gemspec.
- [x] Port TOON encoder/decoder (Ruby).
- [x] Implement normalizer.
- [x] Implement encoder + mixins.
- [x] Implement decoder + reconstruction.
- [x] Signature formatter utilities.
- [x] DSPy adapter stub (`lib/dspy/schema/sorbet_toon_adapter.rb`).
- [ ] Unit/integration tests.
- [x] Documentation (README, llms-full.txt).
- [ ] Release 0.1.0 & integrate into DSPy.

---

## Immediate Next Steps

1. **Predict/LM end-to-end specs:** Add higher-level tests (Predict → Prompt → LM mock → adapter) to ensure TOON formatting stays stable across demos/ReAct/MIPRO flows.
2. **Error reporting & logging:** Surface clearer `Sorbet::Toon` errors inside DSPy (e.g., code-fence mismatch, tabular column mismatches) and add optional logging hooks before the v0.1.0 release.

---

## Maintenance Notes

- Keep this plan updated after each significant commit (decoder merged, adapter wired, etc.).
- Periodically sync with upstream TypeScript implementation (`toon-format/toon`) to keep codec behavior aligned.
- Track issues/PRs referencing this plan in GitHub to maintain traceability.
