# frozen_string_literal: true

# Load all tool files
Dir[File.join(__dir__, 'tools', '*.rb')].sort.each { |f| require f }
