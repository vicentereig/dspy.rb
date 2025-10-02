# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DSPy::Image, "provider compatibility" do
  describe '#validate_for_provider!' do
    context 'with Anthropic' do
      context 'when image uses URL' do
        it 'raises IncompatibleImageFeatureError with clear message' do
          image = DSPy::Image.new(url: 'https://example.com/image.jpg')
          
          expect {
            image.validate_for_provider!('anthropic')
          }.to raise_error(
            DSPy::LM::IncompatibleImageFeatureError,
            "Anthropic doesn't support image URLs. Please provide base64 or raw data instead."
          )
        end
      end
      
      context 'when image uses detail parameter' do
        it 'raises IncompatibleImageFeatureError with clear message' do
          image = DSPy::Image.new(
            base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAGAWjR9awAAAABJRU5ErkJggg==',
            content_type: 'image/png',
            detail: 'high'
          )
          
          expect {
            image.validate_for_provider!('anthropic')
          }.to raise_error(
            DSPy::LM::IncompatibleImageFeatureError,
            "Anthropic doesn't support the 'detail' parameter. This feature is OpenAI-specific."
          )
        end
      end
      
      context 'when image uses base64 without detail' do
        it 'does not raise error' do
          image = DSPy::Image.new(
            base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAGAWjR9awAAAABJRU5ErkJggg==',
            content_type: 'image/png'
          )
          
          expect {
            image.validate_for_provider!('anthropic')
          }.not_to raise_error
        end
      end
      
      context 'when image uses raw data without detail' do
        it 'does not raise error' do
          image = DSPy::Image.new(
            data: [0, 1, 2, 3],
            content_type: 'image/png'
          )
          
          expect {
            image.validate_for_provider!('anthropic')
          }.not_to raise_error
        end
      end
    end
    
    context 'with OpenAI' do
      context 'when image uses URL' do
        it 'does not raise error' do
          image = DSPy::Image.new(url: 'https://example.com/image.jpg')
          
          expect {
            image.validate_for_provider!('openai')
          }.not_to raise_error
        end
      end
      
      context 'when image uses URL with detail' do
        it 'does not raise error' do
          image = DSPy::Image.new(
            url: 'https://example.com/image.jpg',
            detail: 'high'
          )
          
          expect {
            image.validate_for_provider!('openai')
          }.not_to raise_error
        end
      end
      
      context 'when image uses base64 with detail' do
        it 'does not raise error' do
          image = DSPy::Image.new(
            base64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAGAWjR9awAAAABJRU5ErkJggg==',
            content_type: 'image/png',
            detail: 'low'
          )
          
          expect {
            image.validate_for_provider!('openai')
          }.not_to raise_error
        end
      end
    end
    
    context 'with unsupported provider' do
      it 'raises error for unknown provider' do
        image = DSPy::Image.new(url: 'https://example.com/image.jpg')
        
        expect {
          image.validate_for_provider!('unknown_provider')
        }.to raise_error(
          DSPy::LM::IncompatibleImageFeatureError,
          /Unknown provider/
        )
      end
    end
  end
  
  describe 'PROVIDER_CAPABILITIES' do
    it 'defines capabilities for each provider' do
      expect(DSPy::Image::PROVIDER_CAPABILITIES).to include('openai', 'anthropic')
      
      openai_caps = DSPy::Image::PROVIDER_CAPABILITIES['openai']
      expect(openai_caps[:sources]).to include('url', 'base64', 'data')
      expect(openai_caps[:parameters]).to include('detail')
      
      anthropic_caps = DSPy::Image::PROVIDER_CAPABILITIES['anthropic']  
      expect(anthropic_caps[:sources]).to include('base64', 'data')
      expect(anthropic_caps[:sources]).not_to include('url')
      expect(anthropic_caps[:parameters]).to be_empty
    end
  end
end