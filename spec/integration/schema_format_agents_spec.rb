# frozen_string_literal: true

require 'spec_helper'
require 'sorbet_baml'
require 'sorbet/toon'
require 'dspy/code_act'

# Shared test fixtures for schema format integration tests
module SchemaFormatAgentSpecs
  # Simple calculator tool for testing agents
  class CalculatorTool < DSPy::Tools::Base
    extend T::Sig

    tool_name 'calculate'
    tool_description 'Perform a mathematical calculation and return the numeric result'

    sig { params(expression: String).returns(Integer) }
    def call(expression:)
      # Simple safe evaluation of basic math expressions
      result = case expression
               when /(\d+)\s*\+\s*(\d+)/ then $1.to_i + $2.to_i
               when /(\d+)\s*\*\s*(\d+)/ then $1.to_i * $2.to_i
               when /(\d+)\s*-\s*(\d+)/ then $1.to_i - $2.to_i
               when /sum.*1.*to.*(\d+)/i then (1..$1.to_i).sum
               else 42
               end
      result
    end
  end

  # Math assistant signature for ReAct
  class MathAssistant < DSPy::Signature
    description "Solve mathematical problems step by step"

    input do
      const :problem, String
    end

    output do
      const :answer, String
    end
  end

  # Code generation signature for CodeAct
  class CodeSolver < DSPy::Signature
    description "Solve problems by writing and executing Ruby code"

    input do
      const :task, String
    end

    output do
      const :result, String
    end
  end
end

RSpec.describe 'Schema Format Integration with Agents', type: :integration do
  describe 'ReAct with BAML schema format' do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4o-mini',
          api_key: ENV['OPENAI_API_KEY'],
          structured_outputs: false,
          schema_format: :baml
        )
      end
    end

    let(:tools) { [SchemaFormatAgentSpecs::CalculatorTool.new] }
    let(:agent) { DSPy::ReAct.new(SchemaFormatAgentSpecs::MathAssistant, tools: tools, max_iterations: 3) }

    it 'uses BAML schema format in prompts' do
      system_prompt = agent.prompt.render_system_prompt

      # Verify BAML format is used
      expect(system_prompt).to include('```baml')
      expect(system_prompt).not_to include('"properties"') # JSON schema indicator
    end

    it 'generates proper BAML schema for ReAct history and tools' do
      system_prompt = agent.prompt.render_system_prompt

      # Should have HistoryEntry class definition
      expect(system_prompt).to include('class HistoryEntry')
      expect(system_prompt).to match(/step\s+int/)
      expect(system_prompt).to match(/thought\s+string\?/)

      # Should have AvailableTool class definition
      expect(system_prompt).to include('class AvailableTool')
      expect(system_prompt).to match(/name\s+string/)
      expect(system_prompt).to match(/description\s+string/)
      expect(system_prompt).to match(/schema\s+string/) # Now typed as String!
    end

    it 'includes action enum with tool names in BAML format' do
      system_prompt = agent.prompt.render_system_prompt

      # Should have enum for actions
      expect(system_prompt).to include('enum')
      expect(system_prompt).to include('"calculate"')
      expect(system_prompt).to include('"finish"')
    end
  end

  describe 'ReAct with TOON schema format' do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4o-mini',
          api_key: ENV['OPENAI_API_KEY'],
          structured_outputs: false,
          schema_format: :toon,
          data_format: :toon
        )
      end
    end

    let(:tools) { [SchemaFormatAgentSpecs::CalculatorTool.new] }
    let(:agent) { DSPy::ReAct.new(SchemaFormatAgentSpecs::MathAssistant, tools: tools, max_iterations: 3) }

    it 'uses TOON schema format in prompts' do
      system_prompt = agent.prompt.render_system_prompt

      # Verify TOON format is used
      expect(system_prompt).to include('TOON')
      expect(system_prompt).not_to include('"$schema"')
      expect(system_prompt).not_to include('"properties"')
    end

    it 'describes input fields in TOON format' do
      system_prompt = agent.prompt.render_system_prompt

      # Should describe input_context, history, available_tools
      expect(system_prompt).to include('input_context')
      expect(system_prompt).to include('history')
      expect(system_prompt).to include('available_tools')
    end

    it 'describes output fields with action enum in TOON format' do
      system_prompt = agent.prompt.render_system_prompt

      # Should describe thought, action, tool_input, final_answer
      expect(system_prompt).to include('thought')
      expect(system_prompt).to include('action')
      expect(system_prompt).to include('tool_input')
      expect(system_prompt).to include('final_answer')

      # Should list valid action values
      expect(system_prompt).to include('calculate')
      expect(system_prompt).to include('finish')
    end
  end

  describe 'CodeAct with BAML schema format' do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4o-mini',
          api_key: ENV['OPENAI_API_KEY'],
          structured_outputs: false,
          schema_format: :baml
        )
      end
    end

    let(:agent) { DSPy::CodeAct.new(SchemaFormatAgentSpecs::CodeSolver, max_iterations: 3) }

    it 'uses BAML schema format for code generation prompts' do
      code_generator = agent.instance_variable_get(:@code_generator)
      system_prompt = code_generator.prompt.render_system_prompt

      # Verify BAML format is used
      expect(system_prompt).to include('```baml')
    end

    it 'includes CodeActHistoryEntry in BAML schema' do
      code_generator = agent.instance_variable_get(:@code_generator)
      system_prompt = code_generator.prompt.render_system_prompt

      # Should have CodeActHistoryEntry class definition
      expect(system_prompt).to include('class CodeActHistoryEntry')
      expect(system_prompt).to match(/step\s+int/)
      expect(system_prompt).to match(/thought\s+string\?/)
      expect(system_prompt).to match(/ruby_code\s+string\?/)
      expect(system_prompt).to match(/execution_result\s+string\?/)
      expect(system_prompt).to match(/error_message\s+string/)
    end

    it 'generates and executes Ruby code', vcr: { cassette_name: 'schema_format/codeact_baml_execution' } do
      result = agent.call(task: "Calculate the sum of even numbers from 2 to 10")

      expect(result.result).to be_a(String)
      expect(result.result).not_to be_empty
      expect(result.iterations).to be >= 1
      expect(result.history).to be_an(Array)
      expect(result.history).not_to be_empty
    end

    it 'tracks execution history with CodeActHistoryEntry structs', vcr: { cassette_name: 'schema_format/codeact_baml_history' } do
      result = agent.call(task: "Calculate 5 factorial (5!)")

      result.history.each do |entry|
        expect(entry).to be_a(DSPy::CodeActHistoryEntry)
        expect(entry.step).to be_an(Integer)
        expect(entry.thought).to be_a(String).or be_nil
        expect(entry.ruby_code).to be_a(String).or be_nil
      end
    end
  end

  describe 'CodeAct with TOON schema format' do
    before do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4o-mini',
          api_key: ENV['OPENAI_API_KEY'],
          structured_outputs: false,
          schema_format: :toon,
          data_format: :toon
        )
      end
    end

    let(:agent) { DSPy::CodeAct.new(SchemaFormatAgentSpecs::CodeSolver, max_iterations: 3) }

    it 'uses TOON schema format for code generation prompts' do
      code_generator = agent.instance_variable_get(:@code_generator)
      system_prompt = code_generator.prompt.render_system_prompt

      # Verify TOON format is used
      expect(system_prompt).to include('TOON')
      expect(system_prompt).not_to include('"$schema"')
    end

    it 'describes CodeAct fields in TOON format' do
      code_generator = agent.instance_variable_get(:@code_generator)
      system_prompt = code_generator.prompt.render_system_prompt

      # Input fields
      expect(system_prompt).to include('task')
      expect(system_prompt).to include('context')
      expect(system_prompt).to include('history')

      # Output fields
      expect(system_prompt).to include('thought')
      expect(system_prompt).to include('ruby_code')
      expect(system_prompt).to include('explanation')
    end

    it 'generates and executes Ruby code', vcr: { cassette_name: 'schema_format/codeact_toon_execution' } do
      result = agent.call(task: "Calculate the product of 6 and 9")

      expect(result.result).to be_a(String)
      expect(result.result).not_to be_empty
      expect(result.iterations).to be >= 1
    end

    it 'preserves CodeActHistoryEntry types', vcr: { cassette_name: 'schema_format/codeact_toon_history' } do
      result = agent.call(task: "Find the square of 12")

      expect(result.history).to be_an(Array)
      result.history.each do |entry|
        expect(entry).to be_a(DSPy::CodeActHistoryEntry)
      end
    end
  end

  describe 'Schema format comparison for agent prompts' do
    let(:tools) { [SchemaFormatAgentSpecs::CalculatorTool.new] }

    it 'BAML produces more compact ReAct prompts than JSON' do
      # Create ReAct with JSON format
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :json)
      end
      json_agent = DSPy::ReAct.new(SchemaFormatAgentSpecs::MathAssistant, tools: tools)
      json_prompt = json_agent.prompt.render_system_prompt

      # Create ReAct with BAML format
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :baml)
      end
      baml_agent = DSPy::ReAct.new(SchemaFormatAgentSpecs::MathAssistant, tools: tools)
      baml_prompt = baml_agent.prompt.render_system_prompt

      # BAML should be more compact
      puts "\n=== ReAct Prompt Size Comparison ==="
      puts "JSON format: #{json_prompt.length} chars"
      puts "BAML format: #{baml_prompt.length} chars"
      puts "Savings: #{((1 - baml_prompt.length.to_f / json_prompt.length) * 100).round(1)}%"

      expect(baml_prompt.length).to be < json_prompt.length
    end

    it 'BAML produces more compact CodeAct prompts than JSON' do
      # Create CodeAct with JSON format
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :json)
      end
      json_agent = DSPy::CodeAct.new(SchemaFormatAgentSpecs::CodeSolver)
      json_generator = json_agent.instance_variable_get(:@code_generator)
      json_prompt = json_generator.prompt.render_system_prompt

      # Create CodeAct with BAML format
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :baml)
      end
      baml_agent = DSPy::CodeAct.new(SchemaFormatAgentSpecs::CodeSolver)
      baml_generator = baml_agent.instance_variable_get(:@code_generator)
      baml_prompt = baml_generator.prompt.render_system_prompt

      puts "\n=== CodeAct Prompt Size Comparison ==="
      puts "JSON format: #{json_prompt.length} chars"
      puts "BAML format: #{baml_prompt.length} chars"
      puts "Savings: #{((1 - baml_prompt.length.to_f / json_prompt.length) * 100).round(1)}%"

      expect(baml_prompt.length).to be < json_prompt.length
    end
  end

  describe 'AvailableTool schema type change verification' do
    # This test verifies the fix from PR #194 - AvailableTool.schema is now String
    # instead of T::Hash[Symbol, T.untyped] which caused BAML encoding errors

    let(:tools) { [SchemaFormatAgentSpecs::CalculatorTool.new] }

    it 'AvailableTool.schema is typed as String for BAML compatibility' do
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :baml)
      end

      # Create AvailableTool and verify schema is a String
      tool = DSPy::ReAct::AvailableTool.new(
        name: 'test_tool',
        description: 'A test tool',
        schema: '{"type":"object","properties":{}}'
      )

      expect(tool.schema).to be_a(String)

      # The BAML schema should now show schema as string type
      agent = DSPy::ReAct.new(SchemaFormatAgentSpecs::MathAssistant, tools: tools)
      system_prompt = agent.prompt.render_system_prompt

      expect(system_prompt).to include('class AvailableTool')
      expect(system_prompt).to match(/schema\s+string/)
    end
  end

  describe 'CodeActHistoryEntry type verification' do
    # This test verifies the fix from PR #194 - CodeAct history uses
    # CodeActHistoryEntry structs instead of T::Hash[Symbol, T.untyped]

    it 'CodeAct history field is typed as T::Array[CodeActHistoryEntry]' do
      DSPy.configure do |c|
        c.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: 'test', schema_format: :baml)
      end

      agent = DSPy::CodeAct.new(SchemaFormatAgentSpecs::CodeSolver)
      code_generator = agent.instance_variable_get(:@code_generator)
      system_prompt = code_generator.prompt.render_system_prompt

      # The BAML schema should reference CodeActHistoryEntry, not generic hash
      expect(system_prompt).to include('CodeActHistoryEntry')
      expect(system_prompt).to include('class CodeActHistoryEntry')
    end
  end
end
