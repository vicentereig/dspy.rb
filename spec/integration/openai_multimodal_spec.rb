# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require_relative '../support/test_images'

RSpec.describe 'OpenAI Multimodal Integration', :vcr do
  let(:api_key) { ENV['OPENAI_API_KEY'] || 'test-key' }
  let(:model) { 'gpt-4o-mini' }
  
  describe 'image analysis' do
    it 'analyzes an image from URL', vcr: { cassette_name: 'openai_multimodal_url' } do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      
      lm = DSPy::LM.new("openai/#{model}", api_key: api_key)
      
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
      
      lm = DSPy::LM.new("openai/#{model}", api_key: api_key)
      
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
      
      lm = DSPy::LM.new("openai/#{model}", api_key: api_key)
      
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
      
      non_vision_lm = DSPy::LM.new('openai/gpt-3.5-turbo', api_key: api_key)
      
      image = DSPy::Image.new(url: 'https://example.com/image.jpg')
      
      expect {
        non_vision_lm.raw_chat do |messages|
          messages.user_with_image('What is this?', image)
        end
      }.to raise_error(ArgumentError, /does not support vision/)
    end
  end

  describe 'provider compatibility validation' do
    let(:api_key) { ENV['OPENAI_API_KEY'] }

    context 'when using OpenAI-specific features' do
      it 'allows URL images with detail parameter' do
        skip 'Requires OPENAI_API_KEY' unless api_key
        lm = DSPy::LM.new("openai/#{model}", api_key: api_key)

        image = DSPy::Image.new(
          url: 'https://example.com/image.jpg',
          detail: 'low'
        )
        
        # This should not raise an error during validation
        # (though it might fail at API call due to fake URL)
        expect {
          builder = DSPy::LM::MessageBuilder.new
          builder.user_with_image("What's in this image?", image)
          messages = builder.build
          # We're testing validation, not the actual API call
          lm.send(:format_multimodal_messages, messages)
        }.not_to raise_error
      end

      it 'allows base64 images with detail parameter' do
        skip 'Requires OPENAI_API_KEY' unless api_key
        lm = DSPy::LM.new("openai/#{model}", api_key: api_key)

        image = DSPy::Image.new(
          base64: TestImages.create_solid_color_png,
          content_type: 'image/png',
          detail: 'high'
        )
        
        # This should not raise an error
        expect {
          builder = DSPy::LM::MessageBuilder.new
          builder.user_with_image("What's in this image?", image)
          messages = builder.build
          lm.send(:format_multimodal_messages, messages)
        }.not_to raise_error
      end
    end
  end
end