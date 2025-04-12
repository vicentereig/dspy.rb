#!/usr/bin/env ruby
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'dotenv'
  gem 'async'
  gem 'async-http'
end

require 'dotenv/load'
require 'async'
require 'async/http/internet'
require 'json'

# Retrieve the API key from .env.
api_key = ENV['OPENAI_API_KEY']
if api_key.nil? || api_key.strip.empty?
  abort "Please set your OPENAI_API_KEY in your .env file."
end

# Build the payload (mirroring your curl command).
payload = {
  "model" => "gpt-4o-mini-2024-07-18",
  "messages" => [
    { "role" => "system", "content" => "You are a helpful math tutor." },
    { "role" => "user", "content" => "Solve 8x + 31 = 2." }
  ],
  "response_format" => {
    "type" => "json_schema",
    "json_schema" => {
      "name" => "math_response",
      "strict" => true,
      "schema" => {
        "type" => "object",
        "properties" => {
          "steps" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "explanation" => { "type" => "string" },
                "output" => { "type" => "string" }
              },
              "required" => ["explanation", "output"],
              "additionalProperties" => false
            }
          },
          "final_answer" => { "type" => "string" }
        },
        "required" => ["steps", "final_answer"],
        "additionalProperties" => false
      }
    }
  },
  "temperature" => 0.7,
  "stream" => true
}

payload_json = JSON.dump(payload)

# Merge a parsed fragment into our overall result.
def merge_fragment!(result, fragment)
  if fragment["steps"]
    result["steps"] ||= []
    # Assuming each fragment's "steps" is an array:
    result["steps"].concat(fragment["steps"])
  end
  if fragment["final_answer"]
    result["final_answer"] = fragment["final_answer"]
  end
end

Async do |task|
  internet = Async::HTTP::Internet.new
  begin
    response = internet.post(
      "https://api.openai.com/v1/chat/completions",
      {
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{api_key}"
      },
      [payload_json]
    )

    puts "Streaming response chunks..."
    final_output = {}
    buffer = ""

    response.each do |chunk|
      # Append the chunk to our temporary buffer.
      buffer << chunk

      # Split the buffer into lines. (The stream is expected to be newline-delimited.)
      lines = buffer.split("\n")
      # Leave the last partial line in the buffer (if any).
      buffer = lines.pop || ""

      lines.each do |line|
        line.strip!
        next if line.empty?
        puts "line: #{line}"
        # Check if we've reached the end of stream.
        if line == "data: [DONE]"
          puts "Stream complete."
          next
        end

        # Remove a "data:" prefix if present.
        line = line.sub(/^data:\s*/, "")

        # Attempt to parse the line as JSON.
        begin
          fragment = JSON.parse(line)
          merge_fragment!(final_output, fragment)
          puts "Updated output:"
          puts JSON.pretty_generate(final_output)
        rescue JSON::ParserError => e
          # If parsing fails, it might be because the JSON is split.
          # We put it back into our buffer for the next chunk.
          buffer = line + buffer
        end
      end
    end

    # Final attempt in case any remaining buffered content forms valid JSON.
    unless buffer.empty?
      begin
        fragment = JSON.parse(buffer)
        merge_fragment!(final_output, fragment)
      rescue JSON::ParserError
        # If still not valid, ignore or log as needed.
      end
    end

    if final_output.empty?
      puts "No complete JSON could be reconstructed from stream."
    else
      puts "Final reconstructed JSON:"
      puts JSON.pretty_generate(final_output)
    end
  ensure
    internet.close
  end
end
