# Sorbet::Toon (alpha)

Sorbet::Toon brings the official [TOON data format](https://github.com/toon-format/toon) to Ruby. The goal is to let DSPy.rb—and any Sorbet app—render compact prompt contracts and parse LLM responses using the same `DSPy::Signature` metadata you already maintain for JSON/BAML.

> **Status:** codec + Sorbet-aware normalization/rehydration are in place. CLI/docs/tooling are evolving quickly; expect sharp edges until v0.1 ships.

## Installation

Add the gem to your application (the code already lives inside `dspy.rb`, but the gem will be published separately):

```ruby
# Gemfile
gem 'sorbet-toon', path: '.' # until released to RubyGems
```

## Quick Start

```ruby
require 'sorbet-runtime'
require 'sorbet/toon'

class Source < T::Struct
  prop :name, String
  prop :url, String
end

class ResearchSignature < DSPy::Signature
  input { const :query, String }
  output do
    const :summary, String
    const :sources, T::Array[Source]
  end
end

payload = ResearchSignature.output_struct_class.new(
  summary: 'Recent AI papers',
  sources: [
    Source.new(name: 'Anthropic', url: 'https://anthropic.com'),
    Source.new(name: 'OpenAI', url: 'https://openai.com')
  ]
)

toon = Sorbet::Toon.encode(payload)
# =>
# summary: Recent AI papers
# sources[2]{name,url}:
#   Anthropic,https://anthropic.com
#   OpenAI,https://openai.com

rehydrated = Sorbet::Toon.decode(toon, signature: ResearchSignature, role: :output)
rehydrated.summary # => "Recent AI papers"
```

### Struct / Enum helpers

Opt-in helpers keep call sites terse:

```ruby
Sorbet::Toon.enable_extensions!

toon = payload.to_toon(include_type_metadata: true)
back  = ResearchSignature.output_struct_class.from_toon(toon)
```

### Config knobs

```ruby
Sorbet::Toon.configure do |config|
  config.indent = 4
  config.delimiter = Sorbet::Toon::Constants::PIPE
  config.include_type_metadata = true
end
```

Per-call overrides (`Sorbet::Toon.encode(value, delimiter: ...)`) win over global config.

## Roadmap

- [x] Port encoder/decoder + fixtures from TypeScript reference.
- [x] Sorbet-aware normalizer + reconstruction, struct/enum mixins.
- [ ] Signature formatter + DSPy adapter (`data_format: :toon`).
- [ ] README deep dive (llms-full narrative) before v0.1 release.

Feedback welcome—open an issue or ping `hey@vicente.services`.
