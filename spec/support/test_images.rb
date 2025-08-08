# frozen_string_literal: true

require 'zlib'

module TestImages
  module_function
  
  # Creates a valid minimal PNG image of a single color
  # Based on PNG specification: http://www.libpng.org/pub/png/spec/1.2/PNG-Structure.html
  def create_solid_color_png(color: :red, width: 16, height: 16)
    # PNG signature
    png_signature = [137, 80, 78, 71, 13, 10, 26, 10].pack('C*')
    
    # IHDR chunk (Image Header)
    ihdr_data = [
      width,           # Width (4 bytes)
      height,          # Height (4 bytes)
      8,              # Bit depth (1 byte)
      2,              # Color type: 2 = RGB (1 byte)
      0,              # Compression method (1 byte)
      0,              # Filter method (1 byte)
      0               # Interlace method (1 byte)
    ].pack('N2C5')
    
    ihdr_chunk = create_chunk('IHDR', ihdr_data)
    
    # IDAT chunk (Image Data)
    # Create uncompressed RGB pixel data
    rgb_values = case color
                 when :red
                   [255, 0, 0]
                 when :green
                   [0, 255, 0]
                 when :blue
                   [0, 0, 255]
                 when :white
                   [255, 255, 255]
                 when :black
                   [0, 0, 0]
                 else
                   [128, 128, 128] # gray
                 end
    
    # Build scanlines with filter byte (0 = no filter)
    scanlines = String.new
    height.times do
      scanlines << "\x00" # Filter type = None
      width.times do
        scanlines << rgb_values.pack('C*')
      end
    end
    
    # Compress the pixel data
    compressed_data = Zlib::Deflate.deflate(scanlines, Zlib::BEST_COMPRESSION)
    idat_chunk = create_chunk('IDAT', compressed_data)
    
    # IEND chunk (Image End)
    iend_chunk = create_chunk('IEND', '')
    
    # Combine all chunks
    png_signature + ihdr_chunk + idat_chunk + iend_chunk
  end
  
  # Create a PNG chunk with proper CRC
  def create_chunk(type, data)
    length = [data.bytesize].pack('N')
    type_and_data = type + data
    crc = [Zlib.crc32(type_and_data)].pack('N')
    length + type_and_data + crc
  end
  
  # Create a simple test pattern PNG (checkerboard)
  def create_checkerboard_png(width: 16, height: 16)
    png_signature = [137, 80, 78, 71, 13, 10, 26, 10].pack('C*')
    
    ihdr_data = [width, height, 8, 2, 0, 0, 0].pack('N2C5')
    ihdr_chunk = create_chunk('IHDR', ihdr_data)
    
    # Create checkerboard pattern
    scanlines = String.new
    height.times do |y|
      scanlines << "\x00" # Filter type
      width.times do |x|
        if (x / 4 + y / 4).even?
          scanlines << [255, 255, 255].pack('C*') # White
        else
          scanlines << [0, 0, 0].pack('C*') # Black
        end
      end
    end
    
    compressed_data = Zlib::Deflate.deflate(scanlines, Zlib::BEST_COMPRESSION)
    idat_chunk = create_chunk('IDAT', compressed_data)
    iend_chunk = create_chunk('IEND', '')
    
    png_signature + ihdr_chunk + idat_chunk + iend_chunk
  end
  
  # Returns a minimal 1x1 pixel PNG for the lightest possible image
  def create_minimal_png(color: :red)
    create_solid_color_png(color: color, width: 1, height: 1)
  end
  
  # Returns base64 encoded version of the PNG
  def create_base64_png(color: :red, width: 16, height: 16)
    png_data = create_solid_color_png(color: color, width: width, height: height)
    Base64.strict_encode64(png_data)
  end
end