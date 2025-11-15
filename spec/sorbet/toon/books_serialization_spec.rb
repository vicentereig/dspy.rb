# frozen_string_literal: true

require 'spec_helper'
require 'sorbet-runtime'
require 'sorbet/toon'

module SorbetToonBooksSpec
  class Author < T::Struct
    prop :name, String
    prop :notable_work, String
  end

  class Book < T::Struct
    prop :title, String
    prop :published_year, Integer
    prop :authors, T::Array[Author]
  end
end

RSpec.describe 'Sorbet::Toon.encode book catalogs' do
  Book = SorbetToonBooksSpec::Book
  Author = SorbetToonBooksSpec::Author

  let(:books) do
    [
      Book.new(
        title: 'Distributed Systems',
        published_year: 2014,
        authors: [
          Author.new(name: 'Leslie Lamport', notable_work: 'Paxos'),
          Author.new(name: 'Nancy Lynch', notable_work: 'FLP result')
        ]
      ),
      Book.new(
        title: 'Programming Languages',
        published_year: 2003,
        authors: [
          Author.new(name: 'Benjamin Pierce', notable_work: 'TAPL')
        ]
      )
    ]
  end

  let(:payload) { Sorbet::Toon.encode({ catalog: books }) }

  it 'shows the nested book/author layout in TOON' do
    expect(payload).to eq(<<~TOON.strip)
      catalog[2]:
        - title: Distributed Systems
          published_year: 2014
          authors[2]{name,notable_work}:
            Leslie Lamport,Paxos
            Nancy Lynch,FLP result
        - title: Programming Languages
          published_year: 2003
          authors[1]{name,notable_work}:
            Benjamin Pierce,TAPL
    TOON
  end

  it 'decodes back into hashes with nested author entries' do
    decoded = Sorbet::Toon.decode(payload)
    first_book = decoded['catalog'].first

    expect(first_book['title']).to eq('Distributed Systems')
    expect(first_book['authors'].map { |author| author['name'] }).to contain_exactly(
      'Leslie Lamport',
      'Nancy Lynch'
    )
  end
end
