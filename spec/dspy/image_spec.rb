# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe DSPy::Image do
  describe '#initialize' do
    context 'with URL' do
      it 'creates an image from a URL' do
        url = 'https://example.com/image.jpg'
        image = described_class.new(url: url)
        
        expect(image.url).to eq(url)
        expect(image.base64).to be_nil
        expect(image.data).to be_nil
        expect(image.content_type).to eq('image/jpeg')
      end
      
      it 'infers content type from URL extension' do
        expect(described_class.new(url: 'https://example.com/image.png').content_type).to eq('image/png')
        expect(described_class.new(url: 'https://example.com/image.gif').content_type).to eq('image/gif')
        expect(described_class.new(url: 'https://example.com/image.webp').content_type).to eq('image/webp')
      end
    end
    
    context 'with base64 data' do
      it 'creates an image from base64 string' do
        base64_data = Base64.strict_encode64('fake_image_data')
        image = described_class.new(base64: base64_data, content_type: 'image/png')
        
        expect(image.base64).to eq(base64_data)
        expect(image.url).to be_nil
        expect(image.data).to be_nil
        expect(image.content_type).to eq('image/png')
      end
      
      it 'requires content_type when using base64' do
        base64_data = Base64.strict_encode64('fake_image_data')
        expect {
          described_class.new(base64: base64_data)
        }.to raise_error(ArgumentError, /content_type is required/)
      end
    end
    
    context 'with byte data' do
      it 'creates an image from byte array' do
        data = 'fake_image_data'.bytes
        image = described_class.new(data: data, content_type: 'image/jpeg')
        
        expect(image.data).to eq(data)
        expect(image.url).to be_nil
        expect(image.base64).to be_nil
        expect(image.content_type).to eq('image/jpeg')
      end
      
      it 'requires content_type when using data' do
        data = 'fake_image_data'.bytes
        expect {
          described_class.new(data: data)
        }.to raise_error(ArgumentError, /content_type is required/)
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
          described_class.new(url: 'https://example.com/image.jpg', base64: 'abc123')
        }.to raise_error(ArgumentError, /Only one of url, base64, or data can be provided/)
      end
    end
  end
  
  describe '#to_openai_format' do
    context 'with URL' do
      it 'returns OpenAI image_url format' do
        image = described_class.new(url: 'https://example.com/image.jpg')
        result = image.to_openai_format
        
        expect(result).to eq({
          type: 'image_url',
          image_url: {
            url: 'https://example.com/image.jpg'
          }
        })
      end
      
      it 'includes detail parameter when specified' do
        image = described_class.new(url: 'https://example.com/image.jpg', detail: 'high')
        result = image.to_openai_format
        
        expect(result).to eq({
          type: 'image_url',
          image_url: {
            url: 'https://example.com/image.jpg',
            detail: 'high'
          }
        })
      end
    end
    
    context 'with base64 data' do
      it 'returns OpenAI data URL format' do
        base64_data = Base64.strict_encode64('fake_image_data')
        image = described_class.new(base64: base64_data, content_type: 'image/png')
        result = image.to_openai_format
        
        expect(result).to eq({
          type: 'image_url',
          image_url: {
            url: "data:image/png;base64,#{base64_data}"
          }
        })
      end
    end
    
    context 'with byte data' do
      it 'converts to base64 and returns data URL format' do
        data = 'fake_image_data'
        image = described_class.new(data: data.bytes, content_type: 'image/jpeg')
        result = image.to_openai_format
        
        expected_base64 = Base64.strict_encode64(data)
        expect(result).to eq({
          type: 'image_url',
          image_url: {
            url: "data:image/jpeg;base64,#{expected_base64}"
          }
        })
      end
    end
  end
  
  describe '#to_anthropic_format' do
    context 'with URL' do
      it 'fetches and converts to base64 for Anthropic' do
        # For now, we'll skip this test as it requires HTTP fetching
        skip 'URL fetching for Anthropic will be implemented separately'
      end
    end
    
    context 'with base64 data' do
      it 'returns Anthropic image format' do
        base64_data = Base64.strict_encode64('fake_image_data')
        image = described_class.new(base64: base64_data, content_type: 'image/png')
        result = image.to_anthropic_format
        
        expect(result).to eq({
          type: 'image',
          source: {
            type: 'base64',
            media_type: 'image/png',
            data: base64_data
          }
        })
      end
    end
    
    context 'with byte data' do
      it 'converts to base64 and returns Anthropic format' do
        data = 'fake_image_data'
        image = described_class.new(data: data.bytes, content_type: 'image/jpeg')
        result = image.to_anthropic_format
        
        expected_base64 = Base64.strict_encode64(data)
        expect(result).to eq({
          type: 'image',
          source: {
            type: 'base64',
            media_type: 'image/jpeg',
            data: expected_base64
          }
        })
      end
    end
  end
  
  describe '#to_base64' do
    it 'returns base64 data when available' do
      base64_data = Base64.strict_encode64('fake_image_data')
      image = described_class.new(base64: base64_data, content_type: 'image/png')
      
      expect(image.to_base64).to eq(base64_data)
    end
    
    it 'converts byte data to base64' do
      data = 'fake_image_data'
      image = described_class.new(data: data.bytes, content_type: 'image/jpeg')
      
      expect(image.to_base64).to eq(Base64.strict_encode64(data))
    end
    
    it 'returns nil for URL-based images' do
      image = described_class.new(url: 'https://example.com/image.jpg')
      
      expect(image.to_base64).to be_nil
    end
  end
  
  describe '#validate!' do
    it 'validates supported content types' do
      valid_types = ['image/jpeg', 'image/png', 'image/gif', 'image/webp']
      
      valid_types.each do |content_type|
        expect {
          described_class.new(base64: 'abc123', content_type: content_type)
        }.not_to raise_error
      end
    end
    
    it 'raises error for unsupported content types' do
      expect {
        described_class.new(base64: 'abc123', content_type: 'image/svg+xml')
      }.to raise_error(ArgumentError, /Unsupported image format/)
    end
    
    it 'validates image size limits' do
      # 6MB of data (over 5MB limit)
      large_data = 'x' * (6 * 1024 * 1024)
      
      expect {
        described_class.new(data: large_data.bytes, content_type: 'image/jpeg')
      }.to raise_error(ArgumentError, /Image size exceeds 5MB limit/)
    end
  end
end