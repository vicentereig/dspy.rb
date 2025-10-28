# frozen_string_literal: true

module DSPy
  module DeepResearch
    class Module < DSPy::Module
      extend T::Sig

      SectionSpec = DSPy::DeepResearch::Signatures::BuildOutline::SectionSpec
      ResearchMode = DSPy::DeepResearch::Signatures::BuildOutline::Mode

      MODEL_ENV_KEYS = {
        planner: 'DSPY_DEEP_RESEARCH_PLANNER_MODEL',
        qa: 'DSPY_DEEP_RESEARCH_QA_MODEL',
        synthesizer: 'DSPY_DEEP_RESEARCH_SYNTH_MODEL',
        reporter: 'DSPY_DEEP_RESEARCH_REPORTER_MODEL'
      }.freeze

      MODEL_PRIORITY = {
        planner: [
          'gemini/gemini-2.5-pro',
          'openai/o4-mini',
          'anthropic/claude-4.1-opus'
        ],
        qa: [
          'gemini/gemini-2.5-pro',
          'openai/o4-mini',
          'anthropic/claude-4.1-opus'
        ],
        synthesizer: [
          'anthropic/claude-sonnet-4-5',
          'openai/gpt-4.1'
        ],
        reporter: [
          'anthropic/claude-sonnet-4-5',
          'openai/gpt-4.1'
        ]
      }.freeze

      MODE_CONFIG = T.let(
        {
          ResearchMode::Light => T.let(1, Integer),
          ResearchMode::Medium => T.let(3, Integer),
          ResearchMode::Hard => T.let(5, Integer),
          ResearchMode::Ultra => T.let(6, Integer)
        }.freeze,
        T::Hash[ResearchMode, Integer]
      )

      DEFAULT_MODE = ResearchMode::Medium

      class SectionResult < T::Struct
        class Status < T::Enum
          enums do
            Complete = new("complete")
            Partial = new("partial")
            InsufficientEvidence = new("insufficient_evidence")
          end
        end

        const :identifier, String
        const :title, String
        const :draft, String
        const :citations, T::Array[String]
        const :warnings, T::Array[String], default: []
        const :status, Status, default: Status::Complete
        const :attempt, Integer
      end

      class Result < T::Struct
        const :report, String
        const :sections, T::Array[SectionResult]
        const :citations, T::Array[String]
        const :warnings, T::Array[String], default: []
        const :budget_exhausted, T::Boolean, default: false
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
        configure_default_predictor_models
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

        mode = normalize_mode(input_values[:mode])

        reset_state!
        @current_mode = mode
        @current_mode_target_sections = mode_target_sections(mode)

        outline = @planner.call(brief: brief, mode: mode)
        sections = apply_mode_to_sections(outline.sections, @current_mode_target_sections)
        enqueue_sections(sections)

        while (section_spec = @section_queue.dequeue)
          attempts = @section_queue.attempts_for(section_spec)
          if attempts > @max_section_attempts
            raise DSPy::DeepResearch::QueueStarvationError,
                  "Section #{section_spec.identifier} exceeded max attempts (#{attempts}/#{@max_section_attempts})"
          end

          emit_section_started(section_spec, attempts)

          deep_search_module = build_deep_search(section_spec)
          deep_result = deep_search_module.call(question: section_spec.prompt)
          @token_budget_exhausted ||= deep_result.budget_exhausted

          evidence = merge_section_evidence(section_spec, deep_result)

          synthesized = @synthesizer.call(
            brief: brief,
            section: section_spec,
            answer: deep_result.answer,
            notes: evidence[:notes],
            citations: evidence[:citations]
          )

          citations = Array(synthesized.citations || evidence[:citations]).compact.uniq
          warnings = section_warnings(evidence, deep_result)
          base_status = deep_result.budget_exhausted ? SectionResult::Status::Partial : SectionResult::Status::Complete

          qa_decision = @qa_reviewer.call(
            brief: brief,
            section: section_spec,
            draft: synthesized.draft,
            notes: evidence[:notes],
            citations: evidence[:citations],
            attempt: attempts
          )

          case qa_decision.status
          when DSPy::DeepResearch::Signatures::QAReview::Status::Approved
            section_result = build_section_result(section_spec, synthesized, citations, attempts, base_status, warnings)
            accept_section(section_result)
          when DSPy::DeepResearch::Signatures::QAReview::Status::NeedsMoreEvidence
            follow_up_prompt = qa_decision.follow_up_prompt

            if deep_result.budget_exhausted
              warnings << insufficient_evidence_warning(section_spec)
              section_result = build_section_result(
                section_spec,
                synthesized,
                citations,
                attempts,
                SectionResult::Status::InsufficientEvidence,
                warnings
              )
              accept_section(section_result)
              emit_section_insufficient(section_spec, attempts, warnings.last)
              next
            end

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
          citations: merged_citations(Array(assembled.citations)),
          warnings: @warnings.dup,
          budget_exhausted: @token_budget_exhausted
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
        @warnings.concat(section.warnings)
        @warnings.uniq!

        DSPy.event(
          "deep_research.section.approved",
          identifier: section.identifier,
          title: section.title,
          attempt: section.attempt,
          citations: section.citations
        )

        emit_section_completion_status(section)
      end

      sig { params(section: SectionResult).void }
      def emit_section_completion_status(section)
        return if section.status == SectionResult::Status::Complete

        DSPy.event(
          "deep_research.section.partial",
          identifier: section.identifier,
          title: section.title,
          status: section.status.serialize,
          warnings: section.warnings
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
        @section_evidence = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
        @warnings = T.let([], T::Array[String])
        @token_budget_exhausted = T.let(false, T::Boolean)
        @current_mode = T.let(DEFAULT_MODE, ResearchMode)
        @current_mode_target_sections = T.let(mode_target_sections(DEFAULT_MODE), Integer)
      end

      sig { params(citations: T::Array[String]).returns(T::Array[String]) }
      def merged_citations(citations)
        (Array(citations) + @citations).compact.uniq
      end

      sig { params(section: SectionSpec, deep_result: DSPy::DeepSearch::Module::Result).returns(T::Hash[Symbol, T.untyped]) }
      def merge_section_evidence(section, deep_result)
        base = normalize_identifier(section)
        store = (@section_evidence[base] ||= { notes: [], citations: [], warnings: [], budget_exhausted: false })
        store[:notes] = (Array(store[:notes]) + Array(deep_result.notes)).compact.uniq
        store[:citations] = (Array(store[:citations]) + Array(deep_result.citations)).compact.uniq
        if deep_result.warning
          warnings = Array(store[:warnings]) + [deep_result.warning]
          store[:warnings] = warnings.compact.uniq
        else
          store[:warnings] = Array(store[:warnings])
        end
        store[:budget_exhausted] ||= deep_result.budget_exhausted
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

      sig { params(section: SectionSpec, attempt: Integer, warning: String).void }
      def emit_section_insufficient(section, attempt, warning)
        DSPy.event(
          "deep_research.section.insufficient_evidence",
          identifier: section.identifier,
          title: section.title,
          attempt: attempt,
          warning: warning
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

      sig { params(section_spec: SectionSpec, synthesized: T.untyped, citations: T::Array[String], attempts: Integer, status: SectionResult::Status, warnings: T::Array[String]).returns(SectionResult) }
      def build_section_result(section_spec, synthesized, citations, attempts, status, warnings)
        SectionResult.new(
          identifier: section_spec.identifier,
          title: section_spec.title,
          draft: synthesized.draft,
          citations: citations,
          warnings: warnings.dup,
          status: status,
          attempt: attempts
        )
      end

      sig { params(evidence: T::Hash[Symbol, T.untyped], deep_result: DSPy::DeepSearch::Module::Result).returns(T::Array[String]) }
      def section_warnings(evidence, deep_result)
        warnings = Array(evidence[:warnings]).dup
        warnings << deep_result.warning if deep_result.warning
        warnings.compact!
        warnings.uniq!
        if deep_result.budget_exhausted && warnings.empty?
          warnings << "Token budget exhausted while collecting evidence"
        end
        warnings
      end

      sig { params(section: SectionSpec).returns(String) }
      def insufficient_evidence_warning(section)
        "Token budget exhausted before QA approval for #{section.title}"
      end

      sig { params(raw_mode: T.untyped).returns(ResearchMode) }
      def normalize_mode(raw_mode)
        return DEFAULT_MODE if raw_mode.nil?
        return raw_mode if raw_mode.is_a?(ResearchMode)

        ResearchMode.deserialize(raw_mode.to_s)
      rescue ArgumentError
        DEFAULT_MODE
      end

      sig { params(mode: ResearchMode).returns(Integer) }
      def mode_target_sections(mode)
        MODE_CONFIG.fetch(mode) { MODE_CONFIG.fetch(DEFAULT_MODE) }
      end

      sig { params(sections: T::Array[SectionSpec], limit: Integer).returns(T::Array[SectionSpec]) }
      def apply_mode_to_sections(sections, limit)
        sections.first(limit).map do |section|
          SectionSpec.new(
            identifier: section.identifier,
            title: section.title,
            prompt: section.prompt,
            token_budget: section.token_budget,
            attempt: section.attempt,
            parent_identifier: section.parent_identifier
          )
        end
      end

      def configure_default_predictor_models
        @lm_cache = {}
        assign_model(@planner, :planner)
        assign_model(@qa_reviewer, :qa)
        assign_model(@synthesizer, :synthesizer)
        assign_model(@reporter, :reporter)
      end

      def env_model(role)
        key = MODEL_ENV_KEYS[role]
        value = key ? ENV[key] : nil
        return nil if value.nil?

        trimmed = value.strip
        trimmed.empty? ? nil : trimmed
      end

      def assign_model(predictor, role)
        return unless predictor
        return if predictor.respond_to?(:config) && predictor.config.lm

        candidates = []
        env_override = env_model(role)
        candidates << env_override if env_override
        candidates.concat(Array(MODEL_PRIORITY[role]))

        candidates.each do |model_id|
          next unless model_id
          lm = build_lm(model_id)
          next unless lm

          begin
            predictor.configure { |config| config.lm = lm }
            return
          rescue StandardError => e
            DSPy.logger&.warn(
              "DeepResearch predictor LM assignment error",
              role: role,
              model: model_id,
              error: e.message
            )
          end
        end

        DSPy.logger&.warn(
          "DeepResearch predictor LM assignment skipped (no viable model)",
          role: role
        )
      end

      def build_lm(model_id)
        @lm_cache ||= {}
        return @lm_cache[model_id] if @lm_cache.key?(model_id)

        provider = model_id.split('/', 2).first
        api_key = api_key_for(provider)
        unless api_key && !api_key.strip.empty?
          DSPy.logger&.warn(
            "DeepResearch skipped LM assignment due to missing API key",
            model: model_id,
            provider: provider
          )
          return nil
        end

        @lm_cache[model_id] = DSPy::LM.new(model_id, api_key: api_key)
      rescue StandardError => e
        DSPy.logger&.warn(
          "DeepResearch failed to initialize LM",
          model: model_id,
          error: e.message
        )
        nil
      end

      def api_key_for(provider)
        case provider
        when 'openai'
          ENV['OPENAI_API_KEY']
        when 'anthropic'
          ENV['ANTHROPIC_API_KEY']
        when 'gemini'
          ENV['GEMINI_API_KEY']
        when 'google'
          ENV['GEMINI_API_KEY'] || ENV['GOOGLE_API_KEY']
        else
          nil
        end
      end
    end
  end
end
