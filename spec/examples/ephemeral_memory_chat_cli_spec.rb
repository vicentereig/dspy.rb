# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'EphemeralMemoryChat CLI', type: :aruba do
  let(:script_path) { File.expand_path('../../examples/ephemeral_memory_chat.rb', __dir__) }

  before do
    set_environment_variable('DSPY_FAKE_CHAT', '1')
    set_environment_variable('OPENAI_API_KEY', 'demo')
  end

  it 'renders transcript frames and persists memory summary' do
    run_command("bundle exec ruby #{script_path}")
    last_command_started.write("hello router\n")
    last_command_started.write("exit\n")
    last_command_started.stop

    output = last_command_started.output
    expect(output).to include('Ephemeral Memory Chat')
    expect(output).to include('Stored Memory Turns')
    expect(output).to include('hello router')
  end
end
