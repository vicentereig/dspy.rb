# frozen_string_literal: true

# Tool that generates a random number within a specified range
class SorbetGetRandomNumber < DSPy::Tools::Base
  extend T::Sig

  tool_name 'get_random_number'
  tool_description 'Generates a random number within a specified range'

  sig { params(min: Integer, max: Integer).returns(Integer) }
  def call(min: 1, max: 100)
    rand(min..max)
  end
end
