# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  class FewShotExample
    extend T::Sig

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :input

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :output

    sig { returns(T.nilable(String)) }
    attr_reader :reasoning

    sig do
      params(
        input: T::Hash[Symbol, T.untyped],
        output: T::Hash[Symbol, T.untyped],
        reasoning: T.nilable(String)
      ).void
    end
    def initialize(input:, output:, reasoning: nil)
      @input = input.freeze
      @output = output.freeze
      @reasoning = reasoning
    end

    sig { returns(String) }
    def to_prompt_section
      sections = []
      
      sections << "## Input"
      sections << "```json"
      sections << JSON.pretty_generate(@input)
      sections << "```"
      
      if @reasoning
        sections << "## Reasoning"
        sections << @reasoning
      end
      
      sections << "## Output"
      sections << "```json"
      sections << JSON.pretty_generate(@output)
      sections << "```"
      
      sections.join("\n")
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      result = {
        input: @input,
        output: @output
      }
      result[:reasoning] = @reasoning if @reasoning
      result
    end

    sig { params(hash: T::Hash[Symbol, T.untyped]).returns(FewShotExample) }
    def self.from_h(hash)
      new(
        input: hash[:input] || {},
        output: hash[:output] || {},
        reasoning: hash[:reasoning]
      )
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      return false unless other.is_a?(FewShotExample)
      
      @input == other.input &&
        @output == other.output &&
        @reasoning == other.reasoning
    end
  end
end