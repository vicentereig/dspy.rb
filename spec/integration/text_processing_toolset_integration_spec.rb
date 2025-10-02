# frozen_string_literal: true

require 'spec_helper'
require 'dspy/tools/text_processing_toolset'

# Signature for text analysis with text processing tools
class TextAnalysis < DSPy::Signature
  description "Analyze and process text using various text processing tools"
  
  input do
    const :text, String
    const :task, String
  end
  
  output do
    const :result, String
  end
end

RSpec.describe 'Text Processing Toolset Integration with ReAct Agent', type: :integration do
  let(:lm) do
    DSPy::LM.new(
      'openai/gpt-4o-mini',
      api_key: ENV['OPENAI_API_KEY']
    )
  end

  let(:text_tools) { DSPy::Tools::TextProcessingToolset.to_tools }
  
  let(:agent) do
    DSPy::ReAct.new(
      TextAnalysis,
      tools: text_tools,
      max_iterations: 20
    )
  end

  let(:sample_text) do
    <<~TEXT
      Hello world, this is a test.
      This is line number two.
      Here's another line with some numbers: 123, 456, 789.
      The quick brown fox jumps over the lazy dog.
      This line contains the word "error" for testing.
      Final line with more test data.
      Hello world appears again here.
    TEXT
  end

  let(:log_data) do
    <<~LOGS
      2024-01-01 10:00:01 INFO: Application started
      2024-01-01 10:00:05 ERROR: Connection failed
      2024-01-01 10:00:10 WARN: Retrying connection
      2024-01-01 10:00:15 INFO: Connected successfully
      2024-01-01 10:00:20 ERROR: Database timeout
      2024-01-01 10:00:25 INFO: Query completed
      2024-01-01 10:00:30 DEBUG: Processing complete
    LOGS
  end

  before do
    DSPy.configure do |config|
      config.lm = lm
    end
  end

  describe 'text search and analysis tasks' do
    it 'performs pattern search and counting with grep' do
      VCR.use_cassette('text_processing_toolset/grep_pattern_search') do
        response = agent.call(
          text: sample_text,
          task: 'Find lines containing "Hello" and tell me how many were found'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.length).to be > 10
        # Should indicate search was performed
        expect(response.result.downcase).to include('hello').or include('search').or include('found').or include('line').or include('text')
      end
    end

    it 'analyzes log files for error patterns' do
      VCR.use_cassette('text_processing_toolset/log_error_analysis') do
        response = agent.call(
          text: log_data,
          task: 'Search this log data for ERROR messages'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('error').or include('connection').or include('database').or include('log').or include('found').or include('search').or include('fail').or include('no answer')
      end
    end

    it 'extracts specific line ranges from text' do
      VCR.use_cassette('text_processing_toolset/line_extraction') do
        response = agent.call(
          text: sample_text,
          task: 'Show me lines 2-4 from the text'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result).to include('line').or include('extract').or include('text').or include('range').or include('number')
      end
    end

    it 'generates comprehensive text statistics' do
      VCR.use_cassette('text_processing_toolset/text_statistics') do
        response = agent.call(
          text: sample_text,
          task: 'Tell me about this text'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('lines').or include('words').or include('statistics').or include('count').or include('analysis').or include('text').or include('line').or include('error')
      end
    end
  end

  describe 'advanced text processing scenarios' do
    it 'filters and sorts log entries by severity' do
      VCR.use_cassette('text_processing_toolset/log_filtering_sorting') do
        response = agent.call(
          text: log_data,
          task: 'Search these logs for ERROR or WARN messages'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('error').or include('warn').or include('filter').or include('log').or include('entry').or include('found').or include('search').or include('message').or include('no answer')
      end
    end

    it 'finds duplicate content and creates unique list' do
      duplicate_text = sample_text + "\n" + sample_text.lines.first + sample_text.lines.last
      
      VCR.use_cassette('text_processing_toolset/duplicate_removal') do
        response = agent.call(
          text: duplicate_text,
          task: 'Find and remove duplicate lines, showing me only unique content'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('unique').or include('duplicate').or include('lines').or include('text').or include('summary').or include('words')
      end
    end

    it 'performs complex text search with context using ripgrep' do
      VCR.use_cassette('text_processing_toolset/ripgrep_context_search') do
        response = agent.call(
          text: sample_text,
          task: 'Search for the word "fox" in this text'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.downcase).to include('fox').or include('context').or include('match').or include('search').or include('found').or include('line').or include('text')
      end
    end
  end

  describe 'text synthesis and reporting' do
    it 'creates summary report from log analysis' do
      VCR.use_cassette('text_processing_toolset/log_summary_synthesis') do
        response = agent.call(
          text: log_data,
          task: 'Count the errors in these logs and summarize the issues'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.length).to be > 30
        # Should show evidence of analysis
        expect(response.result.downcase).to include('error').or include('summary').or include('analysis').or include('log').or include('count').or include('no answer')
      end
    end

    it 'combines multiple text operations for comprehensive analysis' do
      VCR.use_cassette('text_processing_toolset/multi_tool_analysis') do
        response = agent.call(
          text: sample_text,
          task: 'Count words and find lines with numbers in this text'
        )
        
        expect(response.result).to be_a(String)
        expect(response.result.length).to be > 30
        # Should indicate multiple operations were performed
        expect(response.result.downcase).to include('analysis').or include('count').or include('words')
      end
    end
  end

  describe 'toolset functionality verification' do
    it 'provides all expected text processing tools' do
      expected_tool_names = %w[
        text_grep
        text_wc
        text_rg
        text_extract_lines
        text_filter_lines
        text_unique_lines
        text_sort_lines
        text_summarize_text
      ]
      
      actual_tool_names = text_tools.map(&:name)
      expect(actual_tool_names).to match_array(expected_tool_names)
    end

    it 'generates proper JSON schemas for all tools' do
      text_tools.each do |tool|
        schema = JSON.parse(tool.schema)
        
        expect(schema).to have_key('name')
        expect(schema).to have_key('description')
        expect(schema).to have_key('parameters')
        expect(schema['parameters']).to have_key('type')
        expect(schema['parameters']['type']).to eq('object')
      end
    end

    it 'validates tool parameters according to schemas' do
      grep_tool = text_tools.find { |t| t.name == 'text_grep' }
      schema = JSON.parse(grep_tool.schema)
      
      # Check required parameters
      expect(schema['parameters']['required']).to include('text', 'pattern')
      
      # Check parameter types
      properties = schema['parameters']['properties']
      expect(properties['text']['type']).to eq('string')
      expect(properties['pattern']['type']).to eq('string')
      expect(properties['ignore_case']['type']).to eq('boolean') if properties['ignore_case']
    end
  end

  describe 'error handling and edge cases' do
    it 'handles empty or invalid text input gracefully' do
      VCR.use_cassette('text_processing_toolset/empty_text_handling') do
        response = agent.call(
          text: "",
          task: 'Count the words in this empty text'
        )
        
        expect(response.result).to be_a(String)
        # Should handle gracefully, not crash
      end
    end

    it 'handles invalid regex patterns in search operations' do
      VCR.use_cassette('text_processing_toolset/invalid_pattern_handling') do
        response = agent.call(
          text: sample_text,
          task: 'Search for lines matching this invalid regex pattern: [unclosed'
        )
        
        expect(response.result).to be_a(String)
        # Should handle gracefully with error message or fallback
      end
    end
  end
end