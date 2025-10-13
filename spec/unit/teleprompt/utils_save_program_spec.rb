# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'tmpdir'

RSpec.describe 'DSPy::Teleprompt::Utils.save_candidate_program' do
  # Mock program class with save method
  class MockSaveableProgram
    attr_reader :id

    def initialize(id)
      @id = id
    end

    def save(path)
      File.write(path, JSON.generate({ id: @id }))
    end
  end

  describe '.save_candidate_program' do
    let(:program) { MockSaveableProgram.new('test_program') }

    it 'returns nil when log_dir is nil' do
      result = DSPy::Teleprompt::Utils.save_candidate_program(program, nil, 1)
      expect(result).to be_nil
    end

    it 'creates evaluated_programs directory when it does not exist' do
      Dir.mktmpdir do |tmpdir|
        eval_dir = File.join(tmpdir, 'evaluated_programs')
        expect(Dir.exist?(eval_dir)).to be(false)

        DSPy::Teleprompt::Utils.save_candidate_program(program, tmpdir, 1)

        expect(Dir.exist?(eval_dir)).to be(true)
      end
    end

    it 'saves program with trial number' do
      Dir.mktmpdir do |tmpdir|
        path = DSPy::Teleprompt::Utils.save_candidate_program(program, tmpdir, 5)

        expect(path).to eq(File.join(tmpdir, 'evaluated_programs', 'program_5.json'))
        expect(File.exist?(path)).to be(true)
      end
    end

    it 'saves program with trial number and note' do
      Dir.mktmpdir do |tmpdir|
        path = DSPy::Teleprompt::Utils.save_candidate_program(program, tmpdir, 3, note: 'best')

        expect(path).to eq(File.join(tmpdir, 'evaluated_programs', 'program_3_best.json'))
        expect(File.exist?(path)).to be(true)
      end
    end

    it 'calls program.save with correct path' do
      Dir.mktmpdir do |tmpdir|
        expect(program).to receive(:save).with(File.join(tmpdir, 'evaluated_programs', 'program_7.json'))
        DSPy::Teleprompt::Utils.save_candidate_program(program, tmpdir, 7)
      end
    end

    it 'returns save path' do
      Dir.mktmpdir do |tmpdir|
        path = DSPy::Teleprompt::Utils.save_candidate_program(program, tmpdir, 2)

        expect(path).to be_a(String)
        expect(File.exist?(path)).to be(true)
      end
    end
  end
end
