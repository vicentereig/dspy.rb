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
            uri = URI("#{BASE_URL}/parquet")
            params = {
              dataset: info.loader_options.fetch(:dataset),
              config: info.loader_options.fetch(:config),
              split: split
            }
            uri.query = URI.encode_www_form(params)

            response = http_get(uri)
            unless response.is_a?(Net::HTTPSuccess)
              raise DatasetError, "Failed to fetch parquet manifest: #{response.code}"
            end

            body = JSON.parse(response.body)
            files = body.fetch('parquet_files', [])
            raise DatasetError, "No parquet files available for #{info.id} (#{split})" if files.empty?

            files
          end
        end

        def ensure_cached(file)
          FileUtils.mkdir_p(cache_dir)
          path = File.join(cache_dir, file.fetch('filename'))
          return path if File.exist?(path) && File.size?(path)

          download_file(file.fetch('url'), path)
          path
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
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            request = Net::HTTP::Get.new(uri)
            http.request(request)
          end
        end

        def download_file(url, destination)
          uri = URI(url)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            request = Net::HTTP::Get.new(uri)
            http.request(request) do |response|
              unless response.is_a?(Net::HTTPSuccess)
                raise DownloadError, "Failed to download parquet file: #{response.code}"
              end

              File.open(destination, 'wb') do |file|
                response.read_body do |chunk|
                  file.write(chunk)
                end
              end
            end
          end
        rescue => e
          File.delete(destination) if File.exist?(destination)
          raise
        end
      end
    end
  end
end
