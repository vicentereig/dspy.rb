# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require_relative '../support/test_images'

RSpec.describe 'Gemini Integration' do
  let(:api_key) { ENV['GEMINI_API_KEY'] }
  let(:model) { 'gemini-1.5-flash' }
  
  describe 'basic text generation' do
    it 'generates text response' do
      SSEVCR.use_cassette('gemini_basic_text') do
        lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
        
        response = lm.raw_chat do |messages|
          messages.user('What is the capital of France? Answer with just the city name.')
        end
        
        expect(response).to be_a(String)
        expect(response.downcase).to include('paris')
      end
    end
    
    it 'handles conversation with system messages' do
      SSEVCR.use_cassette('gemini_conversation') do
        lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
        
        response = lm.raw_chat do |messages|
          messages.system('You are a helpful geography teacher.')
          messages.user('What is the capital of Spain?')
        end
        
        expect(response).to be_a(String)
        expect(response.downcase).to include('madrid')
      end
    end
  end
  
  describe 'multimodal capabilities' do
    it 'analyzes an image from base64 data' do
      SSEVCR.use_cassette('gemini_multimodal_base64') do
        lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
        
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
    end
    
    it 'compares multiple images' do
      SSEVCR.use_cassette('gemini_multimodal_multiple') do
        lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
        
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
    end
    
    it 'raises error when trying to use URL images' do
      lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
      
      image = DSPy::Image.new(url: 'https://example.com/image.jpg')
      
      expect {
        lm.raw_chat do |messages|
          messages.user_with_image('What is this?', image)
        end
      }.to raise_error(DSPy::LM::IncompatibleImageFeatureError, /doesn't support image URLs/)
    end
    
    it 'raises error when trying to use detail parameter' do
      lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
      
      base64_image = TestImages.create_base64_png(color: :red, width: 16, height: 16)
      image = DSPy::Image.new(
        base64: base64_image,
        content_type: 'image/png',
        detail: 'high'
      )
      
      expect {
        lm.raw_chat do |messages|
          messages.user_with_image('What is this?', image)
        end
      }.to raise_error(DSPy::LM::IncompatibleImageFeatureError, /doesn't support the 'detail' parameter/)
    end
  end


  describe 'provider compatibility validation' do
    context 'when using Gemini-specific constraints' do
      it 'rejects URL images during validation' do
        image = DSPy::Image.new(url: 'https://example.com/image.jpg')
        
        expect {
          image.validate_for_provider!('gemini')
        }.to raise_error(DSPy::LM::IncompatibleImageFeatureError, /doesn't support image URLs/)
      end

      it 'rejects detail parameter during validation' do
        image = DSPy::Image.new(
          base64: TestImages.create_solid_color_png,
          content_type: 'image/png',
          detail: 'high'
        )
        
        expect {
          image.validate_for_provider!('gemini')
        }.to raise_error(DSPy::LM::IncompatibleImageFeatureError, /doesn't support the 'detail' parameter/)
      end

      it 'allows base64 images without detail parameter' do
        image = DSPy::Image.new(
          base64: TestImages.create_solid_color_png,
          content_type: 'image/png'
        )
        
        expect {
          image.validate_for_provider!('gemini')
        }.not_to raise_error
      end
    end
  end

  describe 'vision model validation' do
    it 'allows vision-capable Gemini models' do
      DSPy::LM::VisionModels::GEMINI_VISION_MODELS.each do |model|
        expect(DSPy::LM::VisionModels.supports_vision?('gemini', model)).to be true
      end
    end
    
    it 'raises error for non-vision model attempting multimodal input' do
      # Assuming there might be text-only Gemini models in the future
      non_vision_model = 'gemini-text-only' # hypothetical
      
      expect {
        DSPy::LM::VisionModels.validate_vision_support!('gemini', non_vision_model)
      }.to raise_error(ArgumentError, /does not support vision/)
    end
  end

  describe 'error handling' do
    it 'handles authentication errors' do
      lm = DSPy::LM.new("gemini/#{model}", api_key: 'invalid-key')
      
      expect {
        lm.raw_chat do |messages|
          messages.user('Hello')
        end
      }.to raise_error(DSPy::LM::AdapterError)
    end
    
    it 'handles safety filter errors gracefully' do
      SSEVCR.use_cassette('gemini_safety_error') do
        lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
        
        # This might trigger safety filters - just test it doesn't crash
        begin
          lm.raw_chat do |messages|
            messages.user('How to make dangerous things')
          end
        rescue DSPy::LM::AdapterError => e
          expect(e.message).to match(/blocked by safety filters|Gemini adapter error/)
        end
      end
    end
  end

  describe 'usage tracking' do
    it 'tracks token usage correctly' do
      SSEVCR.use_cassette('gemini_usage_tracking') do
        lm = DSPy::LM.new("gemini/#{model}", api_key: api_key)
        
        # Use the adapter directly to test usage tracking
        adapter = lm.instance_variable_get(:@adapter)
        response = adapter.chat(
          messages: [{ role: 'user', content: 'Count from 1 to 5.' }]
        )
        
        expect(response.usage).to be_a(DSPy::LM::Usage)
        expect(response.usage.input_tokens).to be > 0
        expect(response.usage.output_tokens).to be > 0
        expect(response.usage.total_tokens).to eq(response.usage.input_tokens + response.usage.output_tokens)
      end
    end
  end
end