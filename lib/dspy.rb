# frozen_string_literal: true
require_relative 'dspy/support/warning_filters'
require 'sorbet-runtime'
require 'dry-configurable'
require 'dry/logger'
require 'securerandom'

require_relative 'dspy/version'
require_relative 'dspy/errors'
require_relative 'dspy/type_serializer'
require_relative 'dspy/observability'
require_relative 'dspy/context'
require_relative 'dspy/events'
require_relative 'dspy/events/types'
require_relative 'dspy/reflection_lm'

module DSPy
  extend Dry::Configurable

  setting :lm
  setting :logger, default: Dry.Logger(:dspy, formatter: :string)

  # Structured output configuration for LLM providers
  setting :structured_outputs do
    setting :openai, default: false
    setting :anthropic, default: false  # Reserved for future use
  end

  def self.logger
    @logger ||= create_logger
  end

  # Writes structured output to the configured logger. Use this for human-readable
  # logs only—listeners and telemetry exporters are not triggered by `DSPy.log`.
  # Prefer `DSPy.event` whenever you want consumers (or Langfuse/OpenTelemetry)
  # to react to what happened.
  def self.log(event_name, **attributes)
    # Return nil early if logger is not configured (backward compatibility)
    return nil unless logger

    # Direct logging - simple and straightforward
    emit_log(event_name, attributes)

    # Return nil to maintain backward compatibility
    nil
  end

  # Emits a structured event that flows through DSPy's event bus, fires any
  # subscribed listeners, and creates OpenTelemetry spans when observability
  # is enabled. Use this for anything that should be tracked, instrumented,
  # or forwarded to Langfuse.
  def self.event(event_name_or_object, attributes = {})
    # Handle typed event objects
    if event_name_or_object.respond_to?(:name) && event_name_or_object.respond_to?(:to_attributes)
      event_obj = event_name_or_object
      event_name = event_obj.name
      attributes = event_obj.to_attributes

      # For LLM events, use OpenTelemetry semantic conventions for spans
      if event_obj.is_a?(DSPy::Events::LLMEvent)
        otel_attributes = event_obj.to_otel_attributes
        create_event_span(event_name, otel_attributes)
      else
        create_event_span(event_name, attributes)
      end
    else
      # Handle string event names (backward compatibility)
      event_name = event_name_or_object
      raise ArgumentError, "Event name cannot be nil" if event_name.nil?

      # Handle nil attributes
      attributes = {} if attributes.nil?

      # Create OpenTelemetry span for the event if observability is enabled
      create_event_span(event_name, attributes)
    end

    attributes = attributes.dup
    module_metadata = DSPy::Context.module_context_attributes
    attributes.merge!(module_metadata) unless module_metadata.empty?

    # Perform the actual logging (original DSPy.log behavior)
    # emit_log(event_name, attributes)

    # Notify event listeners
    events.notify(event_name, attributes)
  end

  def self.events
    @event_registry ||= DSPy::EventRegistry.new.tap do |registry|
      # Subscribe logger to all events - use a proc that calls logger each time
      # to support mocking in tests
      registry.subscribe('*') { |event_name, attributes| 
        emit_log(event_name, attributes) if logger
      }
    end
  end

  private

  def self.emit_log(event_name, attributes)
    return unless logger

    # Merge context automatically (but don't include span_stack)
    context = Context.current.dup
    context.delete(:span_stack)
    context.delete(:otel_span_stack)
    context.delete(:module_stack)
    attributes = context.merge(attributes)
    attributes[:event] = event_name

    # Use Dry::Logger's structured logging
    logger.info(attributes)
  end

  # Internal events that should not create OpenTelemetry spans
  INTERNAL_EVENTS = [
    'span.start',
    'span.end',
    'span.attributes',
    'observability.disabled',
    'observability.error',
    'observability.span_error',
    'observability.span_finish_error',
    'event.span_creation_error',
    'lm.tokens'
  ].freeze

  def self.create_event_span(event_name, attributes)
    return unless DSPy::Observability.enabled?
    return if INTERNAL_EVENTS.include?(event_name)

    begin
      # Flatten nested hashes for OpenTelemetry span attributes
      flattened_attributes = flatten_attributes(attributes)

      # Create and immediately finish a span for this event
      # Events are instant moments in time, not ongoing operations
      span = DSPy::Observability.start_span(event_name, flattened_attributes)
      DSPy::Observability.finish_span(span) if span
    rescue => e
      # Log error but don't let it break the event system
      # Use emit_log directly to avoid infinite recursion
      emit_log('event.span_creation_error', {
        error_class: e.class.name,
        error_message: e.message,
        event_name: event_name
      })
    end
  end

  def self.flatten_attributes(attributes, parent_key = '', result = {})
    attributes.each do |key, value|
      new_key = parent_key.empty? ? key.to_s : "#{parent_key}.#{key}"

      if value.is_a?(Hash)
        flatten_attributes(value, new_key, result)
      else
        result[new_key] = value
      end
    end

    result
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

require_relative 'dspy/callbacks'
require_relative 'dspy/module'
require_relative 'dspy/field'
require_relative 'dspy/signature'
require_relative 'dspy/few_shot_example'
require_relative 'dspy/prompt'
require_relative 'dspy/example'
require_relative 'dspy/lm'
require_relative 'dspy/image'
require_relative 'dspy/prediction'
require_relative 'dspy/predict'
require_relative 'dspy/events/subscribers'
require_relative 'dspy/events/subscriber_mixin'
require_relative 'dspy/chain_of_thought'
require_relative 'dspy/re_act'
require_relative 'dspy/evals'
require_relative 'dspy/teleprompt/teleprompter'
require_relative 'dspy/teleprompt/utils'
require_relative 'dspy/teleprompt/data_handler'
require_relative 'dspy/propose/grounded_proposer'
begin
  require 'dspy/o11y/langfuse'
rescue LoadError
end
begin
  require 'dspy/gepa'
rescue LoadError
end
begin
  require 'dspy/code_act'
rescue LoadError
end
begin
  require 'dspy/miprov2'
rescue LoadError
end
require_relative 'dspy/tools'
require_relative 'dspy/memory'

begin
  require 'dspy/datasets'
rescue LoadError
end
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
