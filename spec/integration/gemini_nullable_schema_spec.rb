# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gemini nullable structured output contract' do
  before do
    stub_const('GeminiChoiceCheck', Class.new(T::Struct) do
      const :choices, T.nilable(T::Array[String]), default: nil,
        description: 'Three or four answer options, or null.'
    end)
  end

  [ ['Hello', 'Goodbye', 'Thank you'], nil ].each do |choices|
    it "sends a nullable array schema and deserializes #{choices.nil? ? 'null' : 'array'} responses" do
      signature = Class.new(DSPy::Signature) do
        input { const :topic, String }
        output { const :checks, T::Array[GeminiChoiceCheck] }
      end
      lm = DSPy::LM.new('gemini/gemini-2.5-flash', api_key: 'test-key', structured_outputs: true)
      client = lm.adapter.instance_variable_get(:@client)
      request = nil
      allow(client).to receive(:stream_generate_content) do |params, &consume|
        request = params
        consume.call({
          'candidates' => [{
            'content' => { 'parts' => [{ 'text' => JSON.generate(checks: [{ choices: choices }]) }] },
            'finishReason' => 'STOP'
          }]
        })
      end

      result = DSPy.with_lm(lm) { DSPy::Predict.new(signature).call(topic: 'Greetings') }

      expect(result.checks.first.choices).to eq(choices)
      config = request.fetch(:generation_config)
      expect(config[:response_mime_type]).to eq('application/json')
      check = config.dig(:response_json_schema, :properties, :checks, :items)
      expect(check.dig(:properties, :choices)).to eq(
        type: ['array', 'null'], items: { type: 'string' },
        description: 'Three or four answer options, or null.'
      )
      expect(check[:additionalProperties]).to be(false)
    end
  end
end
