# frozen_string_literal: true

module DSPy
  module DeepSearch
    class Module < DSPy::Module
      extend T::Sig

      class Result < T::Struct
        const :answer, String
        const :notes, T::Array[String]
        const :citations, T::Array[String]
      end

      class TokenBudgetExceeded < DSPy::Error; end

      DEFAULT_SEARCH_RESULTS = 5

      subscribe 'llm.tokens', :meter_tokens

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
      end

      def forward_untyped(**input_values)
        question = input_values[:question]
        unless question.is_a?(String)
          raise ArgumentError, "DeepSearch expects keyword argument :question"
        end

        reset_state!
        process_question(question)
      rescue DSPy::DeepSearch::TokenBudget::Exceeded => e
        raise TokenBudgetExceeded, e.message
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
          reason_predictor: apply_instruction(@reason_predictor, instruction)
        )
      end

      sig { params(examples: T::Array[DSPy::FewShotExample]).returns(Module) }
      def with_examples(examples)
        examples_copy = examples.map { |example| example }
        clone_with(
          seed_predictor: apply_examples(@seed_predictor, examples_copy),
          search_predictor: apply_examples(@search_predictor, examples_copy),
          reader_predictor: apply_examples(@reader_predictor, examples_copy),
          reason_predictor: apply_examples(@reason_predictor, examples_copy)
        )
      end

      private

      sig { params(question: String).returns(Result) }
      def process_question(question)
        query = @seed_predictor.call(question: question).query
        loop do
          urls = fetch_search_urls(query)
          break if urls.empty?

          urls.each { |url| enqueue_url(url) }
          collect_notes

          decision = @reason_predictor.call(question: question, insights: @notes)
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

        Result.new(answer: synthesize_answer, notes: @notes, citations: @citations)
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
        contents = @search_client.contents(urls: [url])
        record_notes(url, contents)
        reader_notes = @reader_predictor.call(url: url).notes
        @notes.concat(Array(reader_notes))
      rescue DSPy::DeepSearch::Clients::ExaClient::ApiError => e
        DSPy.logger&.warn("DeepSearch fetch failed", url: url, error: e.message)
      end

      sig { params(url: String, contents: T::Array[DSPy::DeepSearch::Clients::ExaClient::Content]).void }
      def record_notes(url, contents)
        contents.each do |content|
          token_count = Array(content.highlights).join(" ").split.size + (content.summary.to_s.split.size)
          @token_budget.track!(prompt_tokens: 0, completion_tokens: token_count)

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
          reason_predictor: T.untyped
        ).returns(Module)
      end
      def clone_with(seed_predictor:, search_predictor:, reader_predictor:, reason_predictor:)
        self.class.new(
          token_budget: DSPy::DeepSearch::TokenBudget.new(limit: @token_budget_limit),
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

    end
  end
end
