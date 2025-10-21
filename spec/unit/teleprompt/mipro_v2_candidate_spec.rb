require 'spec_helper'

miprov2_available = begin
  require 'dspy/miprov2'
  require 'dspy/propose/grounded_proposer'
  true
rescue LoadError
  false
end

if miprov2_available
  RSpec.describe DSPy::Teleprompt::MIPROv2, :miprov2 do
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
else
  RSpec.describe 'DSPy::Teleprompt::MIPROv2 candidate selection', :miprov2 do
    it 'skips when MIPROv2 dependencies are unavailable' do
      skip 'MIPROv2 optional dependencies are not installed'
    end
  end
end
