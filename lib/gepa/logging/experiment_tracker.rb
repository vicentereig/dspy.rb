# frozen_string_literal: true

module GEPA
  module Logging
    # Lightweight experiment tracker that records metrics locally and can fan out to user hooks.
    class ExperimentTracker
      attr_reader :events

      def initialize(subscribers: [])
        @subscribers = Array(subscribers)
        @events = []
      end

      def with_subscriber(proc = nil, &block)
        @subscribers << (proc || block)
        self
      end

      def initialize_backends; end

      def start_run; end

      def log_metrics(metrics, step: nil)
        entry = { metrics: symbolize_keys(metrics), step: step }
        @events << entry

        @subscribers.each do |subscriber|
          subscriber.call(entry)
        rescue StandardError => e
          DSPy.log('gepa.experiment_tracker.error', error: e.message)
        end
      end

      def end_run; end

      def active?
        !@events.empty?
      end

      def each_event(&block)
        @events.each(&block)
      end

      private

      def symbolize_keys(hash)
        hash.each_with_object({}) do |(k, v), memo|
          memo[k.to_sym] = v
        end
      end
    end
  end
end

