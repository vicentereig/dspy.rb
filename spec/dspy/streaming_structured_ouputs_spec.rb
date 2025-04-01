require 'spec_helper'

RSpec.describe 'streaming structured outputs' do
  it 'streams a structured output response for inspection' do
    VCR.use_cassette('openai/gpt4o-mini/streaming-json-response-v1') do

    end
  end

end
