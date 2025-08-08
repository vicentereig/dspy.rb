#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dspy'
require 'json'

# Example: Bounding Box Detection in Aerial Images
# This example demonstrates how to use DSPy's multimodal capabilities
# to detect objects in images and return structured bounding box data

# Define a signature for bounding box detection
class BoundingBoxDetection < DSPy::Signature
  input :query, T.any(String, NilClass), desc: 'Object to detect (e.g., "airplanes", "cars")'
  input :image_description, T.any(String, NilClass), desc: 'Optional description of the image'
  
  # Output structured bounding box data
  output do
    const :objects, T::Array[T::Hash[Symbol, T.untyped]], desc: 'Array of detected objects with bounding boxes'
    const :count, Integer, desc: 'Total number of objects detected'
    const :confidence, Float, desc: 'Overall confidence in the detection (0.0-1.0)'
  end
end

# Create a module for object detection
class ObjectDetector < DSPy::Predict
  def initialize
    super(BoundingBoxDetection)
  end
  
  def detect(image, query = 'all objects')
    # Build the prompt with the image
    messages = []
    
    # System prompt for structured output
    messages << {
      role: 'system',
      content: <<~PROMPT
        You are an expert computer vision system that detects objects in images.
        When detecting objects, provide bounding boxes in the format:
        {
          "objects": [
            {
              "label": "object_type",
              "bbox": {"x": x_coordinate, "y": y_coordinate, "width": width, "height": height},
              "confidence": 0.95
            }
          ],
          "count": total_objects,
          "confidence": overall_confidence
        }
        Coordinates should be normalized to 0-1 range relative to image dimensions.
      PROMPT
    }
    
    # User message with image
    content = [
      { type: 'text', text: "Detect #{query} in this image and provide bounding boxes." },
      { type: 'image', image: image }
    ]
    
    messages << {
      role: 'user',
      content: content
    }
    
    # Call the LM with multimodal content
    forward(
      query: query,
      image_description: "Aerial image for object detection"
    )
  end
end

# Main example
def main
  # Initialize DSPy with a vision-capable model
  DSPy.config.lm = DSPy::LM.new(
    'openai/gpt-4o-mini',  # or 'anthropic/claude-3-5-sonnet-20241022'
    api_key: ENV['OPENAI_API_KEY'] || ENV['ANTHROPIC_API_KEY']
  )
  
  # Example 1: Detect objects in an aerial airport image
  puts "Example 1: Detecting airplanes in an aerial airport image"
  puts "-" * 60
  
  # Using a public domain aerial image of an airport
  airport_image = DSPy::Image.new(
    url: 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3d/KSFO_from_above.jpg/1280px-KSFO_from_above.jpg'
  )
  
  detector = ObjectDetector.new
  result = detector.detect(airport_image, 'airplanes')
  
  puts "Detection Results:"
  puts "  Total airplanes detected: #{result.count}"
  puts "  Overall confidence: #{(result.confidence * 100).round(1)}%"
  puts "\nBounding Boxes:"
  
  result.objects.each_with_index do |obj, i|
    puts "  #{i + 1}. #{obj[:label]}"
    puts "     Position: (#{obj[:bbox][:x]}, #{obj[:bbox][:y]})"
    puts "     Size: #{obj[:bbox][:width]} x #{obj[:bbox][:height]}"
    puts "     Confidence: #{(obj[:confidence] * 100).round(1)}%"
  end
  
  # Example 2: Using base64 encoded image
  puts "\n" + "=" * 60
  puts "Example 2: Detecting objects in a base64 encoded image"
  puts "-" * 60
  
  # Load a local image and encode it
  if File.exist?('sample_image.jpg')
    image_data = File.read('sample_image.jpg', mode: 'rb')
    base64_image = Base64.strict_encode64(image_data)
    
    local_image = DSPy::Image.new(
      base64: base64_image,
      content_type: 'image/jpeg'
    )
    
    result = detector.detect(local_image, 'vehicles')
    
    puts "Detection Results:"
    puts "  Total vehicles detected: #{result.count}"
    puts "  Overall confidence: #{(result.confidence * 100).round(1)}%"
  else
    puts "  (Skipping: No local image file found)"
  end
  
  # Example 3: Multiple object types
  puts "\n" + "=" * 60
  puts "Example 3: Detecting multiple object types"
  puts "-" * 60
  
  # Using a street scene image
  street_image = DSPy::Image.new(
    url: 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c0/Shibuya_Crossing_2023.jpg/1280px-Shibuya_Crossing_2023.jpg'
  )
  
  result = detector.detect(street_image, 'people, cars, traffic lights, and buildings')
  
  puts "Detection Results:"
  puts "  Total objects detected: #{result.count}"
  puts "  Overall confidence: #{(result.confidence * 100).round(1)}%"
  
  # Group by object type
  grouped = result.objects.group_by { |obj| obj[:label] }
  puts "\nObjects by type:"
  grouped.each do |label, objects|
    puts "  #{label}: #{objects.count}"
  end
end

if __FILE__ == $0
  main
end