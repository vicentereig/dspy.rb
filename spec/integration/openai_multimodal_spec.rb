# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require_relative '../support/test_images'

RSpec.describe 'OpenAI Multimodal Integration', :vcr do
  # No fallback key - tests will skip if ENV key is not available
  let(:model) { 'gpt-4o-mini' }
  
  describe 'image analysis' do
    it 'analyzes an image from URL', vcr: { cassette_name: 'openai_multimodal_url' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new("openai/#{model}", api_key: ENV['OPENAI_API_KEY'])
      
      image = DSPy::Image.new(
        url: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg'
      )
      
      response = lm.raw_chat do |messages|
        messages.user_with_image('What is in this image? Be brief.', image)
      end
      
      expect(response).to be_a(String)
      expect(response.downcase).to match(/boardwalk|nature|path|trees|sky/)
    end
    
    it 'analyzes an image from base64 data', vcr: { cassette_name: 'openai_multimodal_base64' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new("openai/#{model}", api_key: ENV['OPENAI_API_KEY'])
      
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
    
    it 'compares multiple images', vcr: { cassette_name: 'openai_multimodal_multiple' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new("openai/#{model}", api_key: ENV['OPENAI_API_KEY'])
      
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
    
    it 'raises error for non-vision model', vcr: { cassette_name: 'openai_multimodal_error' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      non_vision_lm = DSPy::LM.new('openai/gpt-3.5-turbo', api_key: ENV['OPENAI_API_KEY'])
      
      image = DSPy::Image.new(url: 'https://example.com/image.jpg')
      
      expect {
        non_vision_lm.raw_chat do |messages|
          messages.user_with_image('What is this?', image)
        end
      }.to raise_error(ArgumentError, /does not support vision/)
    end
  end

  describe 'provider compatibility validation' do

    context 'when using OpenAI-specific features' do
      it 'allows URL images with detail parameter during validation' do
        skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

        image = DSPy::Image.new(
          url: 'https://example.com/image.jpg',
          detail: 'low'
        )
        
        # Direct validation should not raise error for OpenAI
        expect {
          image.validate_for_provider!('openai')
        }.not_to raise_error
      end

      it 'allows base64 images with detail parameter during validation' do
        skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']

        image = DSPy::Image.new(
          base64: TestImages.create_solid_color_png,
          content_type: 'image/png',
          detail: 'high'
        )
        
        # Direct validation should not raise error for OpenAI
        expect {
          image.validate_for_provider!('openai')
        }.not_to raise_error
      end
    end
  end
end