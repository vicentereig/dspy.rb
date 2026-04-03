# frozen_string_literal: true

require 'spec_helper'
require 'dspy/ruby_llm'
require_relative '../support/test_documents'

RSpec.describe 'Predict with Document Integration', :vcr do
  let(:anthropic_model) { 'claude-sonnet-4-20250514' }
  let(:ruby_llm_anthropic_model) { 'claude-sonnet-4' }
  let(:allow_live_recording) { ENV['DSPY_RUN_LIVE_DOCUMENT_INTEGRATION'] == '1' }

  def cassette_exists?(name)
    File.exist?(File.join(__dir__, '..', 'vcr_cassettes', "#{name}.yml"))
  end

  describe 'document analysis via raw_chat' do
    it 'analyzes a PDF document via raw_chat', vcr: { cassette_name: 'predict_with_document/raw_chat_anthropic' } do
      unless cassette_exists?('predict_with_document/raw_chat_anthropic') ||
             (allow_live_recording && !ENV['ANTHROPIC_API_KEY'].to_s.strip.empty?)
        skip 'Requires recorded cassette or DSPY_RUN_LIVE_DOCUMENT_INTEGRATION=1 with ANTHROPIC_API_KEY'
      end

      lm = DSPy::LM.new("anthropic/#{anthropic_model}", api_key: ENV['ANTHROPIC_API_KEY'])
      doc = DSPy::Document.new(
        base64: TestDocuments.create_base64_pdf(text: "Revenue: $1.2M. Growth: 15%."),
        content_type: 'application/pdf'
      )

      response = lm.raw_chat do |messages|
        messages.system("You are a financial analyst. Extract key metrics from documents.")
        messages.user_with_document("What are the key metrics in this document?", doc)
      end

      expect(response).to be_a(String)
      expect(response.length).to be > 0
    end
  end

  describe 'document analysis via Predict' do
    before do
      next if cassette_exists?('predict_with_document/predict_anthropic')
      next if allow_live_recording && !ENV['ANTHROPIC_API_KEY'].to_s.strip.empty?

      skip 'Requires recorded cassette or DSPY_RUN_LIVE_DOCUMENT_INTEGRATION=1 with ANTHROPIC_API_KEY'
    end

    let(:document_summary_signature) do
      Class.new(DSPy::Signature) do
        description "Extract a summary from a document"

        input do
          const :document, DSPy::Document, description: "The document to summarize"
          const :focus, String, description: "What to focus on"
        end

        output do
          const :summary, String, description: "Document summary"
        end
      end
    end

    it 'extracts information from a PDF through Predict pipeline',
       vcr: { cassette_name: 'predict_with_document/predict_anthropic' } do
      DSPy.configure do |c|
        c.lm = DSPy::LM.new("anthropic/#{anthropic_model}", api_key: ENV['ANTHROPIC_API_KEY'], structured_outputs: false)
      end

      doc = DSPy::Document.new(
        base64: TestDocuments.create_base64_pdf(text: "Q4 Revenue: $1.2M. Year-over-year growth: 15%. Active users: 50,000."),
        content_type: 'application/pdf'
      )

      predictor = DSPy::Predict.new(document_summary_signature)
      result = predictor.call(document: doc, focus: "financial metrics")

      expect(result.summary).to be_a(String)
      expect(result.summary.length).to be > 0
    end
  end

  describe 'document analysis via RubyLLM' do
    before do
      next if cassette_exists?('predict_with_document/raw_chat_ruby_llm_anthropic')
      next if allow_live_recording && !ENV['ANTHROPIC_API_KEY'].to_s.strip.empty?

      skip 'Requires recorded cassette or DSPY_RUN_LIVE_DOCUMENT_INTEGRATION=1 with ANTHROPIC_API_KEY'
    end

    it 'analyzes a PDF document via RubyLLM Anthropic',
       vcr: { cassette_name: 'predict_with_document/raw_chat_ruby_llm_anthropic' } do
      lm = DSPy::LM.new(
        "ruby_llm/#{ruby_llm_anthropic_model}",
        api_key: ENV['ANTHROPIC_API_KEY'],
        structured_outputs: false
      )

      doc = DSPy::Document.new(
        base64: TestDocuments.create_base64_pdf(text: 'Revenue: $1.2M. Growth: 15%.'),
        content_type: 'application/pdf'
      )

      response = lm.raw_chat do |messages|
        messages.system('You extract financial metrics from PDF documents.')
        messages.user_with_document('Reply with the revenue figure only.', doc)
      end

      expect(response).to be_a(String)
      expect(response).to include('1.2')
    end
  end
end
