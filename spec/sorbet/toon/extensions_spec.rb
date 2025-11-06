# frozen_string_literal: true

require 'sorbet-runtime'
require 'sorbet/toon'

RSpec.describe 'Sorbet::Toon extensions' do
  module SorbetToonExtensionsSpec
    class Status < T::Enum
      enums do
        Draft = new('draft')
        Final = new('final')
      end
    end

    class Note < T::Struct
      prop :label, String
      prop :status, Status
    end
  end

  before(:all) do
    Sorbet::Toon.enable_extensions!
  end

  after do
    Sorbet::Toon.reset_config!
  end

  it 'adds #to_toon on structs' do
    note = SorbetToonExtensionsSpec::Note.new(label: 'recap', status: SorbetToonExtensionsSpec::Status::Draft)
    expect(note.to_toon).to eq(Sorbet::Toon.encode(note))
  end

  it 'adds .from_toon on structs' do
    note = SorbetToonExtensionsSpec::Note.new(label: 'recap', status: SorbetToonExtensionsSpec::Status::Final)
    payload = note.to_toon

    decoded = SorbetToonExtensionsSpec::Note.from_toon(payload, include_type_metadata: true)
    expect(decoded).to be_a(SorbetToonExtensionsSpec::Note)
    expect(decoded.status).to eq(SorbetToonExtensionsSpec::Status::Final)
  end

  it 'adds helpers to enums' do
    toon_literal = SorbetToonExtensionsSpec::Status::Draft.to_toon
    decoded = SorbetToonExtensionsSpec::Status.from_toon(toon_literal)

    expect(decoded).to eq(SorbetToonExtensionsSpec::Status::Draft)
  end
end
