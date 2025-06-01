# frozen_string_literal: true

# Tool that adds two numbers together
class SorbetAddNumbers < DSPy::Tools::SorbetTool
  extend T::Sig

  tool_name 'add_numbers'
  tool_description 'Adds two numbers together'

  sig { params(x: Numeric, y: Numeric).returns(Numeric) }
  def call(x:, y:)
    x + y
  end
end
