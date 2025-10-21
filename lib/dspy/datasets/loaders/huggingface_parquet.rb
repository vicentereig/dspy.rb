# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'parquet'

module DSPy
  module Datasets
    module Loaders
      class HuggingFaceParquet
        BASE_URL = 'https://datasets-server.huggingface.co'

        def initialize(info, split:, cache_dir:)
          @info = info
          @split = split
          @cache_root = determine_cache_root(cache_dir)
        end

        def each_row
          return enum_for(:each_row) unless block_given?

          parquet_files.each do |file|
            table = load_table(file)
            field_names = table.schema.fields.map(&:name)
            table.raw_records.each do |values|
              yield normalized_row(field_names, values)
            end
          end
        end

        def row_count
          @row_count ||= parquet_files.sum do |file|
            load_table(file).n_rows
          end
        end

        private

        attr_reader :info, :split, :cache_root

        def normalized_row(field_names, values)
          field_names.each_with_index.each_with_object({}) do |(name, index), row|
            row[name] = values[index]
          end
        end

        def load_table(file)
          Arrow::Table.load(ensure_cached(file))
        end

        def parquet_files
          @parquet_files ||= begin
            datasets = Array(info.loader_options.fetch(:dataset))
            last_error = nil

            datasets.each do |dataset_name|
              begin
                files = fetch_parquet_files(dataset_name)
                return files unless files.empty?
                last_error = DatasetError.new("No parquet files available for #{dataset_name} (#{split})")
              rescue DatasetError => e
                last_error = e
              end
            end

            raise(last_error || DatasetError.new("Failed to fetch parquet manifest for #{info.id} (#{split})"))
          end
        end

        def ensure_cached(file)
          FileUtils.mkdir_p(cache_dir)
          path = File.join(cache_dir, file.fetch('filename'))
          return path if File.exist?(path) && File.size?(path)

          download_file(file.fetch('url'), path)
          path
        end

        def fetch_parquet_files(dataset_name)
          uri = URI("#{BASE_URL}/parquet")
          params = {
            dataset: dataset_name,
            config: info.loader_options.fetch(:config),
            split: split
          }
          uri.query = URI.encode_www_form(params)

          response = http_get(uri)
          unless response.is_a?(Net::HTTPSuccess)
            raise DatasetError, "Failed to fetch parquet manifest: #{response.code}"
          end

          body = JSON.parse(response.body)
          body.fetch('parquet_files', [])
        end

        def cache_dir
          @cache_dir ||= File.join(cache_root, split)
        end

        def determine_cache_root(cache_dir)
          base = if cache_dir
                   File.expand_path(cache_dir)
                 elsif ENV['DSPY_DATASETS_CACHE']
                   File.expand_path(ENV['DSPY_DATASETS_CACHE'])
                 else
                   File.expand_path('../../../../tmp/dspy_datasets', __dir__)
                 end
          File.join(base, sanitized_dataset_id)
        end

        def sanitized_dataset_id
          info.id.gsub(/[^\w.-]+/, '_')
        end

        def http_get(uri)
          perform_request_with_redirects(uri)
        end

        def download_file(url, destination)
          fetch_with_redirects(URI(url)) do |response|
            File.binwrite(destination, response.body)
          end
        rescue => e
          File.delete(destination) if File.exist?(destination)
          raise
        end

        MAX_REDIRECTS = 5

        def perform_request_with_redirects(uri, limit = MAX_REDIRECTS)
          raise DownloadError, 'Too many HTTP redirects' if limit <= 0

          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            request = Net::HTTP::Get.new(uri)
            response = http.request(request)

            if response.is_a?(Net::HTTPRedirection)
              location = response['location']
              raise DownloadError, 'Redirect without location header' unless location

              new_uri = URI(location)
              new_uri = uri + location if new_uri.relative?
              return perform_request_with_redirects(new_uri, limit - 1)
            end

            response
          end
        end

        def fetch_with_redirects(uri, limit = MAX_REDIRECTS, &block)
          response = perform_request_with_redirects(uri, limit)

          unless response.is_a?(Net::HTTPSuccess)
            message = response ? "Failed to download parquet file: #{response.code}" : 'Failed to download parquet file'
            raise DownloadError, message
          end

          return yield response if block_given?
          response
        end
      end
    end
  end
end
