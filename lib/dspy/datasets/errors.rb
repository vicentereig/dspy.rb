# frozen_string_literal: true

module DSPy
  module Datasets
    class DatasetError < StandardError; end
    class DatasetNotFoundError < DatasetError; end
    class InvalidSplitError < DatasetError; end
    class DownloadError < DatasetError; end
  end
end
