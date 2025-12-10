# frozen_string_literal: true

require 'spec_helper'
require 'sorbet/toon'

class ToonReActSignature < DSPy::Signature
  description 'ReAct signature for TOON data format'

  input do
    const :question, String
  end

  output do
    const :answer, String
  end
end

class CityFact < T::Struct
  const :city, String
  const :population, Integer
end

class ToonLookupTool < DSPy::Tools::Base
  extend T::Sig

  tool_name 'lookup_city'
  tool_description 'Return structured population data for a given city'

  sig { params(city: String).returns(CityFact) }
  def call(city:)
    CityFact.new(city: city, population: 2_148_000)
  end
end

RSpec.describe 'ReAct with TOON data format', type: :integration do

  let(:mock_adapter) { instance_double('Adapter') }
  let(:usage) { DSPy::LM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0) }

  before do
    allow(DSPy::LM::AdapterFactory).to receive(:create).and_return(mock_adapter)

    DSPy.configure do |c|
      c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :toon, data_format: :toon)
    end
  end

  it 'parses TOON tool calls in ReAct loop' do
    iteration_payload = Sorbet::Toon.encode(
      {
        thought: 'Need to finish',
        action: 'finish',
        action_input: 'answer'
      },
      signature: ToonReActSignature,
      role: :output
    )

    allow(mock_adapter).to receive(:chat).and_return(
      DSPy::LM::Response.new(content: "```toon\n#{iteration_payload}\n```", usage: usage, metadata: {})
    )

    agent = DSPy::ReAct.new(ToonReActSignature, tools: [], max_iterations: 1)
    result = agent.forward(question: 'test')

    expect(result.answer).to eq('answer')
  end

  def decode_toon_input(messages, signature)
    user_message = messages.last
    content = user_message[:content]
    match = content.match(/```toon\s*(.*?)```/m)
    raise 'TOON block missing in user message' unless match

    Sorbet::Toon.decode(match[1].strip, signature: signature, role: :input)
  end

  def thought_signature?(signature)
    signature.output_struct_class.props.key?(:action)
  end

  def fetch_field(container, key)
    return nil if container.nil?

    if container.respond_to?(key)
      return container.public_send(key)
    end

    candidates = [key, key.to_s, key.to_sym].compact.uniq

    if container.respond_to?(:key?)
      candidates.each do |candidate|
        return container[candidate] if container.key?(candidate)
      end
    elsif container.respond_to?(:[])
      candidates.each do |candidate|
        begin
          value = container[candidate]
          return value unless value.nil?
        rescue StandardError
          next
        end
      end
    end

    if container.respond_to?(:to_h)
      hash = container.to_h
      return fetch_field(hash, key) unless hash.equal?(container)
    end

    nil
  end

  it 'serializes inputs, history, and tools into TOON prompts for ReAct' do
    tool = ToonLookupTool.new
    agent = DSPy::ReAct.new(ToonReActSignature, tools: [tool], max_iterations: 3)
    action_enum = agent.instance_variable_get(:@action_enum_class)
    finish_action = action_enum.const_get('FINISH')
    lookup_action = action_enum.const_get('LOOKUP_CITY')

    captured_inputs = []
    thought_call_index = 0

    allow(mock_adapter).to receive(:chat) do |messages:, signature:, **|
      decoded_input = decode_toon_input(messages, signature)
      captured_inputs << { signature: signature, decoded: decoded_input }

      payload = if thought_signature?(signature)
        thought_call_index += 1
        if thought_call_index == 1
          {
            thought: 'Need structured city data',
            action: lookup_action,
            action_input: { city: 'Paris' }
          }
        else
          {
            thought: 'Provide final answer',
            action: finish_action,
            action_input: 'Paris population is 2,148,000'
          }
        end
      else
        {
          interpretation: 'Observation captured',
          next_step: DSPy::NextStep::Finish
        }
      end

      encoded = Sorbet::Toon.encode(payload, signature: signature, role: :output)
      DSPy::LM::Response.new(content: "```toon\n#{encoded}\n```", usage: usage, metadata: {})
    end

    result = agent.forward(question: 'What is the population of Paris?')

    expect(result.answer).to eq('Paris population is 2,148,000')

    thought_inputs = captured_inputs.select { |entry| thought_signature?(entry[:signature]) }
    first_input = thought_inputs.first[:decoded]
    input_context = fetch_field(first_input, :input_context)
    expect(fetch_field(input_context, :question)).to eq('What is the population of Paris?')
    history_entries = fetch_field(first_input, :history) || []
    expect(history_entries).to be_empty
    available_tools = fetch_field(first_input, :available_tools) || []
    tool_schema_str = fetch_field(available_tools.first, :schema)
    # schema is now a JSON string, parse it to access fields
    tool_schema = JSON.parse(tool_schema_str, symbolize_names: true)
    expect(tool_schema[:name]).to eq('lookup_city')
    parameters = tool_schema[:parameters] || {}
    properties = parameters[:properties] || {}
    property_keys = properties.keys.map(&:to_s)
    expect(property_keys).to include('city')

    observation_input = captured_inputs.find { |entry| !thought_signature?(entry[:signature]) }[:decoded]
    observation_history = fetch_field(observation_input, :history) || []
    expect(observation_history.length).to eq(1)
    history_entry = observation_history.first
    action_input = fetch_field(history_entry, :action_input)
    city_arg = fetch_field(action_input, :city)
    expect(city_arg).to eq('Paris')

    history_observation = fetch_field(history_entry, :observation)
    history_city = fetch_field(history_observation, :city)
    expect(history_city).to eq('Paris')

    observation = fetch_field(observation_input, :observation)
    observation_city = fetch_field(observation, :city)
    observation_population = fetch_field(observation, :population)
    expect(observation_city).to eq('Paris')
    expect(observation_population).to eq(2_148_000)
  end
end
