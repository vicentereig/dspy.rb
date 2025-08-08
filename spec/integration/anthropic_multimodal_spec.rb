# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require_relative '../support/test_images'

RSpec.describe 'Anthropic Multimodal Integration', :vcr do
  let(:api_key) { ENV['ANTHROPIC_API_KEY'] || 'test-key' }
  let(:model) { 'claude-3-5-sonnet-20241022' }
  
  describe 'image analysis' do
    it 'analyzes an image from base64 data', vcr: { cassette_name: 'anthropic_multimodal_base64' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
      
      lm = DSPy::LM.new("anthropic/#{model}", api_key: api_key)
      
      # Create a simple red square image in base64
      base64_image = TestImages.create_base64_png(color: :red, width: 16, height: 16)
      
      image = DSPy::Image.new(
        base64: base64_image,
        content_type: 'image/png'
      )
      
      response = lm.raw_chat do |messages|
        messages.user_with_image('What color is this image? Answer with just the color name.', image)
      end
      
      expect(response).to be_a(String)
      expect(response.downcase).to include('red')
    end
    
    it 'compares multiple images', vcr: { cassette_name: 'anthropic_multimodal_multiple' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
      
      lm = DSPy::LM.new("anthropic/#{model}", api_key: api_key)
      
      # Two different colored squares
      red_square = TestImages.create_base64_png(color: :red, width: 16, height: 16)
      blue_square = TestImages.create_base64_png(color: :blue, width: 16, height: 16)
      
      image1 = DSPy::Image.new(base64: red_square, content_type: 'image/png')
      image2 = DSPy::Image.new(base64: blue_square, content_type: 'image/png')
      
      response = lm.raw_chat do |messages|
        messages.user_with_images('What colors are these two images? List them in order.', [image1, image2])
      end
      
      expect(response).to be_a(String)
      expect(response.downcase).to match(/red.*blue/m) # multiline match
    end
    
    it 'raises error for non-vision model', vcr: { cassette_name: 'anthropic_multimodal_error' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
      
      non_vision_lm = DSPy::LM.new('anthropic/claude-2.1', api_key: api_key)
      
      # Anthropic doesn't support URLs directly, so we use base64
      base64_image = TestImages.create_base64_png(color: :red, width: 16, height: 16)
      image = DSPy::Image.new(base64: base64_image, content_type: 'image/png')
      
      expect {
        non_vision_lm.raw_chat do |messages|
          messages.user_with_image('What is this?', image)
        end
      }.to raise_error(ArgumentError, /does not support vision/)
    end
    
    it 'handles image with system prompt', vcr: { cassette_name: 'anthropic_multimodal_system' } do
      skip 'Requires ANTHROPIC_API_KEY' unless ENV['ANTHROPIC_API_KEY']
      
      lm = DSPy::LM.new("anthropic/#{model}", api_key: api_key)
      
      base64_image = TestImages.create_base64_png(color: :red, width: 16, height: 16)
      image = DSPy::Image.new(base64: base64_image, content_type: 'image/png')
      
      response = lm.raw_chat do |messages|
        messages.system('You are a color detection expert. Always respond with just the color name.')
        messages.user_with_image('What color?', image)
      end
      
      expect(response).to be_a(String)
      expect(response.downcase.strip).to match(/^red/)
    end
  end

  describe 'provider compatibility validation' do
    let(:api_key) { ENV['ANTHROPIC_API_KEY'] }

    context 'when using OpenAI-specific features' do
      it 'raises error for URL images' do
        skip 'Requires ANTHROPIC_API_KEY' unless api_key
        lm = DSPy::LM.new("anthropic/#{model}", api_key: api_key)

        image = DSPy::Image.new(url: 'https://example.com/image.jpg')
        
        expect {
          lm.raw_chat do |messages|
            messages.user_with_image("What's in this image?", image)
          end
        }.to raise_error(
          DSPy::LM::IncompatibleImageFeatureError,
          "Anthropic doesn't support image URLs. Please provide base64 or raw data instead."
        )
      end

      it 'raises error for detail parameter' do
        skip 'Requires ANTHROPIC_API_KEY' unless api_key
        lm = DSPy::LM.new("anthropic/#{model}", api_key: api_key)

        image = DSPy::Image.new(
          base64: TestImages.create_solid_color_png,
          content_type: 'image/png',
          detail: 'high'
        )
        
        expect {
          lm.raw_chat do |messages|
            messages.user_with_image("What's in this image?", image)
          end
        }.to raise_error(
          DSPy::LM::IncompatibleImageFeatureError,
          "Anthropic doesn't support the 'detail' parameter. This feature is OpenAI-specific."
        )
      end
    end
  end
end