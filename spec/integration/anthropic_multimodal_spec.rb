# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe 'Anthropic Multimodal Integration', :vcr do
  let(:api_key) { ENV['ANTHROPIC_API_KEY'] || 'test-key' }
  let(:model) { 'claude-3-5-sonnet-20241022' }
  let(:lm) { DSPy::LM.new("anthropic/#{model}", api_key: api_key) }
  
  describe 'image analysis' do
    it 'analyzes an image from base64 data', vcr: { cassette_name: 'anthropic_multimodal_base64' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
      
      # Create a simple red square image in base64
      png_data = create_simple_red_square
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
    
    it 'compares multiple images', vcr: { cassette_name: 'anthropic_multimodal_multiple' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
      
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
    
    it 'raises error for non-vision model', vcr: { cassette_name: 'anthropic_multimodal_error' } do
      non_vision_lm = DSPy::LM.new('anthropic/claude-2.1', api_key: api_key)
      
      # Anthropic doesn't support URLs directly, so we use base64
      base64_image = Base64.strict_encode64(create_simple_red_square)
      image = DSPy::Image.new(base64: base64_image, content_type: 'image/png')
      
      expect {
        non_vision_lm.raw_chat do |messages|
          messages.user_with_image('What is this?', image)
        end
      }.to raise_error(ArgumentError, /does not support vision/)
    end
    
    it 'handles image with system prompt', vcr: { cassette_name: 'anthropic_multimodal_system' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
      
      base64_image = Base64.strict_encode64(create_simple_red_square)
      image = DSPy::Image.new(base64: base64_image, content_type: 'image/png')
      
      response = lm.raw_chat do |messages|
        messages.system('You are a color detection expert. Always respond with just the color name.')
        messages.user_with_image('What color?', image)
      end
      
      expect(response.content).to be_a(String)
      expect(response.content.downcase.strip).to match(/^red/)
    end
  end
  
  private
  
  def create_simple_red_square
    # Create a minimal valid PNG (16x16 red square)
    [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  # PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
      0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10,  # 16x16 pixels
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x91, 0x68,
      0x36, 0x00, 0x00, 0x00, 0x16, 0x49, 0x44, 0x41,  # IDAT chunk
      0x54, 0x78, 0x9C, 0x62, 0xF8, 0xCF, 0xC0, 0x00,  # Red pixels (compressed)
      0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
      0xB4, 0x79, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,  # IEND chunk
      0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ].pack('C*')
  end
  
  def create_colored_square(color)
    # Create a minimal PNG of the specified color
    # For simplicity, reusing the red square structure but changing the pixel data
    case color
    when 'red'
      create_simple_red_square
    when 'blue'
      # Blue square PNG
      [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x91, 0x68,
        0x36, 0x00, 0x00, 0x00, 0x16, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0xF8, 0xFF,  # Blue pixels (compressed)
        0xFF, 0x03, 0x03, 0x00, 0x00, 0x30, 0xC0, 0x01,
        0x00, 0x79, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
        0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ].pack('C*')
    else
      create_simple_red_square
    end
  end
end