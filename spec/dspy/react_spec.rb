# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::ReAct' do
  it 'answers a question' do
    # Configure DSPy
    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
    end


    class GetTodaysDate < DSPy::Tools::Tool
      def initialize
        super('get_todays_date', 'Get today\'s date')
      end

      def call(input = nil)
        Date.today.to_s
      end
    end

    class AddNumbers < DSPy::Tools::Tool
      def initialize
        super('add_numbers', 'Add two numbers together')
      end

      def call(input)
        # Expecting input like "5,10" or "5, 10"
        numbers = input.split(',').map(&:strip).map(&:to_f)

        if numbers.length != 2
          raise ArgumentError, "Expected exactly 2 numbers separated by comma, got: #{input}"
        end

        numbers.sum.to_s
      end
    end

    # Create tools
    date_tool = GetTodaysDate.new
    add_tool = AddNumbers.new

    # Create agent and ask questions
    result = nil
    VCR.use_cassette('openai/gpt4o-mini/react_agent_answers_question') do
      agent = DSPy::ReActAgent.new(tools: [date_tool, add_tool])
      result = agent.forward("What is 42 plus 58?")
    end

    expect(result[:answer]).to eq("100")
  end
end
