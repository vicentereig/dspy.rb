# frozen_string_literal: true

module DSPy
  module DeepSearch
    module Signatures
      extend T::Sig

      class SeedQuery < DSPy::Signature
        description "Seed the first search query for DeepSearch"

        input do
          const :question, String, description: "User research question"
        end

        output do
          const :query, String, description: "Initial search query"
        end
      end

      class SearchSources < DSPy::Signature
        description "Call the search provider and return candidate URLs"

        input do
          const :query, String, description: "Search engine query"
        end

        output do
          const :urls, T::Array[String], description: "Ranked URLs to read next"
        end
      end

      class ReadSource < DSPy::Signature
        description "Summarize a single source into bullet notes"

        input do
          const :url, String, description: "URL selected by the search step"
        end

        output do
          const :notes, T::Array[String], description: "Key takeaways from the page"
        end
      end

      class ReasonStep < DSPy::Signature
        description "Decide whether to keep searching, read more, or answer"

        class Decision < T::Enum
          enums do
            ContinueSearch = new("continue_search")
            ReadMore       = new("read_more")
            Answer         = new("answer")
          end
        end

        input do
          const :question, String, description: "Original user question"
          const :insights, T::Array[String], description: "Accumulated notes" 
        end

        output do
          const :decision, Decision, description: "Next action for the loop"
          const :refined_query, T.nilable(String), description: "Follow-up search query"
          const :draft_answer, T.nilable(String), description: "Candidate answer" 
        end
      end
    end
  end
end
