# frozen_string_literal: true

require 'spec_helper'

# Define ComplexityLevel as a T::Enum for autonomous task orchestration
class ComplexityLevel < T::Enum
  enums do
    Basic = new('basic')
    Intermediate = new('intermediate')
    Advanced = new('advanced')
  end
end

# Task decomposition signature for autonomous task definition and prioritization
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

# Research execution signature for individual task execution with contextual awareness
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

# Research synthesis signature for combining findings into comprehensive conclusions
class ResearchSynthesis < DSPy::Signature
  description "Synthesize all research findings into comprehensive conclusions and strategic recommendations"

  input do
    const :topic, String, description: "The original research topic being synthesized"
    const :findings_collection, T::Array[String], description: "Collection of all research findings from subtasks"
    const :objectives, String, description: "Original research objectives and intended outcomes"
  end

  output do
    const :executive_summary, String, description: "High-level executive summary of all findings"
    const :key_conclusions, T::Array[String], description: "Primary conclusions drawn from the research"
    const :recommendations, T::Array[String], description: "Strategic recommendations based on findings"
    const :knowledge_gaps, T::Array[String], description: "Overall knowledge gaps identified across all research"
    const :confidence_assessment, String, description: "Overall confidence assessment for the research quality"
    const :future_research_directions, T::Array[String], description: "Suggested directions for future research"
  end
end

# Autonomous Task Orchestrator class that coordinates the entire research workflow
class AutonomousTaskOrchestrator
  def initialize(opus_lm, sonnet_lm)
    @decomposer = DSPy::ChainOfThought.new(TaskDecomposition)
    @decomposer.configure { |config| config.lm = opus_lm }
    
    @researcher = DSPy::ChainOfThought.new(ResearchExecution)
    @researcher.configure { |config| config.lm = sonnet_lm }
    
    @synthesizer = DSPy::ChainOfThought.new(ResearchSynthesis)
    @synthesizer.configure { |config| config.lm = sonnet_lm }
  end

  def orchestrate_research(topic:, context: "", objectives: "")
    # Determine complexity level from context or default to intermediate
    complexity_level = extract_complexity_level(context)

    # Step 1: Autonomous task decomposition and strategic planning
    decomposition = @decomposer.call(
      topic: topic,
      context: context,
      complexity_level: complexity_level
    )

    # Step 2: Execute research on autonomously defined subtasks in priority order
    research_findings = []
    accumulated_context = context

    # Sort tasks by priority for optimal execution sequence
    task_indices = (0...decomposition.subtasks.length).to_a
    sorted_indices = task_indices.sort_by { |i| decomposition.priority_order[i] }.reverse

    sorted_indices.each do |index|
      subtask = decomposition.subtasks[index]
      task_type = decomposition.task_types[index]
      agent_requirement = decomposition.agent_requirements[index]

      finding = @researcher.call(
        subtask: subtask,
        context: "#{accumulated_context}\n\nTask Type: #{task_type}\nAgent Requirement: #{agent_requirement}",
        constraints: "Focus on actionable insights and evidence-based conclusions"
      )

      research_findings << {
        subtask: subtask,
        task_type: task_type,
        priority: decomposition.priority_order[index],
        estimated_effort: decomposition.estimated_effort[index],
        agent_requirement: agent_requirement,
        dependency: decomposition.dependencies[index],
        finding: finding
      }

      # Update context with new findings for subsequent research
      accumulated_context += "\n\nCompleted: #{subtask} (#{task_type})"
      accumulated_context += "\nKey insights: #{finding.key_insights.join('; ')}"
    end

    # Step 3: Synthesize all findings into comprehensive conclusions
    synthesis = @synthesizer.call(
      topic: topic,
      findings_collection: research_findings.map { |rf|
        "#{rf[:task_type]} Task: #{rf[:subtask]}\nFindings: #{rf[:finding].findings}"
      },
      objectives: objectives.empty? ? "Provide comprehensive understanding of #{topic}" : objectives
    )

    # Return enhanced orchestration results with autonomous task data
    {
      original_topic: topic,
      complexity_level: complexity_level.serialize,
      decomposition: decomposition,
      research_findings: research_findings,
      synthesis: synthesis,
      orchestration_metadata: {
        total_subtasks: decomposition.subtasks.length,
        task_types_used: decomposition.task_types.uniq,
        average_confidence: research_findings.map { |rf| rf[:finding].confidence_level }.sum.to_f / research_findings.length,
        total_estimated_effort: decomposition.estimated_effort.sum,
        high_priority_tasks: research_findings.select { |rf| rf[:priority] >= 4 }.length,
        agent_types_needed: decomposition.agent_requirements.uniq,
        completion_timestamp: Time.now.iso8601
      }
    }
  end

  private

  def extract_complexity_level(context)
    return ComplexityLevel::Basic if context.include?("complexity_level: basic")
    return ComplexityLevel::Advanced if context.include?("complexity_level: advanced")
    return ComplexityLevel::Intermediate if context.include?("complexity_level: intermediate")
    ComplexityLevel::Intermediate # Default to intermediate
  end
end

RSpec.describe 'Autonomous Task Orchestrator with Claude 4', type: :integration do
  let(:opus_lm) do
    DSPy::LM.new('anthropic/claude-opus-4-20250514', api_key: ENV['ANTHROPIC_API_KEY'])
  end

  let(:sonnet_lm) do
    DSPy::LM.new('anthropic/claude-sonnet-4-20250514', api_key: ENV['ANTHROPIC_API_KEY'])
  end

  let(:orchestrator) { AutonomousTaskOrchestrator.new(opus_lm, sonnet_lm) }

  before do
    DSPy.configure do |c|
      c.lm = sonnet_lm
    end
  end

  describe 'complex research orchestration' do
    it 'autonomously orchestrates multi-step research on AI ethics' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        expect(result).to have_key(:original_topic)
        expect(result[:original_topic]).to eq("Sustainable technology adoption in developing countries")
      end
    end

    it 'autonomously defines research subtasks' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        decomposition = result[:decomposition]
        expect(decomposition.subtasks).to be_an(Array)
        expect(decomposition.subtasks.length).to be >= 3
        expect(decomposition.subtasks).to all(be_a(String))
        expect(decomposition.subtasks).to all(satisfy { |task| task.length > 20 })
      end
    end

    it 'classifies task types autonomously' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries"
        )

        decomposition = result[:decomposition]
        expect(decomposition.task_types).to be_an(Array)
        expect(decomposition.task_types.length).to eq(decomposition.subtasks.length)
        expect(decomposition.task_types).to all(be_a(String))
      end
    end

    it 'provides strategic priority ordering' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries"
        )

        decomposition = result[:decomposition]
        expect(decomposition.priority_order).to be_an(Array)
        expect(decomposition.priority_order).to all(be_between(1, 5))
        expect(decomposition.priority_order.length).to eq(decomposition.subtasks.length)
      end
    end

    it 'defines task dependencies for sequencing' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries"
        )

        decomposition = result[:decomposition]
        expect(decomposition.dependencies).to be_an(Array)
        expect(decomposition.dependencies.length).to eq(decomposition.subtasks.length)
      end
    end

    it 'suggests agent requirements for future mapping' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries"
        )

        decomposition = result[:decomposition]
        expect(decomposition.agent_requirements).to be_an(Array)
        expect(decomposition.agent_requirements.length).to eq(decomposition.subtasks.length)
        expect(decomposition.agent_requirements).to all(be_a(String))
      end
    end

    it 'executes research with contextual findings' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        findings = result[:research_findings]
        expect(findings).to be_an(Array)
        expect(findings.length).to be >= 2

        findings.each do |finding_data|
          expect(finding_data).to have_key(:subtask)
          expect(finding_data).to have_key(:finding)
        end
      end
    end

    it 'maintains contextual awareness across research steps' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        findings = result[:research_findings]
        findings.each do |finding_data|
          finding = finding_data[:finding]
          expect(finding.key_insights).to be_an(Array)
          expect(finding.confidence_level).to be_between(1, 10)
          expect(finding.evidence_quality).to be_a(String)
        end
      end
    end

    it 'provides autonomous next step recommendations' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        findings = result[:research_findings]
        findings.each do |finding_data|
          finding = finding_data[:finding]
          expect(finding.next_steps).to be_an(Array)
          expect(finding.next_steps).to_not be_empty
        end
      end
    end

    it 'generates comprehensive executive synthesis' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        synthesis = result[:synthesis]
        expect(synthesis.executive_summary).to be_a(String)
        expect(synthesis.executive_summary.length).to be > 250
        expect(synthesis.key_conclusions).to be_an(Array)
        expect(synthesis.recommendations).to be_an(Array)
      end
    end

    it 'provides autonomous knowledge gap identification' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        synthesis = result[:synthesis]
        expect(synthesis.knowledge_gaps).to be_an(Array)
        expect(synthesis.knowledge_gaps).to_not be_empty
        expect(synthesis.future_research_directions).to be_an(Array)
      end
    end

    it 'delivers strategic recommendations' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        synthesis = result[:synthesis]
        expect(synthesis.recommendations).to be_an(Array)
        expect(synthesis.recommendations.length).to be >= 3
        expect(synthesis.recommendations).to all(be_a(String))
      end
    end

    it 'demonstrates autonomous complexity scaling' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        # Test that the result has the expected structure for complexity handling
        expect(result[:decomposition]).to respond_to(:subtasks)
        expect(result[:decomposition].subtasks.length).to be >= 3
        expect(result).to have_key(:complexity_level)
        expect(result[:complexity_level]).to match(/basic|intermediate|advanced/)
      end
    end

    it 'maintains autonomous decision quality metrics' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Consider technological, social, and economic factors"
        )

        metadata = result[:orchestration_metadata]
        expect(metadata[:average_confidence]).to be >= 6.5
        expect(metadata[:total_subtasks]).to be >= 4
        expect(metadata[:task_types_used]).to be_an(Array)
        expect(metadata[:agent_types_needed]).to be_an(Array)
      end
    end

    it 'provides autonomous priority justification' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        decomposition = result[:decomposition]
        expect(decomposition.priority_order).to be_an(Array)
        expect(decomposition.priority_order.length).to eq(decomposition.subtasks.length)
      end
    end

    it 'suggests appropriate agent types for task execution' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "Focus on practical implementation challenges and success stories"
        )

        agent_reqs = result[:decomposition].agent_requirements
        expect(agent_reqs).to be_an(Array)
        expect(agent_reqs).to all(be_a(String))
        expect(agent_reqs.any? { |req| req.downcase.include?("analyst") || req.downcase.include?("research") }).to be true
      end
    end

    it 'handles ComplexityLevel enum properly' do
      VCR.use_cassette('anthropic/claude-4/autonomous_task_definition') do
        result = orchestrator.orchestrate_research(
          topic: "Sustainable technology adoption in developing countries",
          context: "complexity_level: advanced, Focus on moral decision-making algorithms"
        )

        expect(result[:complexity_level]).to eq("advanced")
        expect(result[:decomposition]).to respond_to(:subtasks)
        expect(result[:orchestration_metadata][:total_subtasks]).to be >= 3
      end
    end
  end
end
