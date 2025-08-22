# frozen_string_literal: true
require 'sorbet-runtime'
require 'dry-configurable'
require 'dry/logger'
require 'securerandom'

require_relative 'dspy/version'
require_relative 'dspy/errors'
require_relative 'dspy/type_serializer'
require_relative 'dspy/observability'
require_relative 'dspy/context'

module DSPy
  extend Dry::Configurable
  
  setting :lm
  setting :logger, default: Dry.Logger(:dspy, formatter: :string)
  
  # Structured output configuration for LLM providers
  setting :structured_outputs do
    setting :openai, default: false
    setting :anthropic, default: false  # Reserved for future use
    setting :strategy, default: nil  # Can be DSPy::Strategy::Strict, DSPy::Strategy::Compatible, or nil for auto
    setting :retry_enabled, default: true
    setting :max_retries, default: 3
    setting :fallback_enabled, default: true
  end
  
  # Test mode disables sleeps in retry logic
  setting :test_mode, default: false

  def self.logger
    @logger ||= create_logger
  end

  def self.log(event, **attributes)
    return unless logger
    
    # Merge context automatically (but don't include span_stack)
    context = Context.current.dup
    context.delete(:span_stack)
    attributes = context.merge(attributes)
    attributes[:event] = event
    
    # Use Dry::Logger's structured logging
    logger.info(attributes)
  end

  def self.create_logger
    env = ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
    log_output = ENV['DSPY_LOG'] # Allow override
    
    case env
    when 'test'
      # Test: key=value format to log/test.log (or override)
      Dry.Logger(:dspy, formatter: :string) do |config|
        config.add_backend(stream: log_output || "log/test.log")
      end
    when 'development'
      # Development: key=value format to log/development.log (or override)
      Dry.Logger(:dspy, formatter: :string) do |config|
        config.add_backend(stream: log_output || "log/development.log")
      end
    when 'production', 'staging'
      # Production: JSON to STDOUT (or override)
      Dry.Logger(:dspy, formatter: :json) do |config|
        config.add_backend(stream: log_output || $stdout)
      end
    else
      # Fallback: key=value to STDOUT
      Dry.Logger(:dspy, formatter: :string) do |config|
        config.add_backend(stream: log_output || $stdout)
      end
    end
  end

  # Fiber-local LM context for temporary model overrides
  FIBER_LM_KEY = :dspy_fiber_lm

  def self.current_lm
    Fiber[FIBER_LM_KEY] || config.lm
  end

  def self.with_lm(lm)
    previous_lm = Fiber[FIBER_LM_KEY]
    Fiber[FIBER_LM_KEY] = lm
    yield
  ensure
    Fiber[FIBER_LM_KEY] = previous_lm
  end
end

require_relative 'dspy/module'
require_relative 'dspy/field'
require_relative 'dspy/signature'
require_relative 'dspy/few_shot_example'
require_relative 'dspy/prompt'
require_relative 'dspy/example'
require_relative 'dspy/lm'
require_relative 'dspy/image'
require_relative 'dspy/strategy'
require_relative 'dspy/prediction'
require_relative 'dspy/predict'
require_relative 'dspy/chain_of_thought'
require_relative 'dspy/re_act'
require_relative 'dspy/code_act'
require_relative 'dspy/evaluate'
require_relative 'dspy/teleprompt/teleprompter'
require_relative 'dspy/teleprompt/utils'
require_relative 'dspy/teleprompt/data_handler'
require_relative 'dspy/propose/grounded_proposer'
require_relative 'dspy/teleprompt/simple_optimizer'
require_relative 'dspy/teleprompt/mipro_v2'
require_relative 'dspy/tools'
require_relative 'dspy/memory'
require_relative 'dspy/storage/program_storage'
require_relative 'dspy/storage/storage_manager'
require_relative 'dspy/registry/signature_registry'
require_relative 'dspy/registry/registry_manager'

# Auto-configure observability if Langfuse env vars are present
DSPy::Observability.configure!

# LoggerSubscriber will be lazy-initialized when first accessed

# Detect potential gem conflicts and warn users
# DSPy uses the official openai gem, warn if ruby-openai (community version) is detected
if defined?(OpenAI) && defined?(OpenAI::Client) && !defined?(OpenAI::Internal)
  warn <<~WARNING
    WARNING: ruby-openai gem detected. This may cause conflicts with DSPy's OpenAI integration.
    
    DSPy uses the official 'openai' gem. The community 'ruby-openai' gem uses the same
    OpenAI namespace and will cause conflicts.
    
    To fix this, remove 'ruby-openai' from your Gemfile and use the official gem instead:
    - Remove: gem 'ruby-openai'
    - Keep: gem 'openai' (official SDK that DSPy uses)
    
    The official gem provides better compatibility and is actively maintained by OpenAI.
  WARNING
end
