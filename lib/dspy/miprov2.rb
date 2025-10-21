# typed: strict
# frozen_string_literal: true

begin
  require_relative 'miprov2/version'
rescue LoadError
  # In development the version file should be present; in production the gem provides it.
end

require_relative 'optimizers/gaussian_process'
require_relative 'teleprompt/mipro_v2'
