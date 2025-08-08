# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe 'OpenAI Multimodal Integration', :vcr do
  let(:api_key) { ENV['OPENAI_API_KEY'] || 'test-key' }
  let(:model) { 'gpt-4o-mini' }
  let(:lm) { DSPy::LM.new("openai/#{model}", api_key: api_key) }
  
  describe 'image analysis' do
    it 'analyzes an image from URL', vcr: { cassette_name: 'openai_multimodal_url' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      image = DSPy::Image.new(
        url: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg'
      )
      
      response = lm.raw_chat do |messages|
        messages.user_with_image('What is in this image? Be brief.', image)
      end
      
      expect(response.content).to be_a(String)
      expect(response.content.downcase).to match(/boardwalk|nature|path|trees|sky/)
    end
    
    it 'analyzes an image from base64 data', vcr: { cassette_name: 'openai_multimodal_base64' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Create a simple red square image in base64
      # This is a minimal valid PNG image
      png_data = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  # PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
        0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10,  # 16x16 pixels
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x91, 0x68,
        0x36, 0x00, 0x00, 0x00, 0x16, 0x49, 0x44, 0x41,  # IDAT chunk
        0x54, 0x78, 0x9C, 0x62, 0xF8, 0xCF, 0xC0, 0x00,  # Red pixels
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
        0xB4, 0x79, 0x00, 0x00, 0x00, 0x00, 0x00, 0x49,  # IEND chunk
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ].pack('C*')
      
      base64_image = Base64.strict_encode64(png_data)
      
      image = DSPy::Image.new(
        base64: base64_image,
        content_type: 'image/png'
      )
      
      response = lm.raw_chat do |messages|
        messages.user_with_image('What color is this image? Answer with just the color name.', image)
      end
      
      expect(response.content).to be_a(String)
      expect(response.content.downcase).to include('red')
    end
    
    it 'compares multiple images', vcr: { cassette_name: 'openai_multimodal_multiple' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      # Two different colored squares
      red_square = create_colored_square('red')
      blue_square = create_colored_square('blue')
      
      image1 = DSPy::Image.new(base64: red_square, content_type: 'image/png')
      image2 = DSPy::Image.new(base64: blue_square, content_type: 'image/png')
      
      response = lm.raw_chat do |messages|
        messages.user_with_images('What colors are these two images? List them in order.', [image1, image2])
      end
      
      expect(response.content).to be_a(String)
      expect(response.content.downcase).to match(/red.*blue/)
    end
    
    it 'raises error for non-vision model', vcr: { cassette_name: 'openai_multimodal_error' } do
      non_vision_lm = DSPy::LM.new('openai/gpt-3.5-turbo', api_key: api_key)
      
      image = DSPy::Image.new(url: 'https://example.com/image.jpg')
      
      expect {
        non_vision_lm.raw_chat do |messages|
          messages.user_with_image('What is this?', image)
        end
      }.to raise_error(ArgumentError, /does not support vision/)
    end
  end
  
  private
  
  def create_colored_square(color)
    # Create a minimal PNG of the specified color
    pixel_data = case color
                 when 'red'
                   [0xFF, 0x00, 0x00] * 256  # 16x16 red pixels
                 when 'blue'
                   [0x00, 0x00, 0xFF] * 256  # 16x16 blue pixels
                 when 'green'
                   [0x00, 0xFF, 0x00] * 256  # 16x16 green pixels
                 else
                   [0x00, 0x00, 0x00] * 256  # 16x16 black pixels
                 end
    
    # Simplified PNG construction (this is a valid but minimal PNG)
    png_header = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack('C*')
    ihdr = [0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x91, 0x68, 0x36].pack('C*')
    
    # Create a simple uncompressed IDAT chunk (simplified for testing)
    idat_data = pixel_data.flatten.pack('C*')
    compressed = Zlib::Deflate.deflate(idat_data, Zlib::BEST_COMPRESSION)
    idat = [compressed.length].pack('N') + 'IDAT' + compressed
    idat_crc = [Zlib.crc32('IDAT' + compressed)].pack('N')
    
    iend = [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82].pack('C*')
    
    png_data = png_header + ihdr + idat + idat_crc + iend
    Base64.strict_encode64(png_data)
  end
end