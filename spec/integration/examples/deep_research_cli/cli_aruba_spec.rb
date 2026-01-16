# frozen_string_literal: true

require "spec_helper"
require "shellwords"
require "timeout"

RSpec.describe "Deep Research CLI", type: :aruba do
  let(:script_path) { File.expand_path("../../../../examples/deep_research_cli/chat.rb", __dir__) }

  it "produces a report in dry-run mode" do
    set_environment_variable("TERM", "dumb")

    command = "bundle exec ruby #{Shellwords.escape(script_path)} --dry-run"
    run_command(command)

    last_command_started.write("Explain the test harness\n")
    sleep 1

    last_command_started.write("\n")
    last_command_started.stop(10)

    output = strip_ansi(last_command_started.output)

    expect(output).to include("Dry-run report for Explain the test harness")
    expect(output).to include("Status: Completed")
  end

  def strip_ansi(text)
    text.gsub(/\e\[[0-9;?]*[A-Za-z]/, "").delete("\r")
  end

  # Helper retained for future assertions
  def wait_for_output(command, pattern, timeout: 10)
    Timeout.timeout(timeout) do
      loop do
        output = strip_ansi(command.output)
        break if pattern.match?(output)

        sleep 0.1
      end
    end
  end
end
