require 'spec_helper'
# Outline signature for creating article structure
class Outline < DSPy::Signature
    description "Outline a thorough overview of a topic."
    
    input :topic, String
    output :title, String
    # TODO: gonna need json schemas here
    output :sections, Array[String]
    output :section_subheadings, Hash, desc: "mapping from section headings to subheadings"
  end

  
  # DraftSection signature for creating content for a section
  class DraftSection < DSPy::Signature
    description "Draft a top-level section of an article."
    
    input :topic, String
    input :section_heading, String
    input :section_subheadings, Array

    output :content, String, desc: "markdown-formatted section"
  end
  
  class DraftArticle
    attr_reader :title, :sections
    def initialize(title:, sections:)
      @title = title
      @sections = sections
    end
  end

  # DraftArticle module that composes the pipeline
  class ArticleDrafter < DSPy::Module
    def initialize
      @build_outline = DSPy::ChainOfThought.new(Outline)
      @draft_section = DSPy::ChainOfThought.new(DraftSection)
    end
    
    def forward(topic)
      # First, build the outline
      outline = @build_outline.call(topic: topic)
      # Then, draft each section
      sections = []
      
      outline.section_subheadings.each do |heading, subheadings|
        section_heading = "## #{heading}"
        # TODO: gonna need json schemas here
        formatted_subheadings = [subheadings].flatten.map { |subheading| "### #{subheading}" }
        
        # Draft this section
        section = @draft_section.call(
          topic: outline.title,
          section_heading: section_heading,
          section_subheadings: formatted_subheadings
        )

        sections << section
      end
      
      DraftArticle.new(title: outline.title, sections: sections)
    end
  end

RSpec.describe DraftArticle do

  it 'drafts the outline about There Is a Liberal Answer to Elon Musk' do
    VCR.use_cassette('openai/gpt4o-mini/draft_outline_liberal_answer_to_elon_musk') do
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      DSPy.configure(lm: lm)

      outliner = DSPy::ChainOfThought.new(Outline)
      
      outline = outliner.call(topic: "There Is a Liberal Answer to Elon Musk")
      expect(outline).to be_a(Outline)
      expect(outline.title).to be_a(String)
      expect(outline.sections).to be_a(Array)
      expect(outline.section_subheadings).to be_a(Hash)
    end
  end

  it 'drafts a section about There Is a Liberal Answer to Elon Musk' do
    VCR.use_cassette('openai/gpt4o-mini/draft_section_liberal_answer_to_elon_musk') do
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      DSPy.configure(lm: lm)

      drafter = DSPy::ChainOfThought.new(DraftSection)
      section = drafter.call(
        topic: "There Is a Liberal Answer to Elon Musk",
        section_heading: "Introduction",
        section_subheadings: []
      )

      expect(section).to be_a(DraftSection)
      expect(section.content).to be_a(String)

    end
  end

  it 'drafts an article about World Cup 2002' do
    VCR.use_cassette('openai/gpt4o-mini/draft_article_worldcup') do
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      DSPy.configure(lm: lm)
      
      draft_article = ArticleDrafter.new
      
      article = draft_article.call("World Cup 2002")
      expect(article).to be_a(DraftArticle)
      expect(article.title).to be_a(String)
    end
  end

  it 'draft sections are POROs' do
    VCR.use_cassette('openai/gpt4o-mini/draft_article_worldcup') do
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      DSPy.configure(lm: lm)

      drafter = ArticleDrafter.new
      draft_article = drafter.call("World Cup 2002")

      draft_section = draft_article.sections.first
      expect(draft_section).to be_a(DraftSection)
      expect(draft_section.content).to be_a(String)
    end
  end
end 