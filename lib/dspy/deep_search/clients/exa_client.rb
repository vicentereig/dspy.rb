# frozen_string_literal: true

module DSPy
  module DeepSearch
    module Clients
      class ExaClient
        extend T::Sig

        class Error < StandardError; end
        class ConfigurationError < Error; end
        class ApiError < Error; end

        class Result < T::Struct
          const :url, String
          const :title, T.nilable(String)
          const :summary, T.nilable(String)
          const :highlights, T::Array[String]
          const :score, T.nilable(Float)
        end

        class Content < T::Struct
          const :url, String
          const :text, T.nilable(String)
          const :summary, T.nilable(String)
          const :highlights, T::Array[String]
        end

        sig { params(client: T.nilable(::Exa::Client)).void }
        def initialize(client: nil)
          @client = T.let(client || build_client, ::Exa::Client)
        end

        sig do
          params(
            query: String,
            num_results: Integer,
            autoprompt: T::Boolean
          ).returns(T::Array[Result])
        end
        def search(query:, num_results: 5, autoprompt: true)
          response = with_api_errors do
            client.search.search(
              query: query,
              num_results: num_results,
              use_autoprompt: autoprompt,
              summary: true
            )
          end

          response.results.filter_map do |result|
            next if result.url.nil?

            Result.new(
              url: result.url,
              title: result.title,
              summary: result.summary,
              highlights: normalize_highlights(result.highlights),
              score: result.score
            )
          end
        end

        sig do
          params(
            urls: T::Array[String],
            options: T::Hash[Symbol, T.untyped]
          ).returns(T::Array[Content])
        end
        def contents(urls:, **options)
          raise ArgumentError, "urls must not be empty" if urls.empty?

          defaults = {
            text: true,
            summary: true,
            highlights: true,
            filter_empty_results: true
          }

          payload = Exa::Types::ContentsRequest.new(**defaults.merge(options).merge(urls: urls)).to_payload

          raw_response = with_api_errors do
            client.request(
              method: :post,
              path: "contents",
              body: payload,
              response_model: nil
            )
          end

          symbolized = symbolize_keys(raw_response)

          check_content_statuses!(symbolized)

          Array(symbolized[:results]).each_with_index.filter_map do |result, index|
            result = symbolize_keys(result)
            url = result[:url] || urls[index]
            next if url.nil?

            Content.new(
              url: url,
              text: result[:text],
              summary: result[:summary],
              highlights: normalize_highlights(result[:highlights])
            )
          end
        end

        private

        sig { returns(::Exa::Client) }
        def build_client
          ::Exa::Client.new
        rescue ::Exa::Errors::ConfigurationError => e
          raise ConfigurationError, e.message
        end

        sig { params(response: T::Hash[Symbol, T.untyped]).void }
        def check_content_statuses!(response)
          statuses = response[:statuses]
          return if statuses.nil?

          failure = Array(statuses).map { |status| symbolize_keys(status) }.find { |status| status[:status] != "success" }
          return if failure.nil?

          error_details = failure[:error] ? failure[:error].inspect : nil
          message = [
            "Exa contents request failed for #{failure[:id]}",
            failure[:status],
            error_details
          ].compact.join(" - ")

          raise ApiError, message
        end

        sig { params(hash: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def symbolize_keys(hash)
          case hash
          when Hash
            hash.each_with_object({}) do |(key, value), acc|
              acc[(key.is_a?(String) ? key.to_sym : key)] = value
            end
          else
            {}
          end
        end

        sig { params(highlights: T.nilable(T::Array[T.nilable(String)])).returns(T::Array[String]) }
        def normalize_highlights(highlights)
          Array(highlights).compact.map(&:to_s)
        end

        sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
        def with_api_errors(&block)
          block.call
        rescue ::Exa::Errors::ConfigurationError => e
          raise ConfigurationError, e.message
        rescue ::Exa::Errors::APIError => e
          raise ApiError, e.message
        rescue ::Exa::Error => e
          raise ApiError, e.message
        end

        sig { returns(::Exa::Client) }
        attr_reader :client
      end
    end
  end
end
