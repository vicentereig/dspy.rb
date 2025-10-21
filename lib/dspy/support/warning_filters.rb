# frozen_string_literal: true

module DSPy
  module Support
    module WarningFilters
      RUBY2_KEYWORDS_MESSAGE = 'Skipping set of ruby2_keywords flag for forward'

      module WarningSilencer
        def warn(message = nil, *args)
          msg = message.to_s
          return if msg.include?(RUBY2_KEYWORDS_MESSAGE)

          super
        end
      end

      def self.install!
        return if @installed

        Warning.singleton_class.prepend(WarningSilencer)
        @installed = true
      end
    end
  end
end

DSPy::Support::WarningFilters.install!
