# frozen_string_literal: true

require 'securerandom'

module DSPy
  # Events module to hold typed event structures
  module Events
    # Will be defined in events/types.rb
  end
  
  class EventRegistry
    def initialize
      @listeners = {}
      @subscription_counter = 0
      @mutex = Mutex.new
    end

    def subscribe(pattern, &block)
      return unless block_given?
      
      subscription_id = SecureRandom.uuid
      @mutex.synchronize do
        @listeners[subscription_id] = {
          pattern: pattern,
          block: block
        }
      end
      
      subscription_id
    end

    def unsubscribe(subscription_id)
      @mutex.synchronize do
        @listeners.delete(subscription_id)
      end
    end

    def clear_listeners
      @mutex.synchronize do
        @listeners.clear
      end
    end

    def notify(event_name, attributes)
      # Take a snapshot of current listeners to avoid holding the mutex during execution
      # This allows listeners to be modified while others are executing
      matching_listeners = @mutex.synchronize do
        @listeners.select do |id, listener|
          pattern_matches?(listener[:pattern], event_name)
        end.dup  # Create a copy to avoid shared state
      end

      matching_listeners.each do |id, listener|
        begin
          listener[:block].call(event_name, attributes)
        rescue => e
          # Log the error but continue processing other listeners
          # Use emit_log directly to avoid infinite recursion
          DSPy.send(:emit_log, 'event.listener.error', {
            subscription_id: id,
            error_class: e.class.name,
            error_message: e.message,
            event_name: event_name
          })
        end
      end
    end

    private

    def pattern_matches?(pattern, event_name)
      if pattern.include?('*')
        # Convert wildcard pattern to regex
        # llm.* becomes ^llm\..*$
        regex_pattern = "^#{Regexp.escape(pattern).gsub('\\*', '.*')}$"
        Regexp.new(regex_pattern).match?(event_name)
      else
        # Exact match
        pattern == event_name
      end
    end
  end
end