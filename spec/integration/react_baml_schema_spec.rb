# frozen_string_literal: true

require 'spec_helper'
require 'sorbet_baml'

RSpec.describe 'ReAct BAML Schema Issues', type: :integration do
  # Test fixtures for reproducing BAML schema issues
  module TestFixtures
    class SimpleDataTool < DSPy::Tools::Base
      extend T::Sig

      tool_name 'load_data'
      tool_description 'Loads some dummy data'

      sig { params(data_type: String).returns(String) }
      def call(data_type:)
        "Loaded data for: #{data_type}"
      end
    end

    class DataAnalyst < DSPy::Signature
      description 'You are a helpful assistant, use the tools provided to answer the query'

      input do
        const :query, String, desc: 'The user query'
        const :structured_state, String, desc: 'The structured state'
      end

      output do
        const :answer, String, desc: 'The final natural language answer for the user'
      end
    end
  end

  describe 'Issue 1: Anonymous enum class in BAML schema' do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4.1',
          api_key: ENV.fetch('OPENAI_API_KEY', 'test-key'),
          schema_format: :baml
        )
      end
    end

    let(:tool) { TestFixtures::SimpleDataTool.new }
    let(:agent) { DSPy::ReAct.new(TestFixtures::DataAnalyst, tools: [tool], max_iterations: 5) }

    it 'renders ActionEnum with a proper class name instead of anonymous class' do
      system_prompt = agent.prompt.render_system_prompt

      # Should NOT have anonymous class pattern like #<Class:0x000000014cfb5200>
      expect(system_prompt).not_to match(/enum #<Class:0x[0-9a-f]+>/)

      # Should have a proper enum name
      expect(system_prompt).to match(/enum ActionEnum/)
    end

    it 'includes action values in the BAML enum' do
      system_prompt = agent.prompt.render_system_prompt

      # Should include the tool name and finish action
      expect(system_prompt).to include('"load_data"')
      expect(system_prompt).to include('"finish"')
    end
  end

  describe 'Issue 2: Properly typed tool_input and final_answer fields' do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4.1',
          api_key: ENV.fetch('OPENAI_API_KEY', 'test-key'),
          schema_format: :baml
        )
      end
    end

    let(:tool) { TestFixtures::SimpleDataTool.new }
    let(:agent) { DSPy::ReAct.new(TestFixtures::DataAnalyst, tools: [tool], max_iterations: 5) }

    it 'has separate tool_input and final_answer fields instead of action_input' do
      system_prompt = agent.prompt.render_system_prompt

      # Should have separate fields
      expect(system_prompt).to include('tool_input')
      expect(system_prompt).to include('final_answer')

      # Should NOT have the old action_input field
      expect(system_prompt).not_to include('action_input')
    end

    it 'types tool_input as a JSON object (hash)' do
      system_prompt = agent.prompt.render_system_prompt

      # Should have tool_input with a hash/json type indicator
      # In BAML this would be something like json? or map<string, any>?
      expect(system_prompt).to match(/tool_input\s+(json\?|map)/)
    end

    it 'types final_answer to match the signature output type' do
      system_prompt = agent.prompt.render_system_prompt

      # The output type is String, so final_answer should be string?
      expect(system_prompt).to match(/final_answer\s+string\?/)
    end
  end

  describe 'HistoryEntry struct updates' do
    it 'has tool_input field instead of action_input' do
      # Check HistoryEntry props
      props = DSPy::HistoryEntry.props

      expect(props.keys).to include(:tool_input)
      expect(props.keys).not_to include(:action_input)
    end
  end

  describe 'End-to-end ReAct execution with BAML', vcr: { cassette_name: 'react_baml_schema/e2e_execution' } do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4.1',
          api_key: ENV.fetch('OPENAI_API_KEY', nil),
          schema_format: :baml
        )
      end
    end

    let(:tool) { TestFixtures::SimpleDataTool.new }
    let(:agent) { DSPy::ReAct.new(TestFixtures::DataAnalyst, tools: [tool], max_iterations: 5) }

    it 'executes successfully with BAML schema format' do
      result = agent.call(
        query: 'What data do we have?',
        structured_state: 'No prior context'
      )

      expect(result.answer).to be_a(String)
      expect(result.answer).not_to be_empty
    end
  end
end
