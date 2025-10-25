# typed: false
# frozen_string_literal: true

begin
  require 'dspy/gepa'
rescue LoadError => e
  raise LoadError, <<~MSG
    DSPy::Teleprompt::GEPA has moved to the optional 'dspy-gepa' gem.
    Add `gem 'dspy-gepa'` (and set DSPY_WITH_GEPA=1 when bundling from the monorepo) to use GEPA.
    Original error: #{e.message}
  MSG
end
