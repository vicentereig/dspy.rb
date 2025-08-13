#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dspy'
require 'json'

# Example: Comprehensive Image Analysis
# This example demonstrates how to use DSPy's multimodal capabilities
# to extract detailed information from images including colors, objects, mood, etc.

# Define a signature for comprehensive image analysis
class ImageAnalysis < DSPy::Signature
  description "Analyze images comprehensively to extract objects, colors, mood, style, and other visual characteristics"

  class DetailLevel < T::Enum
    enums do
      Brief = new('brief')
      Standard = new('standard')
      Detailed = new('detailed')
    end
  end

  input do
    const :image, DSPy::Image, description: 'Image to analyze'
    const :focus, String, default: 'general', description: 'Analysis focus (e.g., "colors", "objects", "mood", "general")'
    const :detail_level, DetailLevel, default: DetailLevel::Standard, description: 'Level of detail'
  end
  
  output do
    const :description, String, description: 'Overall description of the image'
    const :objects, T::Array[String], description: 'List of objects detected in the image'
    const :dominant_colors, T::Array[String], description: 'Main colors present in the image'
    const :mood, String, description: 'Overall mood or atmosphere of the image'
    const :style, String, description: 'Artistic style or photographic characteristics'
    const :composition, String, description: 'Description of the image composition'
    const :lighting, String, description: 'Description of lighting conditions'
    const :setting, String, description: 'Location or environment depicted'
    const :confidence, Float, description: 'Analysis confidence (0.0-1.0)'
  end
end

# Define a more focused signature for color analysis
class ColorAnalysis < DSPy::Signature
  description "Analyze color composition, temperature, and harmony in images with specialized color theory expertise"

  input do
    const :image, DSPy::Image, description: 'Image to analyze for color information'
    const :color_focus, String, default: 'dominant', description: 'Color analysis focus ("dominant", "palette", "temperature")'
  end
  
  output do
    const :dominant_colors, T::Array[String], description: 'Primary colors in order of prominence'
    const :color_palette, T::Array[String], description: 'Complete color palette detected'
    const :color_temperature, String, description: 'Overall color temperature (warm, cool, neutral)'
    const :saturation_level, String, description: 'Overall saturation (high, medium, low)'
    const :brightness_level, String, description: 'Overall brightness (bright, medium, dark)'
    const :color_harmony, String, description: 'Type of color harmony (complementary, analogous, etc.)'
  end
end

# Main example
def main
  # Initialize DSPy with a vision-capable model
  DSPy.config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',  # or 'anthropic/claude-4'
    api_key: ENV['OPENAI_API_KEY'] || ENV['ANTHROPIC_API_KEY']
  )
  
  # Example 1: Comprehensive analysis of a landscape image
  puts "Example 1: Comprehensive Image Analysis - Landscape"
  puts "=" * 60
  
  # Using a nature landscape image
  landscape_image = DSPy::Image.new(
    url: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg'
  )
  
  analyzer = DSPy::Predict.new(ImageAnalysis)
  landscape_analysis = analyzer.call(
    image: landscape_image,
    focus: 'general',
    detail_level: ImageAnalysis::DetailLevel::Detailed
  )
  
  puts "Analysis Results:"
  puts "  Description: #{landscape_analysis.description}"
  puts "  Setting: #{landscape_analysis.setting}"
  puts "  Mood: #{landscape_analysis.mood}"
  puts "  Style: #{landscape_analysis.style}"
  puts "  Lighting: #{landscape_analysis.lighting}"
  puts "  Composition: #{landscape_analysis.composition}"
  puts "  Confidence: #{(landscape_analysis.confidence * 100).round(1)}%"
  
  puts "\nObjects Detected:"
  landscape_analysis.objects.each_with_index do |object, i|
    puts "  #{i + 1}. #{object}"
  end
  
  puts "\nDominant Colors:"
  landscape_analysis.dominant_colors.each_with_index do |color, i|
    puts "  #{i + 1}. #{color}"
  end
  
  # Example 2: Focused color analysis
  puts "\n" + "=" * 60
  puts "Example 2: Detailed Color Analysis"
  puts "-" * 60
  
  color_analyzer = DSPy::Predict.new(ColorAnalysis)
  color_analysis = color_analyzer.call(
    image: landscape_image,
    color_focus: 'palette'
  )
  
  puts "Color Analysis Results:"
  puts "  Color Temperature: #{color_analysis.color_temperature}"
  puts "  Saturation Level: #{color_analysis.saturation_level}"
  puts "  Brightness Level: #{color_analysis.brightness_level}"
  puts "  Color Harmony: #{color_analysis.color_harmony}"
  
  puts "\nDominant Colors (by prominence):"
  color_analysis.dominant_colors.each_with_index do |color, i|
    puts "  #{i + 1}. #{color}"
  end
  
  puts "\nComplete Color Palette:"
  color_analysis.color_palette.each_with_index do |color, i|
    puts "  #{i + 1}. #{color}"
  end
  
  # Example 3: Art/Portrait analysis
  puts "\n" + "=" * 60
  puts "Example 3: Portrait/Art Analysis"
  puts "-" * 60
  
  # Using a portrait or artwork (example URL)
  portrait_image = DSPy::Image.new(
    url: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/ec/Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg/687px-Mona_Lisa%2C_by_Leonardo_da_Vinci%2C_from_C2RMF_retouched.jpg'
  )
  
  artwork_analysis = analyzer.call(
    image: portrait_image,
    focus: 'artistic',
    detail_level: ImageAnalysis::DetailLevel::Detailed
  )
  
  puts "Artistic Analysis Results:"
  puts "  Description: #{artwork_analysis.description}"
  puts "  Style: #{artwork_analysis.style}"
  puts "  Mood: #{artwork_analysis.mood}"
  puts "  Composition: #{artwork_analysis.composition}"
  puts "  Lighting: #{artwork_analysis.lighting}"
  puts "  Setting: #{artwork_analysis.setting}"
  
  puts "\nArtistic Elements:"
  artwork_analysis.objects.each_with_index do |element, i|
    puts "  #{i + 1}. #{element}"
  end
  
  puts "\nColor Palette:"
  artwork_analysis.dominant_colors.each_with_index do |color, i|
    puts "  #{i + 1}. #{color}"
  end
  
  # Example 4: Using local base64 image
  puts "\n" + "=" * 60
  puts "Example 4: Local Image Analysis"
  puts "-" * 60
  
  if File.exist?('sample_image.jpg')
    puts "Analyzing local image..."
    
    # Load and encode local image
    File.open('sample_image.jpg', 'rb') do |file|
      image_data = file.read
      base64_data = Base64.strict_encode64(image_data)
      
      local_image = DSPy::Image.new(
        base64: base64_data,
        content_type: 'image/jpeg'
      )
      
      local_analysis = analyzer.call(
        image: local_image,
        focus: 'objects',
        detail_level: ImageAnalysis::DetailLevel::Standard
      )
      
      puts "Local Image Analysis:"
      puts "  Description: #{local_analysis.description}"
      puts "  Objects: #{local_analysis.objects.join(', ')}"
      puts "  Dominant Colors: #{local_analysis.dominant_colors.join(', ')}"
      puts "  Mood: #{local_analysis.mood}"
    end
  else
    puts "  (Skipping: No local sample_image.jpg found)"
  end
  
  puts "\n" + "=" * 60
  puts "Analysis complete! All examples demonstrate type-safe structured output"
  puts "with detailed image understanding across different domains."
end

if __FILE__ == $0
  main
end