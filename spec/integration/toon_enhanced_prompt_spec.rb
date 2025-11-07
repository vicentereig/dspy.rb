# frozen_string_literal: true

require 'spec_helper'

class EnhancedToonSignature < DSPy::Signature
  description 'Break down topics using TOON-enhanced prompting'

  input do
    const :topic, String
    const :context, String
  end

  output do
    const :subtasks, T::Array[String]
    const :task_types, T::Array[String]
    const :priority_order, T::Array[Integer]
    const :estimates, T::Array[Integer]
  end
end

RSpec.describe 'Enhanced TOON prompt end-to-end', type: :integration do
  cassette_path = File.join('spec', 'vcr_cassettes', 'integration', 'toon_enhanced_prompt.yml')
  let(:api_key_present) { ENV['OPENAI_API_KEY'].to_s.strip != '' }
  let(:cassette_available) { File.exist?(cassette_path) }

  before do
    skip "Requires OPENAI_API_KEY or existing cassette" unless api_key_present || cassette_available

    DSPy.configure do |config|
      config.lm = DSPy::LM.new(
        'openai/gpt-4o-mini',
        api_key: ENV['OPENAI_API_KEY'] || 'test-openai-key',
        schema_format: :baml,
        data_format: :toon
      )
    end
  end

  it 'round-trips predict flow using TOON format with VCR' do
    VCR.use_cassette('integration/toon_enhanced_prompt') do
      predictor = DSPy::Predict.new(EnhancedToonSignature)

      result = predictor.call(
        topic: 'Sustainable technology adoption',
        context: 'Focus on community microgrids'
      )

      expect(result.subtasks).to all(be_a(String))
      expect(result.task_types.length).to eq(result.subtasks.length)
      expect(result.priority_order).to all(be_a(Integer))
      expect(result.estimates).to all(be_a(Integer))
    end
  end
end
