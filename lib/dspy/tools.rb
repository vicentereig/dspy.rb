# frozen_string_literal: true

module DSPy
  # Example tools for use with ReACT
  module Tools
    # Calculator tool for evaluating mathematical expressions
    class Calculator
      def self.call(expression:)
        begin
          eval(expression).to_s
        rescue => e
          "Error evaluating expression: #{e.message}"
        end
      end

      def self.name
        "calculator"
      end
    end

    # Weather tool for getting weather information
    class WeatherTool
      def self.call(location:)
        # This is a mock implementation
        weather_data = {
          "New York" => "Sunny, 75°F",
          "London" => "Rainy, 60°F",
          "Tokyo" => "Cloudy, 70°F",
          "Sydney" => "Clear, 80°F"
        }

        weather_data[location] || "Weather data not available for #{location}"
      end

      def self.name
        "weather"
      end
    end

    # Search tool for retrieving information
    class SearchTool
      def self.call(query:)
        # This is a mock implementation
        search_data = {
          "ruby programming" => "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity.",
          "dspy framework" => "DSPy is a framework for programming with foundation models using techniques like chain-of-thought reasoning.",
          "react pattern" => "ReACT (Reasoning and Acting) is a pattern that combines reasoning and acting in an interleaved manner."
        }

        search_data[query.downcase] || "No information found for '#{query}'"
      end

      def self.name
        "search"
      end
    end

    # Helper method to create tool instances
    def self.create_calculator_tool
      Tool.new(
        Calculator,
        name: "calculator",
        desc: "Evaluates a mathematical expression and returns the result",
        args: { expression: "string" }
      )
    end

    def self.create_weather_tool
      Tool.new(
        WeatherTool,
        name: "weather",
        desc: "Gets the current weather for a location",
        args: { location: "string" }
      )
    end

    def self.create_search_tool
      Tool.new(
        SearchTool,
        name: "search",
        desc: "Searches for information on a given query",
        args: { query: "string" }
      )
    end

    # Get all example tools
    def self.all_tools
      [
        create_calculator_tool,
        create_weather_tool,
        create_search_tool
      ]
    end
  end
end
