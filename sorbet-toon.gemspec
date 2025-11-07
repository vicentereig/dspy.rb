# frozen_string_literal: true

require_relative 'lib/sorbet/toon/version'

Gem::Specification.new do |spec|
  spec.name = 'sorbet-toon'
  spec.version = Sorbet::Toon::VERSION
  spec.authors = ['Vicente Reig Rincón de Arellano']
  spec.email = ['hey@vicente.services']

  spec.summary = 'TOON encode/decode pipeline for Sorbet signatures.'
  spec.description = 'Ruby port of the TOON encoder/decoder used inside DSPy.rb. Provides Sorbet-aware normalization, reconstruction, and prompt-ready helpers so signatures can round-trip through TOON without hand-written serializers.'
  readme_url = 'https://github.com/vicentereig/dspy.rb/blob/main/lib/sorbet/toon/README.md'
  spec.homepage = readme_url
  spec.metadata = (spec.metadata || {}).merge(
    'homepage_uri' => readme_url,
    'documentation_uri' => readme_url
  )
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir[
    'lib/sorbet/toon.rb',
    'lib/sorbet/toon/**/*.rb',
    'lib/sorbet/toon/README.md',
    'LICENSE'
  ].uniq

  spec.require_paths = ['lib']

  spec.add_dependency 'sorbet-runtime', '~> 0.5'
end
