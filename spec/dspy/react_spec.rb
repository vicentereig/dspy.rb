# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DSPy::ReACT' do
  let(:calculator_tool) { DSPy::Tools.create_calculator_tool }
  let(:weather_tool) { DSPy::Tools.create_weather_tool }
  let(:search_tool) { DSPy::Tools.create_search_tool }

  xit 'answers a question' do
    # class DeepQA < DSPy::Signature
    #   description "Answers the question."
    #
    #   input do
    #     required(:question)
    #       .value(:string)
    #       .meta(description: 'The question you are looking answers for.')
    #   end
    #
    #   output do
    #     required(:answer).value(:string)
    #                          .meta(description: 'The answer to the original question')
    #   end
    # end
    #
    # react_agent = DSPy::ReACT(DeepQA)

    # TODO: the react_prediction extends the originating one
    # prediction = react_agent.call(question='Cual es la poblacion de España?')

    # prediction.trajectory
    # prediction.answer


  end
end
