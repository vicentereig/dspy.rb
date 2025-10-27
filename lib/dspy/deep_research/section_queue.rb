# frozen_string_literal: true

module DSPy
  module DeepResearch
    class SectionQueue
      extend T::Sig

      SectionSpec = DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec

      sig { void }
      def initialize
        @queue = T.let([], T::Array[SectionSpec])
        @attempts = T.let(Hash.new(0), T::Hash[String, Integer])
      end

      sig { params(section: SectionSpec).returns(SectionSpec) }
      def enqueue(section)
        base = base_identifier(section)
        @attempts[base] = section.attempt
        @queue << section
        section
      end

      sig { params(section: SectionSpec).returns(SectionSpec) }
      def enqueue_front(section)
        base = base_identifier(section)
        @attempts[base] = section.attempt
        @queue.unshift(section)
        section
      end

      sig { params(section: SectionSpec, prompt: String).returns(SectionSpec) }
      def enqueue_follow_up(section, prompt:)
        base = base_identifier(section)
        next_attempt = section.attempt + 1
        @queue.delete_if { |queued| base_identifier(queued) == base }

        follow_up = SectionSpec.new(
          identifier: "#{base}-retry-#{next_attempt}",
          title: section.title,
          prompt: prompt,
          token_budget: section.token_budget,
          attempt: next_attempt,
          parent_identifier: section.parent_identifier || base
        )

        enqueue_front(follow_up)
      end

      sig { returns(T.nilable(SectionSpec)) }
      def dequeue
        @queue.shift
      end

      sig { returns(T::Boolean) }
      def empty?
        @queue.empty?
      end

      sig { params(section: SectionSpec).returns(Integer) }
      def attempts_for(section)
        base = base_identifier(section)
        @attempts.fetch(base, section.attempt)
      end

      sig { void }
      def clear
        @queue.clear
      end

      private

      sig { params(section: SectionSpec).returns(String) }
      def base_identifier(section)
        section.parent_identifier || section.identifier.split("-retry-").first
      end
    end
  end
end
