# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'NaiveRLM Integration', :integration do
  let(:research_paper) do
    <<~PAPER.lines.map(&:chomp)
      Title: Effects of Exercise on Mental Health
      Authors: Dr. Sarah Johnson, Dr. Michael Chen
      Published: Journal of Health Psychology, 2024

      Abstract
      This study examines the relationship between regular physical exercise
      and mental health outcomes in adults aged 25-65. We conducted a
      randomized controlled trial with 500 participants over 12 months.
      Results show significant improvements in anxiety and depression scores
      among participants who exercised at least 150 minutes per week.

      1. Introduction
      Mental health disorders affect millions of people worldwide.
      Exercise has been proposed as a non-pharmacological intervention.
      Previous studies have shown mixed results regarding efficacy.
      This study aims to provide definitive evidence through rigorous methodology.

      2. Methods
      2.1 Participants
      We recruited 500 adults (250 male, 250 female) aged 25-65.
      Exclusion criteria included pre-existing cardiovascular conditions.
      Participants were randomly assigned to exercise or control groups.

      2.2 Intervention
      Exercise group: 150+ minutes moderate exercise per week
      Control group: Maintained usual activity levels
      Duration: 12 months with monthly check-ins

      2.3 Measurements
      Primary outcomes: PHQ-9 (depression), GAD-7 (anxiety)
      Secondary outcomes: Quality of life (SF-36), sleep quality
      Assessments conducted at baseline, 6 months, and 12 months

      3. Results
      3.1 Primary Outcomes
      Exercise group showed 45% reduction in depression scores (p<0.001)
      Anxiety scores decreased by 38% in exercise group (p<0.001)
      Effect sizes were large (Cohen's d = 0.8 for depression)

      3.2 Secondary Outcomes
      Quality of life improved significantly in exercise group
      Sleep quality improved by 52% compared to baseline
      Adherence rate was 78% for the full 12 months

      3.3 Subgroup Analysis
      Benefits were consistent across age groups and genders
      Participants with higher baseline severity showed greater improvements
      Outdoor exercise showed marginally better outcomes than indoor

      4. Discussion
      Our findings strongly support exercise as mental health intervention.
      The effect sizes observed are comparable to antidepressant medications.
      Limitations include self-reported exercise adherence.
      Future research should explore optimal exercise types and durations.

      5. Conclusion
      Regular physical exercise significantly improves mental health outcomes.
      Healthcare providers should consider exercise prescriptions for patients.
      Public health initiatives promoting exercise could reduce mental health burden.

      References
      1. World Health Organization (2023) Mental Health Statistics
      2. Smith et al. (2022) Exercise and Depression Meta-analysis
      3. Johnson & Lee (2021) Physical Activity Guidelines Review
      4. Chen et al. (2020) Anxiety Interventions Systematic Review
    PAPER
  end

  describe DSPy::NaiveRLM::Navigator do
    let(:navigator) { described_class.new(max_iterations: 5) }

    before do
      skip 'Requires OPENAI_API_KEY' unless ENV['OPENAI_API_KEY']
      DSPy.configure do |config|
        config.lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      end
    end

    describe '#forward', vcr: { cassette_name: 'naive_rlm/basic_query' } do
      it 'navigates document to answer query' do
        result = navigator.forward(
          lines: research_paper,
          query: 'What were the main findings about depression?'
        )

        # Result is now a typed struct
        expect(result).to be_a(DSPy::NaiveRLM::Result)
        expect(result.answer).to be_a(String)
        expect(result.iterations).to be_a(Integer)
        expect(result.history).to be_an(Array)

        # Should find relevant information about depression
        answer = result.answer.downcase
        expect(answer).to satisfy('mentions depression or reduction') do |a|
          a.include?('depression') || a.include?('45%') || a.include?('reduction')
        end

        # Should have used some actions
        expect(result.history).not_to be_empty
      end
    end

    describe 'action execution', vcr: { cassette_name: 'naive_rlm/action_trace' } do
      it 'records action history' do
        result = navigator.forward(
          lines: research_paper,
          query: 'What was the sample size and duration of the study?'
        )

        history = result.history
        expect(history).not_to be_empty

        # History should contain action descriptions
        history_text = history.join(' ')
        expect(history_text).to satisfy('contains action types') do |h|
          h.include?('GREP') || h.include?('PEEK') || h.include?('PARTITION')
        end
      end
    end

    describe 'max iterations', vcr: { cassette_name: 'naive_rlm/max_iterations' } do
      let(:limited_navigator) { described_class.new(max_iterations: 2) }

      it 'stops at max iterations with partial answer' do
        result = limited_navigator.forward(
          lines: research_paper,
          query: 'Provide a comprehensive summary of all sections'
        )

        # With only 2 iterations, might not fully answer
        expect(result.iterations).to be <= 2

        # Should still return something
        expect(result.answer).not_to be_nil
        expect(result.max_iterations_reached).to be(true).or be(false)
      end
    end

    describe 'grep functionality', vcr: { cassette_name: 'naive_rlm/grep_search' } do
      it 'uses grep to find specific content' do
        result = navigator.forward(
          lines: research_paper,
          query: 'What were the p-values in the results?'
        )

        history_text = result.history.join(' ')

        # The LLM should use grep to search for statistical content
        expect(history_text).to include('p<0.001').or include('GREP')
      end
    end
  end

  describe 'signature validation' do
    it 'SelectAction signature renders valid prompts' do
      prompt = DSPy::Prompt.from_signature(DSPy::NaiveRLM::SelectAction)

      system_prompt = prompt.render_system_prompt
      expect(system_prompt).to include('action')
      expect(system_prompt).to include('query')
    end

    it 'SummarizeChunk signature renders valid prompts' do
      prompt = DSPy::Prompt.from_signature(DSPy::NaiveRLM::SummarizeChunk)

      system_prompt = prompt.render_system_prompt
      expect(system_prompt).to include('summary')
      expect(system_prompt).to include('relevance')
    end
  end
end
