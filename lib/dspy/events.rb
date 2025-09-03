# frozen_string_literal: true

require 'securerandom'

module DSPy
  class EventRegistry
    def initialize
      @listeners = {}
      @subscription_counter = 0
    end

    def subscribe(pattern, &block)
      return unless block_given?
      
      subscription_id = SecureRandom.uuid
      @listeners[subscription_id] = {
        pattern: pattern,
        block: block
      }
      
      subscription_id
    end

    def unsubscribe(subscription_id)
      @listeners.delete(subscription_id)
    end

    def clear_listeners
      @listeners.clear
    end

    def notify(event_name, attributes)
      matching_listeners = @listeners.select do |id, listener|
        pattern_matches?(listener[:pattern], event_name)
      end

      matching_listeners.each do |id, listener|
        begin
          listener[:block].call(event_name, attributes)
        rescue => e
          # Log the error but continue processing other listeners
          DSPy.log('event.listener.error', 
            subscription_id: id,
            error_class: e.class.name,
            error_message: e.message,
            event_name: event_name
          )
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