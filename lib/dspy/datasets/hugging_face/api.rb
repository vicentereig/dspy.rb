# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'time'

module DSPy
  module Datasets
    module HuggingFace
      class APIError < StandardError; end

      class DatasetSummary < T::Struct
        const :id, String
        const :author, T.nilable(String)
        const :disabled, T::Boolean
        const :gated, T::Boolean
        const :private, T::Boolean
        const :likes, T.nilable(Integer)
        const :downloads, T.nilable(Integer)
        const :tags, T::Array[String]
        const :sha, T.nilable(String)
        const :last_modified, T.nilable(Time)
        const :description, T.nilable(String)
      end

      class Sibling < T::Struct
        const :rfilename, String
        const :size, T.nilable(Integer)
      end

      class DatasetDetails < T::Struct
        const :summary, DatasetSummary
        const :card_data, T.nilable(T::Hash[String, T.untyped])
        const :siblings, T::Array[Sibling]
        const :configs, T::Array[T::Hash[String, T.untyped]]
      end

      class ParquetListing < T::Struct
        const :files, T::Hash[String, T::Hash[String, T::Array[String]]]
      end

      class Tag < T::Struct
        const :id, String
        const :label, String
        const :type, String
      end

      class TagsByType < T::Struct
        const :tags, T::Hash[String, T::Array[Tag]]
      end

      class ListParams < T::Struct
        const :search, T.nilable(String)
        const :author, T.nilable(String)
        const :filter, T.nilable(T::Array[String])
        const :sort, T.nilable(String)
        const :direction, T.nilable(Integer)
        const :limit, T.nilable(Integer)
        const :offset, T.nilable(Integer)
        const :full, T.nilable(T::Boolean)
      end

      class Client
        extend T::Sig

        BASE_URL = 'https://huggingface.co'
        DEFAULT_TIMEOUT = 15

        sig { params(base_url: String, timeout: Integer).void }
        def initialize(base_url: BASE_URL, timeout: DEFAULT_TIMEOUT)
          @base_url = base_url
          @timeout = timeout
        end

        sig { params(params: ListParams).returns(T::Array[DatasetSummary]) }
        def list_datasets(params = ListParams.new)
          query = build_list_query(params)
          payload = get('/api/datasets', query)
          unless payload.is_a?(Array)
            raise APIError, 'Unexpected response when listing datasets'
          end

          payload.map { |entry| parse_dataset_summary(entry) }
        end

        sig { params(repo_id: String, full: T.nilable(T::Boolean), revision: T.nilable(String)).returns(DatasetDetails) }
        def dataset(repo_id, full: nil, revision: nil)
          path = if revision
                   "/api/datasets/#{repo_id}/revision/#{revision}"
                 else
                   "/api/datasets/#{repo_id}"
                 end
          query = {}
          query[:full] = full ? 1 : 0 unless full.nil?
          payload = get(path, query)
          DatasetDetails.new(
            summary: parse_dataset_summary(payload),
            card_data: payload['cardData'],
            siblings: Array(payload['siblings']).map { |item| Sibling.new(rfilename: item['rfilename'].to_s, size: item['size']) },
            configs: Array(payload['configs']).map { |config| config }
          )
        end

        sig { params(repo_id: String).returns(ParquetListing) }
        def dataset_parquet(repo_id)
          payload = get("/api/datasets/#{repo_id}/parquet")
          unless payload.is_a?(Hash)
            raise APIError, 'Unexpected parquet listing response'
          end

          files = payload.each_with_object({}) do |(config, splits), acc|
            acc[config] = splits.each_with_object({}) do |(split, urls), split_acc|
              split_acc[split] = Array(urls).map(&:to_s)
            end
          end

          ParquetListing.new(files: files)
        end

        sig { returns(TagsByType) }
        def dataset_tags_by_type
          payload = get('/api/datasets-tags-by-type')
          unless payload.is_a?(Hash)
            raise APIError, 'Unexpected dataset tags response'
          end

          tags = payload.each_with_object({}) do |(category, items), acc|
            acc[category] = Array(items).map do |item|
              Tag.new(
                id: item.fetch('id').to_s,
                label: item.fetch('label').to_s,
                type: item.fetch('type').to_s
              )
            end
          end

          TagsByType.new(tags: tags)
        end

        private

        sig { params(path: String, params: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
        def get(path, params = {})
          uri = build_uri(path, params)
          request = Net::HTTP::Get.new(uri)
          request['Accept'] = 'application/json'

          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: @timeout, open_timeout: @timeout) do |http|
            http.request(request)
          end

          unless response.is_a?(Net::HTTPSuccess)
            raise APIError, "Hugging Face API request failed: #{response.code} #{response.message}"
          end

          JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise APIError, "Failed to parse Hugging Face API response: #{e.message}"
        end

        sig { params(path: String, params: T::Hash[Symbol, T.untyped]).returns(URI::HTTPS) }
        def build_uri(path, params)
          uri = URI.join(@base_url, path)
          unless params.empty?
            # Expand repeated filters if present
            query_pairs = params.each_with_object([]) do |(key, value), acc|
              next if value.nil?

              if key == :filter && value.is_a?(Array)
                value.each { |filter| acc << ["filter", filter.to_s] }
              else
                acc << [key.to_s, format_query_value(value)]
              end
            end
            uri.query = URI.encode_www_form(query_pairs)
          end
          uri
        end

        sig { params(value: T.untyped).returns(String) }
        def format_query_value(value)
          case value
          when TrueClass, FalseClass
            value ? '1' : '0'
          else
            value.to_s
          end
        end

        sig { params(payload: T::Hash[String, T.untyped]).returns(DatasetSummary) }
        def parse_dataset_summary(payload)
          DatasetSummary.new(
            id: payload.fetch('id').to_s,
            author: payload['author'],
            disabled: payload.fetch('disabled', false),
            gated: payload.fetch('gated', false),
            private: payload.fetch('private', false),
            likes: payload['likes'],
            downloads: payload['downloads'],
            tags: Array(payload['tags']).map(&:to_s),
            sha: payload['sha'],
            last_modified: parse_time(payload['lastModified']),
            description: payload['description']
          )
        end

        sig { params(params: ListParams).returns(T::Hash[Symbol, T.untyped]) }
        def build_list_query(params)
          query = {
            search: params.search,
            author: params.author,
            sort: params.sort,
            direction: params.direction,
            limit: params.limit,
            offset: params.offset,
            full: params.full
          }.reject { |_, value| value.nil? }

          query[:filter] = params.filter if params.filter

          query
        end

        sig { params(value: T.untyped).returns(T.nilable(Time)) }
        def parse_time(value)
          return nil unless value

          Time.parse(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
