# frozen_string_literal: true

# Tool that returns the current date in a human-readable format
class SorbetGetTodaysDate < DSPy::Tools::SorbetTool
  extend T::Sig

  tool_name 'get_todays_date'
  tool_description 'Returns the current date in a human-readable format'

  sig { returns(String) }
  def call
    Date.today.strftime("%B %d, %Y")
  end
end
