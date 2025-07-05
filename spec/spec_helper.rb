require 'byebug'
require 'dotenv/load'
require 'vcr'
require 'webmock/rspec'

require 'dspy'

# Load support files and tools
Dir[File.join(File.dirname(__FILE__), 'support', '**', '*.rb')].sort.each { |f| require f }

DSPy.configure do |c|
  c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
  
  # Enable instrumentation for tests
  c.instrumentation.enabled = true
  c.instrumentation.subscribers = [:logger]
end

# Setup instrumentation subscribers
DSPy::Instrumentation.setup_subscribers

# Pre-download embedding model for tests
begin
  require 'dspy/memory/local_embedding_engine'
  
  # Allow HTTP connections temporarily to download the model
  original_allow_setting = WebMock.net_connect_allowed?
  WebMock.allow_net_connect!
  
  # Pre-download the model so it's available for tests
  DSPy::Memory::LocalEmbeddingEngine.new
  
  puts "✓ Embedding model pre-downloaded successfully"
rescue => e
  puts "⚠ Could not pre-download embedding model: #{e.message}"
ensure
  # Restore original WebMock settings
  if original_allow_setting
    WebMock.allow_net_connect!
  else
    WebMock.disable_net_connect!
  end
end

VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter out sensitive information
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  
  # Store and restore DSPy configuration to prevent test interference
  config.before(:each) do |example|
    # Save original configuration before each test
    @original_dspy_config = if defined?(DSPy) && DSPy.respond_to?(:config) && DSPy.config
                             {
                               lm: DSPy.config.lm,
                               logger: DSPy.config.logger
                             }
                           else
                             nil
                           end
  end
  
  config.after(:each) do |example|
    # Restore original configuration after each test unless it's an integration test
    if @original_dspy_config && !example.metadata[:vcr]
      DSPy.configure do |config|
        config.lm = @original_dspy_config[:lm] if @original_dspy_config[:lm]
        config.logger = @original_dspy_config[:logger] if @original_dspy_config[:logger]
      end
    end
  end
end
