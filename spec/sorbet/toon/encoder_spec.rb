# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'
require 'sorbet/toon'

RSpec.describe 'Sorbet::Toon.encode' do
  module SorbetToonEncoderSpec
    class Note < T::Struct
      prop :label, String
      prop :weight, T.nilable(Float)
    end

    class Person < T::Struct
      prop :name, String
      prop :notes, T::Array[Note]
      prop :tags, T::Array[String]
    end
  end

  let(:person) do
    SorbetToonEncoderSpec::Person.new(
      name: 'Ada',
      notes: [
        SorbetToonEncoderSpec::Note.new(label: 'alpha', weight: 1.5),
        SorbetToonEncoderSpec::Note.new(label: 'beta', weight: nil)
      ],
      tags: %w[builder scientist]
    )
  end

  after do
    Sorbet::Toon.reset_config!
  end

  it 'normalizes Sorbet structs before encoding' do
    manual = Sorbet::Toon::Codec.encode(
      Sorbet::Toon::Normalizer.normalize(person)
    )

    expect(Sorbet::Toon.encode(person)).to eq(manual)
  end

  it 'injects type metadata when requested' do
    payload = Sorbet::Toon.encode(person, include_type_metadata: true)
    decoded = Sorbet::Toon::Codec.decode(payload)

    expect(decoded['_type']).to eq('Person')
  end

  it 'honors per-call delimiter overrides' do
    payload = Sorbet::Toon.encode(
      { tags: %w[alpha beta] },
      delimiter: Sorbet::Toon::Constants::PIPE
    )

    expect(payload).to include('tags[2|]: alpha|beta')
  end

  it 'honors global configuration defaults' do
    Sorbet::Toon.configure do |config|
      config.delimiter = Sorbet::Toon::Constants::PIPE
    end

    payload = Sorbet::Toon.encode({ tags: %w[a b] })
    expect(payload).to include('[2|]')
  end
end
