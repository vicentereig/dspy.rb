# frozen_string_literal: true

module DSPy
  # Define the tools available to the agent
  module Tools
    class Tool
      attr_reader :name, :description

      def initialize(name, description)
        @name = name
        @description = description
      end

      def call(input)
        raise NotImplementedError, "Subclasses must implement the call method"
      end
    end
  end
end
