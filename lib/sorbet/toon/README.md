# Sorbet::Toon (Preview)

`sorbet-toon` encodes and decodes [Token-Oriented Object Notation](https://github.com/toon-format/toon), reconstructs Sorbet structs and enums, and supplies the TOON integration used by DSPy.rb. Its public version is pre-1.0, so APIs may change.

See the [package and capability matrix](https://oss.vicente.services/dspy.rb/getting-started/packages/) for canonical preview status and overlap boundaries.

## Prerequisites

- Use a supported Ruby with Bundler.
- Install from RubyGems or a repository checkout before running the example.
- DSPy.rb integration also needs the selected provider adapter and credential.

## Install and Run

Add the gem directly when using the codec without the rest of DSPy.rb:

```ruby
gem "sorbet-toon", "~> 0.1"
```

Save this as `toon_round_trip.rb`:

```ruby
require "sorbet-runtime"
require "sorbet/toon"
# Extensions are enabled automatically when sorbet/toon is required.

class Person < T::Struct
  const :name, String
  const :roles, T::Array[String]
end

person = Person.new(name: "Ada", roles: ["maintainer", "reviewer"])
payload = Sorbet::Toon.encode(person)
decoded = Sorbet::Toon.decode(payload, struct_class: Person)

puts payload
puts decoded.name
```

```bash
bundle install
bundle exec ruby toon_round_trip.rb
```

The command prints the TOON payload and then `Ada`. Requiring `sorbet/toon` enables the `T::Struct` and `T::Enum` extension methods automatically; installing the gem remains a separate step.

## DSPy.rb Integration

DSPy.rb can use TOON for prompt-rendered data:

```ruby
lm = DSPy::LM.new(
  "openai/your-model-id",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  data_format: :toon
)
```

`data_format: :toon` asks the model for TOON and parses the complete response before prediction conversion. It is not provider-native JSON structured output.

## Failure Conditions and Limits

- `Sorbet::Toon::DecodeError` reports malformed payloads, column mismatches, and reconstruction failures.
- Arrays of structs use tabular form only when rows have compatible keys.
- Union reconstruction is more reliable with type metadata enabled. Set it globally with `Sorbet::Toon.configure { |config| config.include_type_metadata = true }` or pass `include_type_metadata: true` to `Sorbet::Toon.encode`.
- Token or prompt-size savings depend on the data shape and the selected model's tokenizer. Compact text does not guarantee better model output.
- The preview API has repository coverage, but callers should pin a compatible version and test round trips for their own types before persisting TOON artifacts.
