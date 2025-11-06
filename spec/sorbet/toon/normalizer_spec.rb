# frozen_string_literal: true

require 'set'
require 'sorbet-runtime'
require 'sorbet/toon/normalizer'

RSpec.describe Sorbet::Toon::Normalizer do
  module SorbetToonNormalizerSpec
    class Status < T::Enum
      enums do
        Draft = new('draft')
        Final = new('final')
      end
    end

    class Note < T::Struct
      prop :label, String
      prop :weight, T.nilable(Float)
    end

    class Person < T::Struct
      prop :name, String
      prop :age, T.nilable(Integer)
      prop :status, Status
      prop :notes, T::Array[Note]
      prop :tags, T::Array[String], default: []
      prop :metadata, T::Hash[Symbol, T.untyped]
    end
  end

  describe '.normalize' do
    let(:person) do
      SorbetToonNormalizerSpec::Person.new(
        name: 'Ada',
        age: nil,
        status: SorbetToonNormalizerSpec::Status::Draft,
        notes: [
          SorbetToonNormalizerSpec::Note.new(label: 'alpha', weight: 1.5),
          SorbetToonNormalizerSpec::Note.new(label: 'beta', weight: nil)
        ],
        tags: ['builder'],
        metadata: { score: 42, extra: { nested: true } }
      )
    end

    it 'serializes T::Struct instances to hashes with string keys' do
      normalized = described_class.normalize(person)

      expect(normalized).to eq(
        'name' => 'Ada',
        'status' => 'draft',
        'notes' => [
          { 'label' => 'alpha', 'weight' => 1.5 },
          { 'label' => 'beta' }
        ],
        'tags' => ['builder'],
        'metadata' => {
          'score' => 42,
          'extra' => { 'nested' => true }
        }
      )
    end

    it 'skips nil optional fields' do
      normalized = described_class.normalize(person)
      expect(normalized).not_to have_key('age')
    end

    it 'injects _type when include_type_metadata is true' do
      normalized = described_class.normalize(person, include_type_metadata: true)
      expect(normalized['_type']).to eq('Person')
    end

    it 'normalizes sets and arrays recursively' do
      normalized = described_class.normalize(
        {
          values: Set.new([SorbetToonNormalizerSpec::Status::Final, nil, 'plain'])
        }
      )

      expect(normalized['values']).to match_array(['final', nil, 'plain'])
    end

    it 'converts NaN and Infinity to nil' do
      payload = {
        'score' => Float::NAN,
        'max' => Float::INFINITY,
        'min' => -Float::INFINITY,
        'ok' => 1.0
      }

      normalized = described_class.normalize(payload)
      expect(normalized).to eq(
        'score' => nil,
        'max' => nil,
        'min' => nil,
        'ok' => 1.0
      )
    end

    it 'stringifies hash keys' do
      normalized = described_class.normalize({ foo: 'bar', 'baz' => 1 })
      expect(normalized).to eq('foo' => 'bar', 'baz' => 1)
    end
  end
end
