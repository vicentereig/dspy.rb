#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dspy'
require 'json'

# Example: Bounding Box Detection in Aerial Images
# This example demonstrates how to use DSPy's multimodal capabilities
# to detect objects in images and return structured bounding box data

# Define structured types for bounding box detection
class BoundingBox < T::Struct
  const :x, Float
  const :y, Float
  const :width, Float
  const :height, Float
end

class DetectedObject < T::Struct
  const :label, String
  const :bbox, BoundingBox
  const :confidence, Float
end

# Define a signature for bounding box detection
class BoundingBoxDetection < DSPy::Signature
  description "Detect and locate objects in images with normalized bounding box coordinates"

  class DetailLevel < T::Enum
    enums do
      Basic = new('basic')
      Standard = new('standard')
      Detailed = new('detailed')
    end
  end

  input do
    const :query, T.any(String, NilClass), description: 'Object to detect (e.g., "airplanes", "cars")'
    const :image, DSPy::Image, description: 'Image to analyze for object detection'
    const :detail_level, DetailLevel, default: DetailLevel::Standard, description: 'Detection detail level'
  end
  
  # Output structured bounding box data with type-safe structs
  output do
    const :objects, T::Array[DetectedObject], description: 'Array of detected objects with bounding boxes'
    const :count, Integer, description: 'Total number of objects detected'
    const :confidence, Float, description: 'Overall confidence in the detection (0.0-1.0)'
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
  
  detector = DSPy::Predict.new(BoundingBoxDetection)
  detection = detector.call(
    query: 'airplanes',
    image: airport_image,
    detail_level: BoundingBoxDetection::DetailLevel::Detailed
  )
  
  puts "Detection Results:"
  puts "  Total airplanes detected: #{detection.count}"
  puts "  Overall confidence: #{(detection.confidence * 100).round(1)}%"
  puts "\nBounding Boxes:"
  
  detection.objects.each_with_index do |obj, i|
    puts "  #{i + 1}. #{obj.label}"
    puts "     Position: (#{obj.bbox.x}, #{obj.bbox.y})"
    puts "     Size: #{obj.bbox.width} x #{obj.bbox.height}"
    puts "     Confidence: #{(obj.confidence * 100).round(1)}%"
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
    
    vehicle_detection = detector.call(
      query: 'vehicles',
      image: local_image,
      detail_level: BoundingBoxDetection::DetailLevel::Standard
    )
    
    puts "Detection Results:"
    puts "  Total vehicles detected: #{vehicle_detection.count}"
    puts "  Overall confidence: #{(vehicle_detection.confidence * 100).round(1)}%"
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
  
  street_detection = detector.call(
    query: 'people, cars, traffic lights, and buildings',
    image: street_image,
    detail_level: BoundingBoxDetection::DetailLevel::Detailed
  )
  
  puts "Detection Results:"
  puts "  Total objects detected: #{street_detection.count}"
  puts "  Overall confidence: #{(street_detection.confidence * 100).round(1)}%"
  
  # Group by object type
  grouped = street_detection.objects.group_by { |obj| obj.label }
  puts "\nObjects by type:"
  grouped.each do |label, objects|
    puts "  #{label}: #{objects.count}"
  end
end

if __FILE__ == $0
  main
end