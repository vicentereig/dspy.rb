# frozen_string_literal: true

require 'sorbet/toon'

RSpec.describe 'Sorbet::Toon.decode' do
  after do
    Sorbet::Toon.reset_config!
  end

  it 'decodes TOON strings back into Ruby primitives' do
    payload = <<~TOON
      person:
        name: Ada
        tags[2]: builder,scientist
    TOON

    result = Sorbet::Toon.decode(payload)

    expect(result).to eq(
      'person' => {
        'name' => 'Ada',
        'tags' => %w[builder scientist]
      }
    )
  end

  it 'obeys strict mode defaults and overrides' do
    payload = <<~TOON
      items[2]:
        - 1

        - 2
    TOON

    expect { Sorbet::Toon.decode(payload) }.to raise_error(Sorbet::Toon::DecodeError)

    expect(
      Sorbet::Toon.decode(payload, strict: false)
    ).to eq('items' => [1, 2])
  end
end
