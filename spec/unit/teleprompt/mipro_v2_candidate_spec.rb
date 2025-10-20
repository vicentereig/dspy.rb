require 'spec_helper'
require 'dspy/teleprompt/mipro_v2'
require 'dspy/propose/grounded_proposer'

RSpec.describe DSPy::Teleprompt::MIPROv2 do
  subject(:optimizer) { described_class.new(metric: nil) }

  describe '#generate_candidate_configurations' do
    it 'deduplicates instruction-only candidates with identical text' do
      proposal_result = DSPy::Propose::GroundedProposer::ProposalResult.new(
        candidate_instructions: [
          'Check for ADE mentions and respond with 0 or 1.',
          'Check for ADE mentions and respond with 0 or 1.'
        ],
        analysis: {},
        metadata: {},
        predictor_instructions: {
          0 => [
            'Check for ADE mentions and respond with 0 or 1.',
            'Check for ADE mentions and respond with 0 or 1.'
          ]
        }
      )

      candidates = optimizer.send(:generate_candidate_configurations, proposal_result, {})

      instruction_candidates = candidates.select do |candidate|
        candidate.type == DSPy::Teleprompt::CandidateType::InstructionOnly
      end
      instructions = instruction_candidates.map(&:instruction)

      expect(instructions).to eq(instructions.uniq)
    end
  end
end
