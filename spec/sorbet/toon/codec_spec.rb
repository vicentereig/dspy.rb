# frozen_string_literal: true

require 'json'
require 'spec_helper'
require 'sorbet/toon/codec'

module SorbetToonSpec
  FIXTURES_ROOT = File.expand_path('../../fixtures/sorbet_toon', __dir__)
  ENCODE_FIXTURES = Dir.glob(File.join(FIXTURES_ROOT, 'encode', '*.json')).sort.freeze
  DECODE_FIXTURES = Dir.glob(File.join(FIXTURES_ROOT, 'decode', '*.json')).sort.freeze

  module_function

  def encode_options(options)
    return {} unless options

    resolved = {}
    resolved[:indent] = options['indent'] if options.key?('indent')
    resolved[:delimiter] = options['delimiter'] if options.key?('delimiter')

    if options.key?('lengthMarker')
      resolved[:length_marker] = options['lengthMarker'] == '#' ? '#' : false
    end

    resolved
  end
end

RSpec.describe 'Sorbet::Toon::Codec' do
  describe 'encode fixtures' do
    SorbetToonSpec::ENCODE_FIXTURES.each do |fixture_path|
      fixtures = JSON.parse(File.read(fixture_path, encoding: 'UTF-8'))

      context fixtures['description'] do
        fixtures.fetch('tests').each do |test|
          it(test['name']) do
            options = SorbetToonSpec.encode_options(test['options'])

            if test['shouldError']
              expect do
                Sorbet::Toon::Codec.encode(test['input'], **options)
              end.to raise_error(StandardError)
            else
              output = Sorbet::Toon::Codec.encode(test['input'], **options)
              expect(output).to eq(test['expected'])
            end
          end
        end
      end
    end
  end

  describe 'decode fixtures' do
    SorbetToonSpec::DECODE_FIXTURES.each do |fixture_path|
      fixtures = JSON.parse(File.read(fixture_path, encoding: 'UTF-8'))

      context fixtures['description'] do
        fixtures.fetch('tests').each do |test|
          it(test['name']) do
            options = test['options'] || {}

            if test['shouldError']
              expect do
                Sorbet::Toon::Codec.decode(test['input'], **options)
              end.to raise_error(StandardError)
            else
              output = Sorbet::Toon::Codec.decode(test['input'], **options)
              expect(output).to eq(test['expected'])
            end
          end
        end
      end
    end
  end
end
