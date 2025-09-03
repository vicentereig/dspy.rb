# frozen_string_literal: true

module DSPy
  module Events
    # Base subscriber class for event-driven patterns
    # This provides the foundation for creating custom event subscribers
    # 
    # Example usage:
    #   class MySubscriber < DSPy::Events::BaseSubscriber
    #     def subscribe
    #       add_subscription('llm.*') do |event_name, attributes|
    #         # Handle LLM events
    #       end
    #     end
    #   end
    #
    #   subscriber = MySubscriber.new
    #   # subscriber will start receiving events
    #   subscriber.unsubscribe # Clean up when done
    class BaseSubscriber
      def initialize
        @subscriptions = []
      end
      
      def subscribe
        raise NotImplementedError, "Subclasses must implement #subscribe"
      end
      
      def unsubscribe
        @subscriptions.each { |id| DSPy.events.unsubscribe(id) }
        @subscriptions.clear
      end
      
      protected
      
      def add_subscription(pattern, &block)
        subscription_id = DSPy.events.subscribe(pattern, &block)
        @subscriptions << subscription_id
        subscription_id
      end
    end
  end
end