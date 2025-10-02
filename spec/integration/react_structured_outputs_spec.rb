# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ReAct with structured outputs (Issue #133)', :integration do
  before(:each) do
    DSPy.configure do |config|
      config.lm = DSPy::LM.new(
        'openai/gpt-4o-mini',
        api_key: ENV['OPENAI_API_KEY']
      )
    end
  end

  describe 'preserving tool result structure in output' do
    class Course < T::Struct
      const :id, Integer
      const :course_title, String
      const :description, String
      const :link, String
    end

    class CoursesToolSet < DSPy::Tools::Toolset
      extend T::Sig
      toolset_name "courses_toolset"

      tool :search_courses, description: "recommend courses related to the query"

      sig { params(query: String).returns(T::Array[Course]) }
      def search_courses(query:)
        [
          Course.new(
            id: 1,
            course_title: "Introduction to AI",
            description: "Learn the basics of Artificial Intelligence.",
            link: "https://example.com/intro-to-ai"
          ),
          Course.new(
            id: 2,
            course_title: "Advanced Machine Learning",
            description: "Deep dive into machine learning algorithms and techniques.",
            link: "https://example.com/advanced-ml"
          ),
          Course.new(
            id: 3,
            course_title: "Data Science Fundamentals",
            description: "Understand data analysis, visualization, and statistical methods.",
            link: "https://example.com/data-science-fundamentals"
          )
        ]
      end
    end

    class LearningAssistant < DSPy::Signature
      description "You are an AI Learning Assistant specialized in helping users find educational content."

      input do
        const :query, String
      end

      output do
        const :response, T::Array[Course]
      end
    end

    it 'returns structured Course array from tool result', vcr: { cassette_name: 'react_structured_course_output_issue_133' } do
      toolset = CoursesToolSet.new
      agent = DSPy::ReAct.new(
        LearningAssistant,
        tools: toolset.class.to_tools
      )

      result = agent.call(query: "Can you recommend some courses on AI and Machine Learning?")

      # The key assertion: result.response should be an Array of Course objects,
      # not a String description
      expect(result.response).to be_a(Array)
      expect(result.response).not_to be_empty
      expect(result.response.first).to be_a(Course)
      expect(result.response.first.course_title).to eq("Introduction to AI")
      expect(result.response.first.id).to eq(1)

      # Verify we have all 3 courses
      expect(result.response.length).to eq(3)
      expect(result.response.map(&:course_title)).to include(
        "Introduction to AI",
        "Advanced Machine Learning",
        "Data Science Fundamentals"
      )
    end

    it 'preserves structure with structured_outputs enabled', vcr: { cassette_name: 'react_structured_course_output_with_structured_outputs' } do
      DSPy.configure do |config|
        config.lm = DSPy::LM.new(
          'openai/gpt-4o-mini',
          api_key: ENV['OPENAI_API_KEY'],
          structured_outputs: true
        )
      end

      toolset = CoursesToolSet.new
      agent = DSPy::ReAct.new(
        LearningAssistant,
        tools: toolset.class.to_tools
      )

      result = agent.call(query: "Recommend AI and ML courses")

      expect(result.response).to be_a(Array)
      expect(result.response.first).to be_a(Course)
      expect(result.response.length).to eq(3)
    end
  end
end
