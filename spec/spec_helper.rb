# Disable observability completely in tests to prevent OpenTelemetry/WebMock conflicts
ENV['DSPY_DISABLE_OBSERVABILITY'] = 'true'

require 'byebug'
require 'dotenv/load'
require 'vcr'
require 'webmock/rspec'

require 'dspy'

require 'newrelic_rpm'

NewRelic::Agent.manual_start

# Disable observability during tests to avoid telemetry overhead
DSPy::Observability.reset!

# Load support files and tools
Dir[File.join(File.dirname(__FILE__), 'support', '**', '*.rb')].sort.each { |f| require f }

DSPy.configure do |c|
  c.logger = Dry.Logger(:dspy, formatter: :string) { |s| s.add_backend(stream: "log/test.log") }
end

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
  # Restore original WebMock settings but allow telemetry endpoints
  if original_allow_setting
    WebMock.allow_net_connect!
  else
    # Block all network connections - no telemetry allowed in tests
    WebMock.disable_net_connect!
  end
end

def require_api_key!
  skip "Requires API key to be set: #{api_key_name}" unless ENV[api_key_name]
end

VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # No telemetry services ignored - block everything

  # Filter out sensitive information
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }
  config.filter_sensitive_data('<GEMINI_API_KEY>') { ENV['GEMINI_API_KEY'] }
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV['OPENROUTER_API_KEY'] }
  config.filter_sensitive_data('<NEW_RELIC_LICENSE_KEY>') { ENV['NEW_RELIC_LICENSE_KEY'] }

  # Filter out sensitive headers and response data
  # Organization IDs in OpenAI responses
  config.filter_sensitive_data('<OPENAI_ORGANIZATION>') do |interaction|
    if interaction.response.headers['Openai-Organization']
      interaction.response.headers['Openai-Organization'].first
    end
  end

  # Organization IDs in Anthropic responses
  config.filter_sensitive_data('<ANTHROPIC_ORGANIZATION>') do |interaction|
    if interaction.response.headers['Anthropic-Organization']
      interaction.response.headers['Anthropic-Organization'].first
    end
  end

  # Request IDs that might be sensitive
  config.filter_sensitive_data('<REQUEST_ID>') do |interaction|
    if interaction.response.headers['X-Request-Id']
      interaction.response.headers['X-Request-Id'].first
    end
  end

  # Filter out cookies - use a more comprehensive approach
  config.before_record do |interaction|
    # Redact Set-Cookie headers
    if interaction.response.headers['Set-Cookie']
      interaction.response.headers['Set-Cookie'] = interaction.response.headers['Set-Cookie'].map do |cookie|
        # Keep only the cookie name, redact the value
        cookie_name = cookie.split('=').first
        "#{cookie_name}=<REDACTED>"
      end
    end

    # Redact organization IDs (backup approach)
    if interaction.response.headers['Openai-Organization']
      interaction.response.headers['Openai-Organization'] = ['<OPENAI_ORGANIZATION>']
    end

    if interaction.response.headers['Anthropic-Organization']
      interaction.response.headers['Anthropic-Organization'] = ['<ANTHROPIC_ORGANIZATION>']
    end

    # Redact request IDs
    if interaction.response.headers['X-Request-Id']
      interaction.response.headers['X-Request-Id'] = ['<REQUEST_ID>']
    end

    # Filter NewRelic license keys in URLs
    if interaction.request.uri.include?('newrelic.com') && interaction.request.uri.include?('license_key=')
      interaction.request.uri = interaction.request.uri.gsub(/license_key=[^&]+/, 'license_key=<NEW_RELIC_LICENSE_KEY>')
    end
  end
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
