require 'spec_helper'
require_relative '../../examples/workflow_router'

RSpec.describe SupportRouter do
  let(:message) { "Device sensors stopped reporting since last night's deployment." }
  let(:classifier) { DSPy::Predict.new(RouteSupportTicket) }
  let(:billing_handler) { DSPy::Predict.new(SupportPlaybooks::Billing) }
  let(:technical_handler) { DSPy::Predict.new(SupportPlaybooks::Technical) }
  let(:general_handler) { DSPy::Predict.new(SupportPlaybooks::GeneralEnablement) }

  def build_classification(category)
    RouteSupportTicket.output_struct_class.new(
      category: category,
      confidence: 0.92,
      reason: "Category derived from routing rules"
    )
  end

  def build_playbook(signature_class, summary:)
    signature_class.output_struct_class.new(
      resolution_summary: summary,
      recommended_steps: ["Validate logs", "Escalate to SRE"],
      tags: ["playbook", signature_class.name]
    )
  end

  describe '#call' do
    before do
      allow(billing_handler).to receive(:lm).and_return(double(model_id: 'anthropic/claude-4.5-haiku'))
      allow(technical_handler).to receive(:lm).and_return(double(model_id: 'anthropic/claude-4.5-sonnet'))
      allow(general_handler).to receive(:lm).and_return(double(model_id: 'anthropic/claude-4.5-haiku'))
    end

    it 'routes to the predicted handler and returns a RoutedTicket struct without hitting an LLM' do
      allow(classifier).to receive(:call)
        .with(message: message)
        .and_return(build_classification(TicketCategory::Technical))

      allow(technical_handler).to receive(:call)
        .with(message: message)
        .and_return(build_playbook(SupportPlaybooks::Technical, summary: "Reboot sensors"))

      router = described_class.new(
        classifier: classifier,
        handlers: { TicketCategory::Technical => technical_handler }
      )

      result = router.call(message: message)

      expect(result).to be_a(RoutedTicket)
      expect(result.category).to eq(TicketCategory::Technical)
      expect(result.model_id).to eq('anthropic/claude-4.5-sonnet')
      expect(result.recommended_steps).to include("Validate logs")
    end

    it 'falls back to the configured handler when a category has no specialized predictor' do
      allow(classifier).to receive(:call)
        .with(message: message)
        .and_return(build_classification(TicketCategory::Technical))

      allow(general_handler).to receive(:call)
        .with(message: message)
        .and_return(build_playbook(SupportPlaybooks::GeneralEnablement, summary: "Send knowledge base link"))

      router = described_class.new(
        classifier: classifier,
        handlers: { TicketCategory::General => general_handler },
        fallback_category: TicketCategory::General
      )

      result = router.call(message: message)

      expect(result.category).to eq(TicketCategory::Technical)
      expect(result.model_id).to eq('anthropic/claude-4.5-haiku')
    end

    it 'raises when neither a category nor fallback handler is configured' do
      allow(classifier).to receive(:call)
        .with(message: message)
        .and_return(build_classification(TicketCategory::Billing))

      router = described_class.new(
        classifier: classifier,
        handlers: {}
      )

      expect { router.call(message: message) }.to raise_error(ArgumentError, /Missing handler/)
    end
  end
end
