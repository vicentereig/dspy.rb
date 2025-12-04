# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Teleprompt::MIPROv2 require paths' do
  let(:mipro_v2_file) { File.join(__dir__, '../../../../lib/dspy/teleprompt/mipro_v2.rb') }

  describe 'require statements' do
    it 'uses require instead of require_relative for cross-gem dependencies' do
      content = File.read(mipro_v2_file)

      # These files are in the main dspy gem, not dspy-miprov2
      # So they should use require (which uses $LOAD_PATH) not require_relative
      cross_gem_requires = [
        'teleprompter',
        'utils',
        'instruction_updates',
        '../propose/grounded_proposer'
      ]

      cross_gem_requires.each do |file|
        # Should NOT have require_relative for these files
        expect(content).not_to include("require_relative '#{file}'"),
          "Expected mipro_v2.rb to NOT use require_relative for '#{file}' (cross-gem dependency)"
      end

      # Should use require with full path instead
      expected_requires = [
        "require 'dspy/teleprompt/teleprompter'",
        "require 'dspy/teleprompt/utils'",
        "require 'dspy/teleprompt/instruction_updates'",
        "require 'dspy/propose/grounded_proposer'"
      ]

      expected_requires.each do |expected|
        expect(content).to include(expected),
          "Expected mipro_v2.rb to include '#{expected}' for cross-gem compatibility"
      end
    end

    it 'can use require_relative for files within the same gem' do
      content = File.read(mipro_v2_file)

      # gaussian_process.rb IS in the dspy-miprov2 gem, so require_relative is fine
      expect(content).to include("require_relative '../optimizers/gaussian_process'"),
        "Expected mipro_v2.rb to use require_relative for gaussian_process (same gem)"
    end
  end
end
