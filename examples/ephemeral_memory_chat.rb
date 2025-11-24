#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv'
require 'cli/ui'
require 'time'

Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

CLI::UI::StdoutRouter.ensure_activated
$stdout.sync = true

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def ensure_api_key!(env_key)
  return if ENV[env_key]

  warn "Missing #{env_key}. Set it in .env or export it before running this script."
  exit 1
end

def env_or_default(key, default)
  ENV.fetch(key, default)
end

# -----------------------------------------------------------------------------
# Signatures and enums
# -----------------------------------------------------------------------------

class ComplexityLevel < T::Enum
  enums do
    Routine = new('routine')
    Detailed = new('detailed')
    Critical = new('critical')
  end
end

class RouteChatRequest < DSPy::Signature
  description 'Estimate message complexity/cost before dispatching to an LM.'

  input do
    const :message, String
    const :conversation_depth, Integer
  end

  output do
    const :level, ComplexityLevel
    const :confidence, Float
    const :reason, String
    const :suggested_cost_tier, String
  end
end

class ResolveUserQuestion < DSPy::Signature
  description 'Respond to a user while persisting ephemeral memory for routing decisions.'

  class MemoryTurn < T::Struct
    const :role, String
    const :message, String
  end

  input do
    const :user_message, String
    const :history, T::Array[MemoryTurn], default: []
    const :selected_model, String
  end

  output do
    const :reply, String
    const :complexity, ComplexityLevel
    const :next_action, String
  end
end

class ConversationMemoryEntry < T::Struct
  const :role, String
  const :message, String
  const :model_id, T.nilable(String)
  const :timestamp, String
end

class RouteDecision < T::Struct
  const :predictor, DSPy::Module
  const :model_id, String
  const :level, ComplexityLevel
  const :reason, String
  const :cost_tier, String
end

# -----------------------------------------------------------------------------
# Router and session types
# -----------------------------------------------------------------------------

class ChatRouter < DSPy::Module
  extend T::Sig

  sig do
    params(
      classifier: DSPy::Predict,
      routes: T::Hash[ComplexityLevel, DSPy::Module],
      default_level: ComplexityLevel
    ).void
  end

  def initialize(classifier:, routes:, default_level: ComplexityLevel::Routine)
    super()
    @classifier = classifier
    @routes = routes
    @default_level = default_level
  end

  sig { override.params(input_values: T.untyped).returns(T.untyped) }
  def forward(**input_values)
    message = input_values[:message]
    memory = input_values[:memory] || []
    raise ArgumentError, 'message is required' unless message

    route_turn(message: message, memory: memory)
  end

  private

  sig { params(message: String, memory: T::Array[ConversationMemoryEntry]).returns(RouteDecision) }
  def route_turn(message:, memory:)
    raise ArgumentError, 'message is required' if message.strip.empty?

    classification = @classifier.call(
      message: message,
      conversation_depth: memory.length
    )

    level = classification.level
    predictor = @routes.fetch(level, @routes[@default_level])
    raise ArgumentError, "Missing predictor for #{level.serialize}" unless predictor

    RouteDecision.new(
      predictor: predictor,
      model_id: predictor.lm&.model_id || DSPy.config.lm&.model_id || 'unknown-model',
      level: level,
      reason: classification.reason,
      cost_tier: classification.suggested_cost_tier
    )
  end
end

class EphemeralMemoryChat < DSPy::Module
  extend T::Sig

  around :transcribe_chat # wraps forward with memory + routing lifecycle

  sig { params(signature: T.class_of(DSPy::Signature), router: ChatRouter).void }
  def initialize(signature:, router:)
    super()
    @router = router
    @signature = signature
    @memory_turn_struct = T.let(
      signature.const_get(:MemoryTurn),
      T.class_of(T::Struct)
    )
    @memory = T.let([], T::Array[ConversationMemoryEntry]) # Hydrate from ActiveRecord rows if you persist history
    @last_route = T.let(nil, T.nilable(RouteDecision))
  end

  sig { returns(T::Array[ConversationMemoryEntry]) }
  attr_reader :memory

  sig { returns(T.nilable(RouteDecision)) }
  attr_reader :last_route

  def forward(user_message:)
    raise ArgumentError, 'user_message is required' unless user_message
    route = @router.call(message: user_message, memory: @memory)
    raise ArgumentError, 'Router did not provide a predictor' unless route
    @last_route = route

    route.predictor.call(
      user_message: user_message,
      history: typed_history,
      selected_model: route.model_id
    )
  end

  def describe_route(decision)
    return 'No route decision recorded yet.' unless decision

    details = [
      "Routed to #{decision.model_id} (#{decision.level.serialize}, #{decision.cost_tier})",
      "Reason: #{decision.reason}"
    ].join(' | ')
    "→ #{details}"
  end

  private

  def typed_history
    history_without_current = @memory[0...-1] || []
    history_without_current.map do |turn|
      @memory_turn_struct.new(role: turn.role, message: turn.message)
    end
  end

  def transcribe_chat(_args, kwargs)
    message = kwargs[:user_message]
    raise ArgumentError, 'user_message is required' unless message
    @last_route = nil

    user_entry = ConversationMemoryEntry.new(
      role: 'user',
      message: message,
      model_id: nil,
      timestamp: Time.now.utc.iso8601
    )
    @memory << user_entry # Replace with ConversationTurn.create!(...) to keep durable transcripts

    result = yield

    if result && @last_route
      @memory << ConversationMemoryEntry.new(
        role: 'assistant',
        message: result.reply,
        model_id: @last_route.model_id,
        timestamp: Time.now.utc.iso8601
      ) # Likewise persist agent replies via ActiveRecord for reloadable memory
    end

    result
  end
end

# -----------------------------------------------------------------------------
# Production wiring
# -----------------------------------------------------------------------------

ROUTER_MODEL = env_or_default('DSPY_CHAT_ROUTER_MODEL', 'openai/gpt-4o-mini')
FAST_RESPONSE_MODEL = env_or_default('DSPY_CHAT_FAST_MODEL', 'openai/gpt-4o-mini')
DEEP_REASONING_MODEL = env_or_default('DSPY_CHAT_DEEP_MODEL', 'openai/gpt-4o')

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    ROUTER_MODEL,
    api_key: ENV['OPENAI_API_KEY'],
    structured_outputs: true
  ) if ENV['OPENAI_API_KEY']
end

DSPy::Observability.configure!

def build_production_router
  classifier = DSPy::Predict.new(RouteChatRequest)

  fast_predictor = DSPy::Predict.new(ResolveUserQuestion)
  fast_predictor.configure do |config|
    config.lm = DSPy::LM.new(
      FAST_RESPONSE_MODEL,
      api_key: ENV['OPENAI_API_KEY'],
      structured_outputs: true
    )
  end

  deep_predictor = DSPy::ChainOfThought.new(ResolveUserQuestion)
  deep_predictor.configure do |config|
    config.lm = DSPy::LM.new(
      DEEP_REASONING_MODEL,
      api_key: ENV['OPENAI_API_KEY'],
      structured_outputs: true
    )
  end

  ChatRouter.new(
    classifier: classifier,
    routes: {
      ComplexityLevel::Routine => fast_predictor,
      ComplexityLevel::Detailed => fast_predictor,
      ComplexityLevel::Critical => deep_predictor
    },
    default_level: ComplexityLevel::Routine
  )
end

# -----------------------------------------------------------------------------
# CLI helpers
# -----------------------------------------------------------------------------

def render_chat_pane(session, max_turns: 12)
  CLI::UI::Frame.open('Ephemeral Memory Chat') do
    turns = session.memory.last(max_turns)
    if turns.empty?
      CLI::UI::Frame.puts('No turns yet. Type in the lower pane to start chatting.')
    else
      turns.each do |turn|
        label = turn.role == 'user' ? '{{bold}}🙋 you{{/bold}}' : '{{green}}🤖 assistant{{/green}}'
        model_suffix = turn.model_id ? " (#{turn.model_id})" : ''
        CLI::UI::Frame.puts(CLI::UI.fmt("#{label}#{model_suffix}: #{turn.message}"))
      end
    end

    if session.last_route
      CLI::UI::Frame.puts('')
      CLI::UI::Frame.puts(session.describe_route(session.last_route))
    end
  end
end

def redraw_chat(session)
  print(CLI::UI::ANSI.control('2', 'J'))  # Clear entire screen
  print(CLI::UI::ANSI.control('', 'H'))   # Move cursor home
  render_chat_pane(session)
  CLI::UI::Frame.open('Controls') do
    CLI::UI::Frame.puts('Type your message below. Send an empty line or `exit` to quit.')
  end
end

def with_chat_screen
  print(CLI::UI::ANSI.enter_alternate_screen)
  print(CLI::UI::ANSI.hide_cursor)
  yield
ensure
  print(CLI::UI::ANSI.show_cursor)
  print(CLI::UI::ANSI.exit_alternate_screen)
end

def print_memory_summary(session)
  CLI::UI::Frame.open('Stored Memory Turns') do
    if session.memory.empty?
      CLI::UI::Frame.puts('No memory entries recorded.')
    else
      session.memory.each do |turn|
        marker = turn.role == 'user' ? '🙋' : '🤖'
        model = turn.model_id || 'human'
        CLI::UI::Frame.puts("#{marker} [#{turn.timestamp}] (#{model}) #{turn.message}")
      end
    end
  end
end

# -----------------------------------------------------------------------------
# CLI entrypoint
# -----------------------------------------------------------------------------

if $PROGRAM_NAME == __FILE__
  ensure_api_key!('OPENAI_API_KEY')
  router = build_production_router

  session = EphemeralMemoryChat.new(signature: ResolveUserQuestion, router: router)

  with_chat_screen do
    loop do
      redraw_chat(session)

      message = CLI::UI::Prompt.ask('you> ').strip
      break if message.empty? || message.casecmp('exit').zero?

      CLI::UI::Spinner.spin('Routing turn...') do
        session.call(user_message: message)
      end
    end

    redraw_chat(session)
    print_memory_summary(session)
  end

  DSPy::Observability.flush! if DSPy::Observability.respond_to?(:flush!)
end
