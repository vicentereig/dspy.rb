#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Workflow Router with Specialized Follow-ups
#
# This script demonstrates how to build a routing workflow in DSPy.rb.
# We classify each support request, route it to a specialized follow-up
# predictor (billing, technical, or general enablement), and highlight
# how each predictor can run on a different model. By default we use
# Anthropic's Claude 4.5 Haiku (2025-10-01 snapshot) for
# classification/easy flows and Claude 4.5 Sonnet (2025-09-29 snapshot)
# when technical tickets need deeper reasoning.

require 'dotenv'

# Load environment variables from .env so `OPENAI_API_KEY` (or others)
# are available when we configure DSPy.
Dotenv.load(File.expand_path('../.env', __dir__))

require_relative '../lib/dspy'

# Configure observability for Langfuse tracing
DSPy::Observability.configure!

class TicketCategory < T::Enum
  enums do
    General = new('general')
    Billing = new('billing')
    Technical = new('technical')
  end
end

class RouteSupportTicket < DSPy::Signature
  description "Classify a support request so we can route it to the right follow-up workflow."

  input do
    const :message, String, description: "Raw customer request text."
  end

  output do
    const :category, TicketCategory, description: "One of: general, billing, or technical."
    const :confidence, Float, description: "Confidence between 0 and 1."
    const :reason, String, description: "Short explanation of why this category fits."
  end
end

# Each specialized follow-up returns structured playbook guidance so an
# agent or human can take the next step confidently.
module SupportPlaybooks
  module SharedSchema
    def self.included(base)
      base.class_eval do
        input do
          const :message, String
        end

        output do
          const :resolution_summary, String
          const :recommended_steps, T::Array[String]
          const :tags, T::Array[String]
        end
      end
    end
  end

  class Billing < DSPy::Signature
    include SharedSchema
    description "Resolve billing or refund issues with policy-aware guidance."
  end

  class Technical < DSPy::Signature
    include SharedSchema
    description "Handle technical or outage reports with diagnostic steps."
  end

  class GeneralEnablement < DSPy::Signature
    include SharedSchema
    description "Answer broad questions or point folks to self-serve docs."
  end
end

class RoutedTicket < T::Struct
  const :category, TicketCategory
  const :model_id, String
  const :confidence, Float
  const :reason, String
  const :resolution_summary, String
  const :recommended_steps, T::Array[String]
  const :tags, T::Array[String]
end

class SupportRouter < DSPy::Module
  extend T::Sig

  sig do
    params(
      classifier: DSPy::Predict,
      handlers: T::Hash[TicketCategory, DSPy::Predict],
      fallback_category: TicketCategory
    ).void
  end
  def initialize(classifier:, handlers:, fallback_category: TicketCategory::General)
    super()
    @classifier = classifier
    @handlers = handlers
    @fallback_category = fallback_category
  end

  sig { override.params(input_values: T.untyped).returns(T.untyped) }
  def forward_untyped(**input_values)
    classification = @classifier.call(**input_values)
    handler = @handlers.fetch(classification.category, @handlers[@fallback_category])
    raise ArgumentError, "Missing handler for #{classification.category.serialize}" unless handler

    specialized = handler.call(**input_values)
    RoutedTicket.new(
      category: classification.category,
      model_id: handler.lm&.model_id || DSPy.config.lm&.model_id || 'unknown-model',
      confidence: classification.confidence,
      reason: classification.reason,
      resolution_summary: specialized.resolution_summary,
      recommended_steps: specialized.recommended_steps,
      tags: specialized.tags
    )
  end
end

def ensure_api_key!(env_key)
  return if ENV[env_key]

  warn "Missing #{env_key}. Set it in .env or your shell before running this example."
  exit 1
end

ensure_api_key!('ANTHROPIC_API_KEY')

CLASSIFIER_MODEL = ENV.fetch('DSPY_ROUTER_CLASSIFIER_MODEL', 'anthropic/claude-haiku-4-5-20251001')
LIGHTWEIGHT_MODEL = ENV.fetch('DSPY_ROUTER_EASY_MODEL', 'anthropic/claude-haiku-4-5-20251001')
HEAVY_MODEL = ENV.fetch('DSPY_ROUTER_COMPLEX_MODEL', 'anthropic/claude-sonnet-4-5-20250929')

DSPy.configure do |config|
  config.lm = DSPy::LM.new(
    CLASSIFIER_MODEL,
    api_key: ENV['ANTHROPIC_API_KEY'],
    structured_outputs: true
  )
end

DSPy::Observability.configure!

# Give users a quick hint when the script is run directly
if $PROGRAM_NAME == __FILE__ && $stdout.tty?
  if !ENV['LANGFUSE_PUBLIC_KEY'] && !ENV['LANGFUSE_SECRET_KEY']
    warn "ℹ️ Set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY to stream traces to Langfuse."
  end
end

classifier = DSPy::Predict.new(RouteSupportTicket)

billing_follow_up = DSPy::Predict.new(SupportPlaybooks::Billing)
billing_follow_up.configure do |config|
  config.lm = DSPy::LM.new(
    LIGHTWEIGHT_MODEL,
    api_key: ENV['ANTHROPIC_API_KEY']
  )
end

general_follow_up = DSPy::Predict.new(SupportPlaybooks::GeneralEnablement)
general_follow_up.configure do |config|
  config.lm = DSPy::LM.new(
    LIGHTWEIGHT_MODEL,
    api_key: ENV['ANTHROPIC_API_KEY']
  )
end

technical_follow_up = DSPy::ChainOfThought.new(SupportPlaybooks::Technical)
technical_follow_up.configure do |config|
  config.lm = DSPy::LM.new(
    HEAVY_MODEL,
    api_key: ENV['ANTHROPIC_API_KEY']
  )
end

def run_router_demo(router)
  sample_tickets = [
    {
      id: 'INC-8721',
      channel: 'email',
      message: "My account was charged twice for September and the invoice shows an unfamiliar add-on."
    },
    {
      id: 'INC-8729',
      channel: 'chat',
      message: "Device sensors stopped reporting since last night's deployment. Can you help me roll back?"
    },
    {
      id: 'INC-8740',
      channel: 'community',
      message: "What limits apply to the new analytics workspace beta?"
    }
  ]

  puts "\n🗺️  Routing #{sample_tickets.size} incoming tickets...\n\n"

  sample_tickets.each do |ticket|
    result = router.call(message: ticket[:message])

    puts "📨  #{ticket[:id]} via #{ticket[:channel]}"
    puts "    Input: #{ticket[:message]}"
    puts "    → Routed to #{result.category.serialize} (#{(result.confidence * 100).round(1)}% confident)"
    puts "    → Follow-up model: #{result.model_id}"
    puts "    Summary: #{result.resolution_summary}"
    puts "    Next steps:"
    result.recommended_steps.each_with_index do |step, index|
      puts "      #{index + 1}. #{step}"
    end
    puts "    Tags: #{result.tags.join(', ')}"
    puts "-" * 70
  end

  puts "\n✅  Done! Adjust the sample tickets or ENV overrides to see the router adapt.\n"
end

if $PROGRAM_NAME == __FILE__
  router = SupportRouter.new(
    classifier: classifier,
    handlers: {
      TicketCategory::Billing => billing_follow_up,
      TicketCategory::Technical => technical_follow_up,
      TicketCategory::General => general_follow_up
    }
  )

  run_router_demo(router)
  DSPy::Observability.flush!
end
