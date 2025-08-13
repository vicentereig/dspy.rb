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
  input :focus, String, default: 'general', desc: 'Analysis focus (e.g., "colors", "objects", "mood", "general")'
  input :detail_level, String, default: 'standard', desc: 'Level of detail ("brief", "standard", "detailed")'
  
  output do
    const :description, String, desc: 'Overall description of the image'
    const :objects, T::Array[String], desc: 'List of objects detected in the image'
    const :dominant_colors, T::Array[String], desc: 'Main colors present in the image'
    const :mood, String, desc: 'Overall mood or atmosphere of the image'
    const :style, String, desc: 'Artistic style or photographic characteristics'
    const :composition, String, desc: 'Description of the image composition'
    const :lighting, String, desc: 'Description of lighting conditions'
    const :setting, String, desc: 'Location or environment depicted'
    const :confidence, Float, desc: 'Analysis confidence (0.0-1.0)'
  end
end

# Define a more focused signature for color analysis
class ColorAnalysis < DSPy::Signature
  input :color_focus, String, default: 'dominant', desc: 'Color analysis focus ("dominant", "palette", "temperature")'
  
  output do
    const :dominant_colors, T::Array[String], desc: 'Primary colors in order of prominence'
    const :color_palette, T::Array[String], desc: 'Complete color palette detected'
    const :color_temperature, String, desc: 'Overall color temperature (warm, cool, neutral)'
    const :saturation_level, String, desc: 'Overall saturation (high, medium, low)'
    const :brightness_level, String, desc: 'Overall brightness (bright, medium, dark)'
    const :color_harmony, String, desc: 'Type of color harmony (complementary, analogous, etc.)'
  end
end

# Create a comprehensive image analyzer
class ImageAnalyzer < DSPy::Predict
  def initialize
    super(ImageAnalysis)
  end
  
  def analyze(image, focus: 'general', detail_level: 'standard')
    # Build multimodal message content
    messages = []
    
    # System prompt for comprehensive analysis
    messages << {
      role: 'system',
      content: <<~PROMPT
        You are an expert image analyst with skills in art history, photography, and visual psychology.
        Analyze images comprehensively, extracting information about:
        - Objects and subjects present
        - Color palette and dominant colors
        - Mood, atmosphere, and emotional tone
        - Artistic style and photographic techniques
        - Composition and visual elements
        - Lighting and environmental conditions
        
        Be specific and accurate in your observations.
      PROMPT
    }
    
    # User message with image and instructions
    content = [
      { type: 'text', text: "Analyze this image with focus on #{focus} at #{detail_level} detail level." },
      { type: 'image', image: image }
    ]
    
    messages << {
      role: 'user',
      content: content
    }
    
    # Call the prediction
    forward(
      focus: focus,
      detail_level: detail_level
    )
  end
end

# Create a specialized color analyzer
class ColorAnalyzer < DSPy::Predict
  def initialize
    super(ColorAnalysis)
  end
  
  def analyze_colors(image, focus: 'dominant')
    # Build multimodal message for color analysis
    messages = []
    
    messages << {
      role: 'system',
      content: <<~PROMPT
        You are a color theory expert specializing in image color analysis.
        Analyze the colors in images with precision, identifying:
        - Dominant colors by prominence and area coverage
        - Complete color palette including subtle hues
        - Color temperature (warm/cool characteristics)
        - Saturation and brightness levels
        - Color harmony relationships
        
        Use specific color names (e.g., "cerulean blue", "burnt orange") when possible.
      PROMPT
    }
    
    content = [
      { type: 'text', text: "Perform detailed color analysis focusing on #{focus} colors." },
      { type: 'image', image: image }
    ]
    
    messages << {
      role: 'user',
      content: content
    }
    
    forward(color_focus: focus)
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
  
  analyzer = ImageAnalyzer.new
  result = analyzer.analyze(landscape_image, focus: 'general', detail_level: 'detailed')
  
  puts "Analysis Results:"
  puts "  Description: #{result.description}"
  puts "  Setting: #{result.setting}"
  puts "  Mood: #{result.mood}"
  puts "  Style: #{result.style}"
  puts "  Lighting: #{result.lighting}"
  puts "  Composition: #{result.composition}"
  puts "  Confidence: #{(result.confidence * 100).round(1)}%"
  
  puts "\nObjects Detected:"
  result.objects.each_with_index do |object, i|
    puts "  #{i + 1}. #{object}"
  end
  
  puts "\nDominant Colors:"
  result.dominant_colors.each_with_index do |color, i|
    puts "  #{i + 1}. #{color}"
  end
  
  # Example 2: Focused color analysis
  puts "\n" + "=" * 60
  puts "Example 2: Detailed Color Analysis"
  puts "-" * 60
  
  color_analyzer = ColorAnalyzer.new
  color_result = color_analyzer.analyze_colors(landscape_image, focus: 'palette')
  
  puts "Color Analysis Results:"
  puts "  Color Temperature: #{color_result.color_temperature}"
  puts "  Saturation Level: #{color_result.saturation_level}"
  puts "  Brightness Level: #{color_result.brightness_level}"
  puts "  Color Harmony: #{color_result.color_harmony}"
  
  puts "\nDominant Colors (by prominence):"
  color_result.dominant_colors.each_with_index do |color, i|
    puts "  #{i + 1}. #{color}"
  end
  
  puts "\nComplete Color Palette:"
  color_result.color_palette.each_with_index do |color, i|
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
  
  art_result = analyzer.analyze(portrait_image, focus: 'artistic', detail_level: 'detailed')
  
  puts "Artistic Analysis Results:"
  puts "  Description: #{art_result.description}"
  puts "  Style: #{art_result.style}"
  puts "  Mood: #{art_result.mood}"
  puts "  Composition: #{art_result.composition}"
  puts "  Lighting: #{art_result.lighting}"
  puts "  Setting: #{art_result.setting}"
  
  puts "\nArtistic Elements:"
  art_result.objects.each_with_index do |element, i|
    puts "  #{i + 1}. #{element}"
  end
  
  puts "\nColor Palette:"
  art_result.dominant_colors.each_with_index do |color, i|
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
      
      local_result = analyzer.analyze(local_image, focus: 'objects', detail_level: 'standard')
      
      puts "Local Image Analysis:"
      puts "  Description: #{local_result.description}"
      puts "  Objects: #{local_result.objects.join(', ')}"
      puts "  Dominant Colors: #{local_result.dominant_colors.join(', ')}"
      puts "  Mood: #{local_result.mood}"
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