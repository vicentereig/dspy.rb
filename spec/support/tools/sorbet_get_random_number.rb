# frozen_string_literal: true

# Tool that generates a random number within a specified range
class SorbetGetRandomNumber < DSPy::Tools::SorbetTool
  extend T::Sig

  tool_name 'get_random_number'
  tool_description 'Generates a random number within a specified range'

  sig { params(min: Numeric, max: Numeric).returns(Numeric) }
  def call(min: 0, max: 100)
    rand(min..max)
  end
end
