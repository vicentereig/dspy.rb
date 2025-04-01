# frozen_string_literal: true

module DSPy
  class Tool
    attr_reader :name, :desc, :func, :args, :arg_types

    def initialize(func, name: nil, desc: nil, args: {}, arg_types: {})
      @func = func
      @name = name || (func.respond_to?(:name) ? func.name : "unnamed_tool")
      @desc = desc
      @args = args
      @arg_types = arg_types
    end

    def call(**kwargs)
      @func.call(**kwargs)
    rescue => e
      "Failed to execute: #{e}"
    end
  end
end
