# frozen_string_literal: true

module DSPy
  module DeepResearch
    class Module < DSPy::Module
      extend T::Sig

      SectionSpec = DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec

      class SectionResult < T::Struct
        const :identifier, String
        const :title, String
        const :draft, String
        const :citations, T::Array[String]
        const :attempt, Integer
      end

      class Result < T::Struct
        const :report, String
        const :sections, T::Array[SectionResult]
        const :citations, T::Array[String]
      end

      sig do
        params(
          planner: T.untyped,
          deep_search_factory: T.nilable(T.proc.returns(DSPy::Module)),
          synthesizer: T.untyped,
          qa_reviewer: T.untyped,
          reporter: T.untyped,
          section_queue_factory: T.nilable(T.proc.returns(DSPy::DeepResearch::SectionQueue)),
          max_section_attempts: Integer
        ).void
      end
      def initialize(
        planner: DSPy::Predict.new(DSPy::DeepResearch::Signatures::BuildOutline),
        deep_search_factory: nil,
        synthesizer: DSPy::Predict.new(DSPy::DeepResearch::Signatures::SynthesizeSection),
        qa_reviewer: DSPy::Predict.new(DSPy::DeepResearch::Signatures::QAReview),
        reporter: DSPy::Predict.new(DSPy::DeepResearch::Signatures::AssembleReport),
        section_queue_factory: nil,
        max_section_attempts: 3
      )
        super()

        @planner = planner
        @deep_search_factory = deep_search_factory || default_deep_search_factory
        @synthesizer = synthesizer
        @qa_reviewer = qa_reviewer
        @reporter = reporter
        @section_queue_factory = section_queue_factory || -> { DSPy::DeepResearch::SectionQueue.new }
        @max_section_attempts = max_section_attempts
        @deep_search_instruction = nil
        @deep_search_examples = []

        reset_state!
      end

      sig { override.returns(T::Array[[String, DSPy::Module]]) }
      def named_predictors
        [
          ["planner", @planner],
          ["synthesizer", @synthesizer],
          ["qa_reviewer", @qa_reviewer],
          ["reporter", @reporter]
        ]
      end

      sig { override.returns(T::Array[DSPy::Module]) }
      def predictors
        named_predictors.map { |(_, predictor)| predictor }
      end

      sig { params(instruction: String).returns(Module) }
      def with_instruction(instruction)
        clone_with(
          planner: apply_instruction(@planner, instruction),
          synthesizer: apply_instruction(@synthesizer, instruction),
          qa_reviewer: apply_instruction(@qa_reviewer, instruction),
          reporter: apply_instruction(@reporter, instruction),
          deep_search_instruction: instruction,
          deep_search_examples: @deep_search_examples.dup
        )
      end

      sig { params(examples: T::Array[DSPy::FewShotExample]).returns(Module) }
      def with_examples(examples)
        examples_copy = examples.map { |example| example }
        clone_with(
          planner: apply_examples(@planner, examples_copy),
          synthesizer: apply_examples(@synthesizer, examples_copy),
          qa_reviewer: apply_examples(@qa_reviewer, examples_copy),
          reporter: apply_examples(@reporter, examples_copy),
          deep_search_instruction: @deep_search_instruction,
          deep_search_examples: examples_copy
        )
      end

      def forward_untyped(**input_values)
        brief = input_values[:brief]
        unless brief.is_a?(String)
          raise ArgumentError, "DeepResearch expects keyword argument :brief"
        end

        reset_state!
        outline = @planner.call(brief: brief)
        enqueue_sections(outline.sections)

        while (section_spec = @section_queue.dequeue)
          attempts = @section_queue.attempts_for(section_spec)
          if attempts > @max_section_attempts
            raise DSPy::DeepResearch::QueueStarvationError,
                  "Section #{section_spec.identifier} exceeded max attempts (#{attempts}/#{@max_section_attempts})"
          end

          emit_section_started(section_spec, attempts)

          deep_search_module = build_deep_search(section_spec)
          deep_result = deep_search_module.call(question: section_spec.prompt)

          evidence = merge_section_evidence(section_spec, deep_result)

          synthesized = @synthesizer.call(
            brief: brief,
            section: section_spec,
            answer: deep_result.answer,
            notes: evidence[:notes],
            citations: evidence[:citations]
          )

          section_result = SectionResult.new(
            identifier: section_spec.identifier,
            title: section_spec.title,
            draft: synthesized.draft,
            citations: Array(synthesized.citations || evidence[:citations]).compact.uniq,
            attempt: attempts
          )

          qa_decision = @qa_reviewer.call(
            brief: brief,
            section: section_spec,
            draft: section_result.draft,
            notes: evidence[:notes],
            citations: evidence[:citations],
            attempt: attempts
          )

          case qa_decision.status
          when DSPy::DeepResearch::Signatures::QAReview::Status::Approved
            accept_section(section_result)
          when DSPy::DeepResearch::Signatures::QAReview::Status::NeedsMoreEvidence
            follow_up_prompt = qa_decision.follow_up_prompt
            if attempts >= @max_section_attempts
              raise DSPy::DeepResearch::EvidenceDeficitError,
                    "QA requested more evidence for #{section_spec.title} beyond max attempts"
            end
            unless follow_up_prompt
              raise DSPy::DeepResearch::EvidenceDeficitError,
                    "QA requested more evidence for #{section_spec.title} but no follow-up prompt provided"
            end

            emit_section_retry(section_spec, attempts, follow_up_prompt)

            follow_up = @section_queue.enqueue_follow_up(section_spec, prompt: follow_up_prompt)
            DSPy.event(
              "deep_research.section.requeued",
              identifier: section_spec.identifier,
              follow_up_identifier: follow_up.identifier,
              prompt: follow_up_prompt,
              attempt: follow_up.attempt
            )
          else
            raise DSPy::DeepResearch::SynthesisCoherenceError,
                  "Unexpected QA status: #{qa_decision.status}"
          end
        end

        raise DSPy::DeepResearch::SynthesisCoherenceError, "No sections were approved" if @accepted_sections.empty?

        assembled = @reporter.call(
          brief: brief,
          sections: @accepted_sections.map do |section|
            DSPy::DeepResearch::Signatures::AssembleReport::SectionDraft.new(
              identifier: section.identifier,
              title: section.title,
              draft: section.draft,
              citations: section.citations
            )
          end
        )

        result = Result.new(
          report: assembled.report,
          sections: @accepted_sections.dup,
          citations: merged_citations(Array(assembled.citations))
        )
        ensure_report_ready(assembled, brief)
        result
      end

      private

      sig do
        params(
          planner: T.untyped,
          synthesizer: T.untyped,
          qa_reviewer: T.untyped,
          reporter: T.untyped,
          deep_search_instruction: T.nilable(String),
          deep_search_examples: T::Array[DSPy::FewShotExample]
        ).returns(Module)
      end
      def clone_with(planner:, synthesizer:, qa_reviewer:, reporter:, deep_search_instruction:, deep_search_examples:)
        clone = self.class.new(
          planner: planner,
          deep_search_factory: @deep_search_factory,
          synthesizer: synthesizer,
          qa_reviewer: qa_reviewer,
          reporter: reporter,
          section_queue_factory: @section_queue_factory,
          max_section_attempts: @max_section_attempts
        )

        clone.instance_variable_set(:@deep_search_instruction, deep_search_instruction)
        clone.instance_variable_set(:@deep_search_examples, deep_search_examples)
        clone
      end

      sig { params(predictor: T.untyped, instruction: String).returns(T.untyped) }
      def apply_instruction(predictor, instruction)
        return predictor unless predictor.respond_to?(:with_instruction)

        predictor.with_instruction(instruction)
      end

      sig { params(predictor: T.untyped, examples: T::Array[DSPy::FewShotExample]).returns(T.untyped) }
      def apply_examples(predictor, examples)
        return predictor unless predictor.respond_to?(:with_examples)

        predictor.with_examples(examples)
      end

      sig { params(sections: T::Array[SectionSpec]).void }
      def enqueue_sections(sections)
        sections.each do |section|
          @section_queue.enqueue(section)
          DSPy.event(
            "deep_research.section.enqueued",
            identifier: section.identifier,
            title: section.title,
            prompt: section.prompt,
            token_budget: section.token_budget
          )
        end
      end

      sig { params(section: SectionResult).void }
      def accept_section(section)
        @accepted_sections << section
        @citations.concat(section.citations)

        DSPy.event(
          "deep_research.section.approved",
          identifier: section.identifier,
          title: section.title,
          attempt: section.attempt,
          citations: section.citations
        )
      end

      sig { params(section: SectionSpec).returns(DSPy::Module) }
      def build_deep_search(section)
        module_instance = @deep_search_factory.call
        if @deep_search_instruction && module_instance.respond_to?(:with_instruction)
          module_instance = module_instance.with_instruction(@deep_search_instruction)
        end
        unless @deep_search_examples.empty?
          if module_instance.respond_to?(:with_examples)
            module_instance = module_instance.with_examples(@deep_search_examples)
          end
        end

        module_instance
      end

      sig { returns(T.proc.returns(DSPy::Module)) }
      def default_deep_search_factory
        -> { DSPy::DeepSearch::Module.new }
      end

      sig { void }
      def reset_state!
        @section_queue = @section_queue_factory.call
        @accepted_sections = T.let([], T::Array[SectionResult])
        @citations = T.let([], T::Array[String])
        @section_evidence = T.let({}, T::Hash[String, T::Hash[Symbol, T::Array[String]]])
      end

      sig { params(citations: T::Array[String]).returns(T::Array[String]) }
      def merged_citations(citations)
        (Array(citations) + @citations).compact.uniq
      end

      sig { params(section: SectionSpec, deep_result: DSPy::DeepSearch::Module::Result).returns(T::Hash[Symbol, T::Array[String]]) }
      def merge_section_evidence(section, deep_result)
        base = normalize_identifier(section)
        store = (@section_evidence[base] ||= { notes: [], citations: [] })
        store[:notes].concat(Array(deep_result.notes)).uniq!
        store[:citations].concat(Array(deep_result.citations)).uniq!
        store
      end

      sig { params(section: SectionSpec).returns(String) }
      def normalize_identifier(section)
        section.parent_identifier || section.identifier.split("-retry-").first
      end

      sig { params(section: SectionSpec, attempt: Integer).void }
      def emit_section_started(section, attempt)
        DSPy.event(
          "deep_research.section.started",
          identifier: section.identifier,
          title: section.title,
          prompt: section.prompt,
          attempt: attempt
        )
      end

      sig { params(section: SectionSpec, attempt: Integer, follow_up_prompt: String).void }
      def emit_section_retry(section, attempt, follow_up_prompt)
        DSPy.event(
          "deep_research.section.qa_retry",
          identifier: section.identifier,
          title: section.title,
          attempt: attempt,
          follow_up_prompt: follow_up_prompt
        )
      end

      sig { params(assembled: T.untyped, brief: String).void }
      def ensure_report_ready(assembled, brief)
        DSPy.event(
          "deep_research.report.ready",
          brief: brief,
          section_count: @accepted_sections.length,
          citation_count: assembled.citations&.length || 0
        )
      end
    end
  end
end
