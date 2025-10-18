# frozen_string_literal: true

require 'spec_helper'
require 'gepa'
require 'gepa/strategies/instruction_proposal'

RSpec.describe GEPA::Strategies::InstructionProposalSignature do
  describe '.prompt_renderer' do
    it 'embeds current instruction and feedback dataset' do
      prompt = described_class.prompt_renderer(
        'current_instruction_doc' => 'Do the task.',
        'dataset_with_feedback' => [
          {
            'Inputs' => { 'question' => 'Q1' },
            'Generated Outputs' => 'A1',
            'Feedback' => 'Needs detail.'
          }
        ]
      )

      expect(prompt).to include('Do the task.')
      expect(prompt).to include('Needs detail.')
    end
  end

  describe '.output_extractor' do
    it 'returns inner fenced block when present' do
      output = "```\nNew instruction\n```"
      expect(described_class.output_extractor(output)).to eq('new_instruction' => 'New instruction')
    end

    it 'strips surrounding fences even when unterminated' do
      output = "```Partial"
      expect(described_class.output_extractor(output)).to eq('new_instruction' => 'Partial')
    end
  end
end
