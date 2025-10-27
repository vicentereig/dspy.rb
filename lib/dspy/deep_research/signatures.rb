# frozen_string_literal: true

module DSPy
  module DeepResearch
    module Signatures
      extend T::Sig

      class BuildOutline < DSPy::Signature
        description "Generate an outline of sections to investigate for the research brief"

        class SectionSpec < T::Struct
          const :identifier, String
          const :title, String
          const :prompt, String
          const :token_budget, Integer
          const :attempt, Integer, default: 0
          const :parent_identifier, T.nilable(String), default: nil
        end

        input do
          const :brief, String, description: "Research brief or question to investigate"
        end

        output do
          const :sections, T::Array[SectionSpec], description: "Ordered section specifications to investigate"
        end
      end

      class SynthesizeSection < DSPy::Signature
        description "Transform DeepSearch results into a coherent section draft"

        input do
          const :brief, String, description: "Original research brief"
          const :section, BuildOutline::SectionSpec, description: "Section specification being drafted"
          const :answer, String, description: "Candidate answer from DeepSearch"
          const :notes, T::Array[String], description: "Supporting notes collected during DeepSearch"
          const :citations, T::Array[String], description: "Citations gathered for this section"
        end

        output do
          const :draft, String, description: "Section draft ready for aggregation"
          const :citations, T::Array[String], description: "Filtered citations supporting the draft"
        end
      end

      class QAReview < DSPy::Signature
        description "Decide whether a section draft is ready or requires more evidence"

        class Status < T::Enum
          enums do
            Approved          = new("approved")
            NeedsMoreEvidence = new("needs_more_evidence")
          end
        end

        input do
          const :brief, String, description: "Research brief"
          const :section, BuildOutline::SectionSpec, description: "Section specification with metadata"
          const :draft, String, description: "Draft content for the section"
          const :notes, T::Array[String], description: "Supporting evidence notes"
          const :citations, T::Array[String], description: "Citations backing the draft"
          const :attempt, Integer, description: "Number of attempts made for this section"
        end

        output do
          const :status, Status, description: "QA decision for the section"
          const :follow_up_prompt, T.nilable(String), description: "Additional prompt if more evidence is required"
        end
      end

      class AssembleReport < DSPy::Signature
        description "Aggregate accepted sections into the final deliverable"

        class SectionDraft < T::Struct
          const :identifier, String
          const :title, String
          const :draft, String
          const :citations, T::Array[String]
        end

        input do
          const :brief, String, description: "Research brief"
          const :sections, T::Array[SectionDraft], description: "Accepted section drafts"
        end

        output do
          const :report, String, description: "Final synthesized report"
          const :citations, T::Array[String], description: "Consolidated citations for the report"
        end
      end
    end
  end
end
