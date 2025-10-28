# frozen_string_literal: true

require "aruba/rspec"

RSpec.configure do |config|
  config.include Aruba::Api, type: :aruba

  config.before(:each, type: :aruba) do
    setup_aruba
  end
end
