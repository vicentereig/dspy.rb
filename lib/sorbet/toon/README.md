# Sorbet::Toon (alpha)

Sorbet::Toon brings the official [TOON data format](https://github.com/toon-format/toon) to Ruby. It lets DSPy.rb—and any Sorbet-powered code—render compact prompt contracts and parse LLM responses using the same `DSPy::Signature` metadata that already powers JSON/BAML. Think of it as “typed Markdown tables for LLMs”: humans stay oriented, tokens stay low, and structs survive the round-trip.

> **Status:** Codec + normalization + reconstruction + TOON mixins are merged. DSPy adapter + docs/tools are landing now; expect sharp edges until v0.1.0.

---

## Install & Load

Until the gem ships on RubyGems, point Bundler at the repo:

```ruby
# Gemfile
gem 'sorbet-toon', path: '.'   # replace with "~> 0.1" once published
```

```ruby
require 'sorbet-runtime'
require 'sorbet/toon'
```

Optional convenience:

```ruby
Sorbet::Toon.enable_extensions!
# T::Struct classes gain #to_toon / .from_toon
# T::Enum classes gain #to_toon / .from_toon
```

---

## Encode + Decode Walkthrough

```ruby
class Source < T::Struct
  prop :name, String
  prop :url, String
  prop :notes, T.nilable(String)
end

class ResearchSignature < DSPy::Signature
  input  { const :query, String }
  output do
    const :summary, String
    const :sources, T::Array[Source]
  end
end

payload = ResearchSignature.output_struct_class.new(
  summary: 'Recent AI papers',
  sources: [
    Source.new(name: 'Anthropic', url: 'https://anthropic.com', notes: nil),
    Source.new(name: 'OpenAI', url: 'https://openai.com', notes: 'top pick')
  ]
)

toon = Sorbet::Toon.encode(payload, signature: ResearchSignature, role: :output)
# summary: Recent AI papers
# sources[2]{name,url,notes}:
#   Anthropic,https://anthropic.com,
#   OpenAI,https://openai.com,"top pick"

rehydrated = Sorbet::Toon.decode(toon, signature: ResearchSignature, role: :output)
rehydrated.summary        # => "Recent AI papers"
rehydrated.sources.last.notes  # => "top pick"
```

### Mixins (optional)

```ruby
Sorbet::Toon.enable_extensions!

toon_blob = payload.to_toon(include_type_metadata: true)
# => struct instances gain #to_toon

decoded = Source.from_toon(%(- name: Ada\n  url: https://example.com))
# => class methods .from_toon / enums too
```

### Config knobs

```ruby
Sorbet::Toon.configure do |config|
  config.indent = 4
  config.delimiter = Sorbet::Toon::Constants::PIPE
  config.include_type_metadata = true
end

Sorbet::Toon.encode(value, delimiter: Sorbet::Toon::Constants::TAB) # per-call override
```

---

## Signature Formatter & DSPy Adapter

`Sorbet::Toon::SignatureFormatter` inspects `DSPy::Signature` definitions to produce human-friendly TOON guidance (field order, optional notes, tabular hints). `DSPy::Schema::SorbetToonAdapter` wires that into prompts:

```ruby
DSPy::Prompt.from_signature(
  ResearchSignature,
  schema_format: :toon,   # show TOON-friendly schema guidance
  data_format:   :toon    # render inputs/outputs as TOON
)
```

System prompts now read:

```
Your input schema fields (TOON order) are:
- query (String) — Research question

Your output schema fields (TOON order) are:
- summary (String) — Key findings
- sources (Array<Source>)
    • Tabular columns: name, url, notes
```

User prompts embed real TOON values:

```
## Input Values
```toon
query: recent diffusion models
```
```

LLMs reply with:

```
## Output values
```toon
summary: Diffusion models are accelerating image synthesis...
sources[2]{name,url,notes}:
  Anthropic,https://anthropic.com,
  OpenAI,https://openai.com,"top pick"
```

Decoding uses the same adapter:

```ruby
DSPy::Schema::SorbetToonAdapter.parse_output(ResearchSignature, toon_blob)
# => Hash with string keys (Predict converts to structs automatically)
```

`DSPy::LM.new(..., data_format: :toon)` enables automatic TOON parsing inside `DSPy::LM#chat`, so `Predict` keeps receiving hashes/structs without custom code.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `LoadError: cannot load such file -- sorbet/toon` | Ensure the gem is installed (via repo path or RubyGems) *before* loading DSPy. |
| LLM responds with narrative text instead of TOON | Double-check the system prompt includes the TOON instructions. `data_format: :toon` forces `Prompt#render_user_prompt` to embed a ```toon``` block and explicitly asks for a TOON reply. |
| `Sorbet::Toon::DecodeError` complaining about columns | Arrays of structs become tabular if every row shares the same keys. Make sure your struct props/names align and optional fields are either present in every row or omitted entirely. |
| Need to include `_type` discriminator | `Sorbet::Toon.configure { |c| c.include_type_metadata = true }` or per-call option `Sorbet::Toon.encode(value, include_type_metadata: true)`. Useful for union/variant decoding. |
| Optional fields showing as `null` | Normalizer already elides fully optional Sorbet props when nil. If you see `null`, the prop likely isn’t declared `T.nilable` or lacks a default. |

---

## Roadmap

- [x] Codec + fixtures ported from the TypeScript reference.
- [x] Sorbet-aware normalizer, decoder reconstruction, struct/enum mixins.
- [x] Gem scaffold (`sorbet-toon.gemspec`, version file, README).
- [ ] Signature formatter + DSPy adapter (data_format: :toon) **← in progress**
- [ ] Full llms-full README (copy-pastable recipes + troubleshooting deep dive).
- [ ] Integration specs mirroring the BAML suite.

Feedback / bugs → issues or `hey@vicente.services`. Thank you!
