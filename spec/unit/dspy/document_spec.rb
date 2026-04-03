# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe DSPy::Document do
  describe '#initialize' do
    context 'with URL' do
      it 'creates a document from a URL' do
        url = 'https://example.com/report.pdf'
        doc = described_class.new(url: url)

        expect(doc.url).to eq(url)
        expect(doc.base64).to be_nil
        expect(doc.data).to be_nil
        expect(doc.content_type).to eq('application/pdf')
      end

      it 'raises for a non-PDF URL' do
        expect {
          described_class.new(url: 'https://example.com/not-a-pdf')
        }.to raise_error(ArgumentError, /Document URL must point to a PDF/)
      end
    end

    context 'with base64 data' do
      it 'creates a document from base64 string' do
        base64_data = Base64.strict_encode64('fake_pdf_data')
        doc = described_class.new(base64: base64_data, content_type: 'application/pdf')

        expect(doc.base64).to eq(base64_data)
        expect(doc.url).to be_nil
        expect(doc.data).to be_nil
        expect(doc.content_type).to eq('application/pdf')
      end

      it 'requires content_type when using base64' do
        base64_data = Base64.strict_encode64('fake_pdf_data')

        expect {
          described_class.new(base64: base64_data)
        }.to raise_error(ArgumentError, /content_type is required/)
      end
    end

    context 'with byte data' do
      it 'creates a document from byte array' do
        data = 'fake_pdf_data'.bytes
        doc = described_class.new(data: data, content_type: 'application/pdf')

        expect(doc.data).to eq(data)
        expect(doc.url).to be_nil
        expect(doc.base64).to be_nil
        expect(doc.content_type).to eq('application/pdf')
      end
    end

    context 'with invalid inputs' do
      it 'raises error when no input provided' do
        expect {
          described_class.new
        }.to raise_error(ArgumentError, /Must provide either url, base64, or data/)
      end

      it 'raises error when multiple inputs provided' do
        expect {
          described_class.new(url: 'https://example.com/report.pdf', base64: 'abc123')
        }.to raise_error(ArgumentError, /Only one of url, base64, or data can be provided/)
      end

      it 'raises error for unsupported content types' do
        expect {
          described_class.new(base64: 'abc123', content_type: 'text/plain')
        }.to raise_error(ArgumentError, /Unsupported document format/)
      end
    end
  end

  describe '#to_anthropic_format' do
    it 'returns Anthropic document URL format' do
      url = 'https://example.com/report.pdf'
      doc = described_class.new(url: url)

      expect(doc.to_anthropic_format).to eq({
        type: 'document',
        source: {
          type: 'url',
          url: url
        }
      })
    end

    it 'returns Anthropic document base64 format' do
      base64_data = Base64.strict_encode64('fake_pdf_data')
      doc = described_class.new(base64: base64_data, content_type: 'application/pdf')

      expect(doc.to_anthropic_format).to eq({
        type: 'document',
        source: {
          type: 'base64',
          media_type: 'application/pdf',
          data: base64_data
        }
      })
    end
  end

  describe '#to_ruby_llm_attachment' do
    it 'returns RubyLLM URL attachment format' do
      doc = described_class.new(url: 'https://example.com/report.pdf')

      expect(doc.to_ruby_llm_attachment).to eq('https://example.com/report.pdf')
    end

    it 'returns a RubyLLM-compatible inline PDF attachment for base64 data' do
      pdf_data = TestDocuments.create_minimal_pdf(text: 'Quarterly results')
      base64_data = Base64.strict_encode64(pdf_data)
      doc = described_class.new(base64: base64_data, content_type: 'application/pdf')
      attachment = doc.to_ruby_llm_attachment

      expect(attachment).to respond_to(:read)
      expect(attachment.path).to eq('document.pdf')
      expect(attachment.read).to eq(pdf_data)
    end
  end

  describe '#validate_for_provider!' do
    let(:doc) { described_class.new(url: 'https://example.com/report.pdf') }

    it 'accepts anthropic' do
      expect { doc.validate_for_provider!('anthropic') }.not_to raise_error
    end

    it 'rejects openai' do
      expect {
        doc.validate_for_provider!('openai')
      }.to raise_error(DSPy::LM::IncompatibleDocumentFeatureError, /OpenAI document inputs are not supported/)
    end

    it 'rejects gemini' do
      expect {
        doc.validate_for_provider!('gemini')
      }.to raise_error(DSPy::LM::IncompatibleDocumentFeatureError, /Gemini document inputs are not supported/)
    end
  end
end
