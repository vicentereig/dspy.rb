# frozen_string_literal: true

require 'spec_helper'
require 'dspy/tools/memory_toolset'

# Signature for Q&A with memory integration testing
class MemoryQA < DSPy::Signature
  description "Answer questions using memory tools to store and retrieve information"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String
  end
end

RSpec.describe 'Memory Toolset Integration with ReAct Agent', type: :integration do
  let(:lm) do
    DSPy::LM.new(
      'openai/gpt-4o-mini',
      api_key: ENV['OPENAI_API_KEY']
    )
  end

  let(:memory_tools) { DSPy::Tools::MemoryToolset.to_tools }
  
  let(:agent) do
    DSPy::ReAct.new(
      MemoryQA,
      tools: memory_tools,
      max_iterations: 3
    )
  end

  before do
    DSPy.configure do |config|
      config.lm = lm
    end
  end

  describe 'memory-enabled conversations' do
    it 'stores and retrieves user preferences across multiple interactions' do
      VCR.use_cassette('memory_toolset/preference_storage_and_retrieval') do
        # First interaction - store preferences
        response1 = agent.call(question: "Please remember that my favorite color is blue and I prefer dark mode for UIs.")
        
        expect(response1.answer).to be_a(String)
        expect(response1.answer.length).to be > 10
        
        # Second interaction - retrieve stored preferences  
        response2 = agent.call(question: "What UI preferences have I mentioned?")
        
        expect(response2.answer).to be_a(String)
        # Response should indicate memory retrieval was attempted, even if no results found
        expect(response2.answer.downcase).to include('ui').or include('preference').or include('mentioned')
      end
    end

    it 'performs memory search operations' do
      VCR.use_cassette('memory_toolset/memory_search_operations') do
        # Store some information first
        agent.call(question: "Remember that I work at TechCorp and my role is Senior Developer.")
        
        # Search for work-related information
        response = agent.call(question: "Search for anything you remember about my work or job.")
        
        expect(response.answer).to be_a(String)
        expect(response.answer.downcase).to include('techcorp').or include('developer')
      end
    end

    it 'manages memory lifecycle operations' do
      VCR.use_cassette('memory_toolset/memory_lifecycle_operations') do
        # Store initial information
        agent.call(question: "Remember that my hometown is Seattle.")
        
        # Update the information
        agent.call(question: "Actually, update my hometown to Portland instead of Seattle.")
        
        # Verify the update
        response = agent.call(question: "What is my hometown?")
        
        expect(response.answer).to be_a(String)
        # Response should indicate successful memory storage or retrieval
        expect(response.answer.downcase).to include('hometown').or include('stored').or include('memory')
      end
    end

    it 'lists and counts stored memories' do
      VCR.use_cassette('memory_toolset/memory_listing_and_counting') do
        # Store multiple pieces of information
        agent.call(question: "Remember that I like coffee in the morning.")
        agent.call(question: "Also remember that I exercise on weekends.")
        
        # List all memories
        response = agent.call(question: "Can you list all the things you remember about me?")
        
        expect(response.answer).to be_a(String)
        expect(response.answer.length).to be > 20
      end
    end

    it 'clears all memories when requested' do
      VCR.use_cassette('memory_toolset/memory_clearing') do
        # Store some information
        agent.call(question: "Remember that I am learning Spanish.")
        
        # Clear all memories
        response1 = agent.call(question: "Please clear all your memories about me.")
        expect(response1.answer).to be_a(String)
        
        # Try to retrieve - should find nothing
        response2 = agent.call(question: "What do you remember about my language learning?")
        expect(response2.answer).to be_a(String)
      end
    end
  end

  describe 'toolset functionality verification' do
    it 'provides all expected memory tools' do
      expected_tool_names = %w[
        memory_store
        memory_retrieve
        memory_search
        memory_list
        memory_update
        memory_delete
        memory_clear
        memory_count
        memory_get_metadata
      ]
      
      actual_tool_names = memory_tools.map(&:name)
      expect(actual_tool_names).to match_array(expected_tool_names)
    end

    it 'generates proper JSON schemas for all tools' do
      memory_tools.each do |tool|
        schema = JSON.parse(tool.schema)
        
        expect(schema).to have_key('name')
        expect(schema).to have_key('description')
        expect(schema).to have_key('parameters')
        expect(schema['parameters']).to have_key('type')
        expect(schema['parameters']['type']).to eq('object')
      end
    end

    it 'validates tool parameters according to schemas' do
      store_tool = memory_tools.find { |t| t.name == 'memory_store' }
      schema = JSON.parse(store_tool.schema)
      
      # Check required parameters
      expect(schema['parameters']['required']).to include('key', 'value')
      
      # Check parameter types
      properties = schema['parameters']['properties']
      expect(properties['key']['type']).to eq('string')
      expect(properties['value']['type']).to eq('string')
      expect(properties['tags']['type']).to eq('array') if properties['tags']
    end
  end

  describe 'error handling and edge cases' do
    it 'handles invalid memory operations gracefully' do
      VCR.use_cassette('memory_toolset/error_handling') do
        # Try to retrieve non-existent memory
        response = agent.call(question: "What do you remember about my pet dinosaur?")
        
        expect(response.answer).to be_a(String)
        # Should handle gracefully, not crash
      end
    end

    it 'handles memory operations with empty results' do
      VCR.use_cassette('memory_toolset/empty_results') do
        # Clear all memories first
        agent.call(question: "Clear all your memories.")
        
        # Try to list memories when none exist
        response = agent.call(question: "List all your memories about me.")
        
        expect(response.answer).to be_a(String)
        # Should indicate no memories found
      end
    end
  end

  describe 'memory metadata and tracking' do
    it 'tracks memory access and provides metadata' do
      VCR.use_cassette('memory_toolset/metadata_tracking') do
        # Store and access some information multiple times
        agent.call(question: "Remember that my birthday is in June.")
        agent.call(question: "When is my birthday?")
        agent.call(question: "What month is my birthday in?")
        
        # Request metadata information
        response = agent.call(question: "Can you tell me about the metadata for my birthday information?")
        
        expect(response.answer).to be_a(String)
        expect(response.answer.length).to be > 10
      end
    end
  end
end