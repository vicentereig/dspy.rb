# frozen_string_literal: true

module DSPy
  module DeepSearch
    class Module < DSPy::Module
      extend T::Sig

      class Result < T::Struct
        const :answer, String
        const :notes, T::Array[String]
        const :citations, T::Array[String]
        const :budget_exhausted, T::Boolean, default: false
        const :warning, T.nilable(String), default: nil
      end

      class TokenBudgetExceeded < DSPy::Error; end

      DEFAULT_SEARCH_RESULTS = 5

      MODEL_ENV_KEYS = {
        seed: 'DSPY_DEEP_SEARCH_SEED_MODEL',
        reader: 'DSPY_DEEP_SEARCH_READER_MODEL',
        reason: 'DSPY_DEEP_SEARCH_REASON_MODEL'
      }.freeze

      MODEL_PRIORITY = {
        seed: [
          'gemini/gemini-2.5-flash-lite',
          'anthropic/claude-haiku-4-5'
        ],
        reader: [
          'anthropic/claude-sonnet-4-5',
          'openai/gpt-4.1'
        ],
        reason: [
          'gemini/gemini-2.5-pro',
          'openai/o4-mini',
          'anthropic/claude-4.1-opus'
        ]
      }.freeze

      subscribe 'lm.tokens', :meter_tokens

      sig do
        params(
          token_budget: DSPy::DeepSearch::TokenBudget,
          seed_predictor: T.untyped,
          search_predictor: T.nilable(T.untyped),
          reader_predictor: T.untyped,
          reason_predictor: T.untyped,
          search_client: DSPy::DeepSearch::Clients::ExaClient
        ).void
      end
      def initialize(
        token_budget: DSPy::DeepSearch::TokenBudget.new(limit: 20_000),
        seed_predictor: DSPy::Predict.new(DSPy::DeepSearch::Signatures::SeedQuery),
        search_predictor: nil,
        reader_predictor: DSPy::Predict.new(DSPy::DeepSearch::Signatures::ReadSource),
        reason_predictor: DSPy::Predict.new(DSPy::DeepSearch::Signatures::ReasonStep),
        search_client: DSPy::DeepSearch::Clients::ExaClient.new
      )
        super()

        @token_budget = token_budget
        @token_budget_limit = token_budget.limit
        @seed_predictor = seed_predictor
        @search_predictor = search_predictor
        @reader_predictor = reader_predictor
        @reason_predictor = reason_predictor
        @search_client = search_client
        @gap_queue = DSPy::DeepSearch::GapQueue.new

        configure_default_predictor_models
      end

      def forward_untyped(**input_values)
        question = input_values[:question]
        unless question.is_a?(String)
          raise ArgumentError, "DeepSearch expects keyword argument :question"
        end

        reset_state!
        process_question(question)
      rescue DSPy::DeepSearch::TokenBudget::Exceeded => e
        build_budget_exhausted_result(question, e)
      end

      sig { override.returns(T::Array[[String, DSPy::Module]]) }
      def named_predictors
        pairs = []
        pairs << ["seed_predictor", @seed_predictor] if @seed_predictor
        pairs << ["search_predictor", T.must(@search_predictor)] if @search_predictor
        pairs << ["reader_predictor", @reader_predictor] if @reader_predictor
        pairs << ["reason_predictor", @reason_predictor] if @reason_predictor
        pairs
      end

      sig { override.returns(T::Array[DSPy::Module]) }
      def predictors
        named_predictors.map { |(_, predictor)| predictor }
      end

      sig { params(instruction: String).returns(Module) }
      def with_instruction(instruction)
        clone_with(
          seed_predictor: apply_instruction(@seed_predictor, instruction),
          search_predictor: apply_instruction(@search_predictor, instruction),
          reader_predictor: apply_instruction(@reader_predictor, instruction),
          reason_predictor: apply_instruction(@reason_predictor, instruction),
          token_budget_limit: @token_budget_limit
        )
      end

      sig { params(examples: T::Array[DSPy::FewShotExample]).returns(Module) }
      def with_examples(examples)
        examples_copy = examples.map { |example| example }
        clone_with(
          seed_predictor: apply_examples(@seed_predictor, examples_copy),
          search_predictor: apply_examples(@search_predictor, examples_copy),
          reader_predictor: apply_examples(@reader_predictor, examples_copy),
          reason_predictor: apply_examples(@reason_predictor, examples_copy),
          token_budget_limit: @token_budget_limit
        )
      end
      sig { params(limit: Integer).returns(Module) }
      def with_token_budget(limit)
        clone_with(
          seed_predictor: @seed_predictor,
          search_predictor: @search_predictor,
          reader_predictor: @reader_predictor,
          reason_predictor: @reason_predictor,
          token_budget_limit: limit
        )
      end

      private

      sig { params(question: String).returns(Result) }
      def process_question(question)
        query = @seed_predictor.call(question: question).query
        loop do
          emit_loop_started(question, query)

          urls = fetch_search_urls(query)
          break if urls.empty?

          urls.each { |url| enqueue_url(url) }
          collect_notes

          decision = @reason_predictor.call(question: question, insights: @notes)
          emit_reason_decision(question, decision)

          case decision.decision
          when DSPy::DeepSearch::Signatures::ReasonStep::Decision::Answer
            answer_text = decision.draft_answer || synthesize_answer
            return Result.new(answer: answer_text, notes: @notes.dup, citations: @citations.dup)
          when DSPy::DeepSearch::Signatures::ReasonStep::Decision::ContinueSearch
            query = decision.refined_query || query
            next
          when DSPy::DeepSearch::Signatures::ReasonStep::Decision::ReadMore
            collect_notes if pending_urls?
            next
          end
        end

        Result.new(answer: synthesize_answer, notes: @notes.dup, citations: @citations.dup)
      end

      sig { params(url: String).void }
      def enqueue_url(url)
        @gap_queue.enqueue(url)
      end

      sig { returns(T::Boolean) }
      def pending_urls?
        !@gap_queue.empty?
      end

      sig { void }
      def collect_notes
        until @gap_queue.empty?
          url = @gap_queue.dequeue
          fetch_and_extract(url)
        end
      end

      sig { params(url: String).void }
      def fetch_and_extract(url)
        DSPy.event(
          "deep_search.fetch.started",
          url: url
        )

        notes_before = @notes.length
        citations_before = @citations.length

        contents = @search_client.contents(urls: [url])
        record_notes(url, contents)
        reader_notes = @reader_predictor.call(url: url).notes
        @notes.concat(Array(reader_notes))

        DSPy.event(
          "deep_search.fetch.completed",
          url: url,
          notes_added: @notes.length - notes_before,
          citations_added: @citations.length - citations_before,
          token_budget_remaining: token_budget_remaining
        )
      rescue DSPy::DeepSearch::Clients::ExaClient::ApiError => e
        DSPy.event(
          "deep_search.fetch.failed",
          url: url,
          error: e.message
        )
        DSPy.logger&.warn("DeepSearch fetch failed", url: url, error: e.message)
      end

      sig { params(url: String, contents: T::Array[DSPy::DeepSearch::Clients::ExaClient::Content]).void }
      def record_notes(url, contents)
        contents.each do |content|
          if content.summary
            @notes << content.summary
          end
          content.highlights.each do |highlight|
            @notes << highlight
          end
          @citations << url unless @citations.include?(url)
        end
      end

      sig { returns(String) }
      def synthesize_answer
        return "" if @notes.empty?

        @notes.first(5).join("\n")
      end

      sig { void }
      def reset_state!
        @notes = []
        @citations = []
        @gap_queue = DSPy::DeepSearch::GapQueue.new
      end

      sig { params(query: String).returns(T::Array[String]) }
      def fetch_search_urls(query)
        if @search_predictor
          Array(@search_predictor.call(query: query).urls).compact
        else
          results = Array(
            @search_client.search(
              query: query,
              num_results: DEFAULT_SEARCH_RESULTS,
              autoprompt: true
            )
          )
          results.map do |result|
            if result.respond_to?(:url)
              result.url
            elsif result.is_a?(Hash)
              result[:url] || result['url']
            else
              nil
            end
          end.compact.uniq
        end
      end

      sig { params(_event_name: String, attrs: T::Hash[Symbol, T.untyped]).void }
      def meter_tokens(_event_name, attrs)
        @token_budget.track!(
          prompt_tokens: attrs[:input_tokens].to_i,
          completion_tokens: attrs[:output_tokens].to_i
        )
      end

      sig do
        params(
          seed_predictor: T.untyped,
          search_predictor: T.nilable(T.untyped),
          reader_predictor: T.untyped,
          reason_predictor: T.untyped,
          token_budget_limit: Integer
        ).returns(Module)
      end
      def clone_with(seed_predictor:, search_predictor:, reader_predictor:, reason_predictor:, token_budget_limit: @token_budget_limit)
        self.class.new(
          token_budget: DSPy::DeepSearch::TokenBudget.new(limit: token_budget_limit),
          seed_predictor: seed_predictor,
          search_predictor: search_predictor,
          reader_predictor: reader_predictor,
          reason_predictor: reason_predictor,
          search_client: @search_client
        )
      end

      sig { params(predictor: T.nilable(T.untyped), instruction: String).returns(T.nilable(T.untyped)) }
      def apply_instruction(predictor, instruction)
        return nil if predictor.nil?
        return predictor.with_instruction(instruction) if predictor.respond_to?(:with_instruction)
        predictor
      end

      sig { params(predictor: T.nilable(T.untyped), examples: T::Array[DSPy::FewShotExample]).returns(T.nilable(T.untyped)) }
      def apply_examples(predictor, examples)
        return nil if predictor.nil?
        return predictor.with_examples(examples) if predictor.respond_to?(:with_examples)
        predictor
      end

      sig { params(question: String, query: String).void }
      def emit_loop_started(question, query)
        DSPy.event(
          "deep_search.loop.started",
          question: question,
          query: query,
          token_budget_remaining: token_budget_remaining
        )
      end

      sig { params(question: String, decision: T.untyped).void }
      def emit_reason_decision(question, decision)
        decision_enum = decision.respond_to?(:decision) ? decision.decision : nil
        serialized_decision =
          if decision_enum.respond_to?(:serialize)
            decision_enum.serialize
          elsif decision_enum.respond_to?(:to_s)
            decision_enum.to_s
          else
            nil
          end

        DSPy.event(
          "deep_search.reason.decision",
          question: question,
          decision: serialized_decision,
          notes_count: @notes.length,
          citations_count: @citations.length,
          refined_query: decision.respond_to?(:refined_query) ? decision.refined_query : nil,
          draft_answer: decision.respond_to?(:draft_answer) ? decision.draft_answer : nil,
          token_budget_remaining: token_budget_remaining
        )
      end

      sig { returns(Integer) }
      def token_budget_remaining
        remaining = @token_budget_limit - @token_budget.total_tokens
        remaining.negative? ? 0 : remaining
      end

      def configure_default_predictor_models
        @lm_cache = {}
        assign_model(@seed_predictor, :seed)
        assign_model(@reader_predictor, :reader)
        assign_model(@reason_predictor, :reason)
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
              "DeepSearch predictor LM assignment error",
              role: role,
              model: model_id,
              error: e.message
            )
          end
        end

        DSPy.logger&.warn(
          "DeepSearch predictor LM assignment skipped (no viable model)",
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
            "DeepSearch skipped LM assignment due to missing API key",
            model: model_id,
            provider: provider
          )
          return nil
        end

        @lm_cache[model_id] = DSPy::LM.new(model_id, api_key: api_key)
      rescue StandardError => e
        DSPy.logger&.warn(
          "DeepSearch failed to initialize LM",
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

      sig { params(question: String, error: DSPy::DeepSearch::TokenBudget::Exceeded).returns(Result) }
      def build_budget_exhausted_result(question, error)
        warning = error.message
        DSPy.event(
          "deep_search.budget.exhausted",
          question: question,
          notes_count: @notes.length,
          citations_count: @citations.length,
          token_budget_limit: @token_budget_limit,
          total_tokens: @token_budget.total_tokens,
          warning: warning
        )

        Result.new(
          answer: synthesize_answer,
          notes: @notes.dup,
          citations: @citations.dup,
          budget_exhausted: true,
          warning: warning
        )
      end
    end
  end
end
