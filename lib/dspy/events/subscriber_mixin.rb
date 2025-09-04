# frozen_string_literal: true

require 'sorbet-runtime'

module DSPy
  module Events
    # Mixin for adding class-level event subscriptions
    # Provides a clean way to subscribe to events at the class level
    # instead of requiring instance-based subscriptions
    #
    # Usage:
    #   class MyTracker
    #     include DSPy::Events::SubscriberMixin
    #     
    #     add_subscription('llm.*') do |name, attrs|
    #       # Handle LLM events globally for this class
    #     end
    #   end
    module SubscriberMixin
      extend T::Sig

      def self.included(base)
        base.extend(ClassMethods)
        base.class_eval do
          @event_subscriptions = []
          @subscription_mutex = Mutex.new
          
          # Initialize subscriptions when the class is first loaded
          @subscriptions_initialized = false
        end
      end

      module ClassMethods
        extend T::Sig

        # Add a class-level event subscription
        sig { params(pattern: String, block: T.proc.params(arg0: String, arg1: T::Hash[T.any(String, Symbol), T.untyped]).void).returns(String) }
        def add_subscription(pattern, &block)
          subscription_mutex.synchronize do
            subscription_id = DSPy.events.subscribe(pattern, &block)
            event_subscriptions << subscription_id
            subscription_id
          end
        end

        # Remove all subscriptions for this class
        sig { void }
        def unsubscribe_all
          subscription_mutex.synchronize do
            event_subscriptions.each { |id| DSPy.events.unsubscribe(id) }
            event_subscriptions.clear
          end
        end

        # Get list of active subscription IDs
        sig { returns(T::Array[String]) }
        def subscriptions
          subscription_mutex.synchronize do
            event_subscriptions.dup
          end
        end

        private

        # Thread-safe access to subscriptions array
        sig { returns(T::Array[String]) }
        def event_subscriptions
          @event_subscriptions ||= []
        end

        # Thread-safe access to mutex
        sig { returns(Mutex) }
        def subscription_mutex
          @subscription_mutex ||= Mutex.new
        end
      end
    end
  end
end