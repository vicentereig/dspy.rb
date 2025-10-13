# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::Teleprompt::Utils.get_program_with_highest_avg_score' do
  # Create a simple mock program class
  class MockProgram
    attr_reader :id

    def initialize(id)
      @id = id
    end
  end

  describe '.get_program_with_highest_avg_score' do
    let(:program_a) { MockProgram.new('a') }
    let(:program_b) { MockProgram.new('b') }
    let(:program_c) { MockProgram.new('c') }

    it 'returns program with highest average score' do
      # param_score_dict has format: { key => [[score, program, params], ...] }
      param_score_dict = {
        'combo_a' => [[0.8, program_a, { temp: 0.5 }]],
        'combo_b' => [[0.9, program_b, { temp: 0.7 }]],
        'combo_c' => [[0.7, program_c, { temp: 0.3 }]]
      }

      fully_evaled_param_combos = []

      program, mean, key, params = DSPy::Teleprompt::Utils.get_program_with_highest_avg_score(
        param_score_dict,
        fully_evaled_param_combos
      )

      expect(program).to eq(program_b)
      expect(mean).to eq(0.9)
      expect(key).to eq('combo_b')
      expect(params).to eq({ temp: 0.7 })
    end

    it 'calculates average from multiple scores for same combo' do
      param_score_dict = {
        'combo_a' => [
          [0.8, program_a, { temp: 0.5 }],
          [0.9, program_a, { temp: 0.5 }],
          [0.7, program_a, { temp: 0.5 }]
        ],
        'combo_b' => [[0.85, program_b, { temp: 0.7 }]]
      }

      fully_evaled_param_combos = []

      program, mean, key, params = DSPy::Teleprompt::Utils.get_program_with_highest_avg_score(
        param_score_dict,
        fully_evaled_param_combos
      )

      # combo_a average: (0.8 + 0.9 + 0.7) / 3 = 0.8
      # combo_b average: 0.85
      # Should return combo_b with higher mean
      expect(program).to eq(program_b)
      expect(mean).to eq(0.85)
      expect(key).to eq('combo_b')
    end

    it 'skips fully evaluated parameter combos' do
      param_score_dict = {
        'combo_a' => [[0.9, program_a, { temp: 0.5 }]],
        'combo_b' => [[0.8, program_b, { temp: 0.7 }]],
        'combo_c' => [[0.7, program_c, { temp: 0.3 }]]
      }

      # combo_a is already fully evaluated
      fully_evaled_param_combos = ['combo_a']

      program, mean, key, params = DSPy::Teleprompt::Utils.get_program_with_highest_avg_score(
        param_score_dict,
        fully_evaled_param_combos
      )

      # Should skip combo_a and return combo_b (next highest)
      expect(program).to eq(program_b)
      expect(mean).to eq(0.8)
      expect(key).to eq('combo_b')
    end

    it 'returns last valid program when all combos are fully evaluated' do
      param_score_dict = {
        'combo_a' => [[0.9, program_a, { temp: 0.5 }]],
        'combo_b' => [[0.8, program_b, { temp: 0.7 }]]
      }

      # All combos are fully evaluated
      fully_evaled_param_combos = ['combo_a', 'combo_b']

      program, mean, key, params = DSPy::Teleprompt::Utils.get_program_with_highest_avg_score(
        param_score_dict,
        fully_evaled_param_combos
      )

      # Should return last valid program (combo_b based on iteration order)
      expect(program).to eq(program_b)
      expect(mean).to eq(0.8)
      expect(key).to eq('combo_b')
    end

    it 'sorts by mean score in descending order' do
      param_score_dict = {
        'combo_low' => [[0.5, program_c, { temp: 0.3 }]],
        'combo_high' => [[0.95, program_a, { temp: 0.5 }]],
        'combo_mid' => [[0.75, program_b, { temp: 0.7 }]]
      }

      fully_evaled_param_combos = []

      program, mean, key, params = DSPy::Teleprompt::Utils.get_program_with_highest_avg_score(
        param_score_dict,
        fully_evaled_param_combos
      )

      expect(program).to eq(program_a)
      expect(mean).to eq(0.95)
      expect(key).to eq('combo_high')
    end
  end
end
