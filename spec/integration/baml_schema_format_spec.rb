# frozen_string_literal: true

require 'spec_helper'
require 'sorbet_baml'

# Define ComplexityLevel enum for task orchestration
class ComplexityLevel < T::Enum
  enums do
    Basic = new('basic')
    Intermediate = new('intermediate')
    Advanced = new('advanced')
  end
end

# Complex signature for autonomous task decomposition
class TaskDecomposition < DSPy::Signature
  description "Autonomously analyze a research topic and define optimal subtasks with strategic prioritization"

  input do
    const :topic, String, description: "The main research topic to investigate"
    const :context, String, description: "Any additional context or constraints"
    const :complexity_level, ComplexityLevel, description: "Desired complexity level for task decomposition"
  end

  output do
    const :subtasks, T::Array[String], description: "Autonomously defined research subtasks with clear objectives"
    const :task_types, T::Array[String], description: "Type classification for each task (analysis, synthesis, investigation, etc.)"
    const :priority_order, T::Array[Integer], description: "Strategic priority rankings (1-5 scale) for each subtask"
    const :estimated_effort, T::Array[Integer], description: "Effort estimates in hours for each subtask"
    const :dependencies, T::Array[String], description: "Task dependency relationships for optimal sequencing"
    const :agent_requirements, T::Array[String], description: "Suggested agent types/skills needed for each task (for future agent mapping)"
  end
end

# Complex signature for research execution with contextual awareness
class ResearchExecution < DSPy::Signature
  description "Execute individual research subtasks with contextual awareness and strategic insight generation"

  input do
    const :subtask, String, description: "The specific research subtask to execute"
    const :context, String, description: "Accumulated context from previous research steps"
    const :constraints, String, description: "Any specific constraints or focus areas for this research"
  end

  output do
    const :findings, String, description: "Detailed research findings and analysis"
    const :key_insights, T::Array[String], description: "Key actionable insights extracted from the research"
    const :confidence_level, Integer, description: "Confidence in findings quality (1-10 scale)"
    const :evidence_quality, String, description: "Assessment of evidence quality and reliability"
    const :next_steps, T::Array[String], description: "Recommended next steps based on these findings"
    const :knowledge_gaps, T::Array[String], description: "Identified gaps in knowledge or areas needing further research"
  end
end

RSpec.describe 'BAML Schema Format Integration', type: :integration do
  let(:lm) do
    DSPy::LM.new(
      'openai/gpt-4o-mini',
      api_key: ENV['OPENAI_API_KEY'],
      structured_outputs: false  # Use enhanced prompting mode
    )
  end

  before do
    DSPy.configure do |c|
      c.lm = lm
    end
  end

  describe 'schema format comparison' do
    it 'generates JSON schema format for complex signatures' do
      predictor = DSPy::Predict.new(TaskDecomposition)
      prompt = predictor.instance_variable_get(:@prompt)

      json_system_prompt = prompt.render_system_prompt

      # Verify JSON schema is embedded
      expect(json_system_prompt).to include('```json')
      expect(json_system_prompt).to include('"properties"')
      expect(json_system_prompt).to include('"type"')
      expect(json_system_prompt).to include('"description"')

      # Verify field descriptions are present
      expect(json_system_prompt).to include('The main research topic to investigate')
      expect(json_system_prompt).to include('Autonomously defined research subtasks')
    end

    it 'BAML schema is more compact than JSON schema for TaskDecomposition' do
      # Get JSON schema
      json_schema = TaskDecomposition.output_json_schema
      json_string = JSON.pretty_generate(json_schema)

      # Generate BAML schema using sorbet-baml
      baml_schema = TaskDecomposition.output_struct_class.to_baml

      # BAML should be significantly shorter
      expect(baml_schema.length).to be < (json_string.length * 0.6)

      puts "\n=== Schema Comparison for TaskDecomposition ==="
      puts "JSON Schema length: #{json_string.length} chars"
      puts "BAML Schema length: #{baml_schema.length} chars"
      puts "Token savings: #{((1 - baml_schema.length.to_f / json_string.length) * 100).round(1)}%"
      puts "\nBAML Schema:\n#{baml_schema}"
    end

    it 'BAML schema is more compact than JSON schema for ResearchExecution' do
      # Get JSON schema
      json_schema = ResearchExecution.output_json_schema
      json_string = JSON.pretty_generate(json_schema)

      # Generate BAML schema using sorbet-baml
      baml_schema = ResearchExecution.output_struct_class.to_baml

      # BAML should be significantly shorter
      expect(baml_schema.length).to be < (json_string.length * 0.6)

      puts "\n=== Schema Comparison for ResearchExecution ==="
      puts "JSON Schema length: #{json_string.length} chars"
      puts "BAML Schema length: #{baml_schema.length} chars"
      puts "Token savings: #{((1 - baml_schema.length.to_f / json_string.length) * 100).round(1)}%"
      puts "\nBAML Schema:\n#{baml_schema}"
    end
  end

  describe 'BAML schema generation for complex types' do
    it 'generates valid BAML syntax for TaskDecomposition' do
      baml_schema = TaskDecomposition.output_struct_class.to_baml

      # Verify BAML syntax
      expect(baml_schema).to include('class')
      expect(baml_schema).to match(/subtasks\s+string\[\]/)
      expect(baml_schema).to match(/task_types\s+string\[\]/)
      expect(baml_schema).to match(/priority_order\s+int\[\]/)
      expect(baml_schema).to match(/estimated_effort\s+int\[\]/)
      expect(baml_schema).to match(/dependencies\s+string\[\]/)
      expect(baml_schema).to match(/agent_requirements\s+string\[\]/)

      # Note: Descriptions require integration with DSPy::Signature's FieldDescriptor
      # This will be implemented in the full BAML integration
    end

    it 'generates valid BAML syntax for ResearchExecution' do
      baml_schema = ResearchExecution.output_struct_class.to_baml

      # Verify BAML syntax
      expect(baml_schema).to include('class')
      expect(baml_schema).to match(/findings\s+string/)
      expect(baml_schema).to match(/key_insights\s+string\[\]/)
      expect(baml_schema).to match(/confidence_level\s+int/)
      expect(baml_schema).to match(/evidence_quality\s+string/)
      expect(baml_schema).to match(/next_steps\s+string\[\]/)
      expect(baml_schema).to match(/knowledge_gaps\s+string\[\]/)

      # Note: Descriptions require integration with DSPy::Signature's FieldDescriptor
      # This will be implemented in the full BAML integration
    end

    it 'demonstrates significant token savings across multiple signatures' do
      signatures = [TaskDecomposition, ResearchExecution]

      total_json_chars = 0
      total_baml_chars = 0

      signatures.each do |sig|
        json_schema = sig.output_json_schema
        json_string = JSON.pretty_generate(json_schema)
        baml_string = sig.output_struct_class.to_baml

        total_json_chars += json_string.length
        total_baml_chars += baml_string.length
      end

      token_savings_pct = ((1 - total_baml_chars.to_f / total_json_chars) * 100).round(1)

      puts "\n=== Aggregate Token Savings ==="
      puts "Total JSON Schema: #{total_json_chars} chars"
      puts "Total BAML Schema: #{total_baml_chars} chars"
      puts "Overall savings: #{token_savings_pct}%"

      # Verify significant token savings (should be > 80%)
      expect(token_savings_pct).to be > 80
    end
  end

  describe 'end-to-end prediction with JSON schema (baseline)' do
    it 'completes task decomposition with JSON schema format', vcr: { cassette_name: 'baml/task_decomposition_json' } do
      predictor = DSPy::Predict.new(TaskDecomposition)

      result = predictor.call(
        topic: "Renewable energy adoption in urban environments",
        context: "Focus on practical implementation challenges",
        complexity_level: ComplexityLevel::Intermediate
      )

      expect(result.subtasks).to be_an(Array)
      expect(result.subtasks.length).to be >= 3
      expect(result.task_types).to be_an(Array)
      expect(result.priority_order).to be_an(Array)
      expect(result.estimated_effort).to be_an(Array)
      expect(result.dependencies).to be_an(Array)
      expect(result.agent_requirements).to be_an(Array)
    end

    it 'completes research execution with JSON schema format', vcr: { cassette_name: 'baml/research_execution_json' } do
      predictor = DSPy::Predict.new(ResearchExecution)

      result = predictor.call(
        subtask: "Analyze solar panel adoption barriers in high-density urban areas",
        context: "Previous research indicates cost and installation complexity are key factors",
        constraints: "Focus on actionable insights for policymakers"
      )

      expect(result.findings).to be_a(String)
      expect(result.findings.length).to be > 50
      expect(result.key_insights).to be_an(Array)
      expect(result.confidence_level).to be_between(1, 10)
      expect(result.evidence_quality).to be_a(String)
      expect(result.next_steps).to be_an(Array)
      expect(result.knowledge_gaps).to be_an(Array)
    end
  end
end
