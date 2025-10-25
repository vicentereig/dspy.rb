require 'spec_helper'
require 'dspy/code_act'
require 'dspy/o11y'

RSpec.describe 'CodeAct observability integration' do
  it 'maps CodeAct modules to Agent observation type' do
    expect(DSPy::ObservationType.for_module_class(DSPy::CodeAct)).to eq(DSPy::ObservationType::Agent)
  end
end
