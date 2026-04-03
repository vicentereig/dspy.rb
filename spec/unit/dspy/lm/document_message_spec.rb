# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Document Message Support' do
  describe DSPy::LM::Message do
    it 'formats document content for Anthropic' do
      doc = DSPy::Document.new(url: 'https://example.com/report.pdf')
      message = described_class.new(
        role: described_class::Role::User,
        content: [
          { type: 'text', text: 'Summarize this document.' },
          { type: 'document', document: doc }
        ]
      )

      expect(message.to_anthropic_format).to eq({
        role: 'user',
        content: [
          { type: 'text', text: 'Summarize this document.' },
          {
            type: 'document',
            source: {
              type: 'url',
              url: 'https://example.com/report.pdf'
            }
          }
        ]
      })
    end
  end

  describe DSPy::LM::MessageBuilder do
    it 'builds a multimodal message with a document' do
      builder = described_class.new
      doc = DSPy::Document.new(url: 'https://example.com/report.pdf')

      builder.user_with_document('Summarize this document.', doc)

      messages = builder.messages
      expect(messages.size).to eq(1)
      expect(messages[0].multimodal?).to be true
      expect(messages[0].content).to eq([
        { type: 'text', text: 'Summarize this document.' },
        { type: 'document', document: doc }
      ])
    end
  end
end
