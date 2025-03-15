require 'spec_helper'

# Outline signature for creating article structure
class Outline < DSPy::Signature
    description "Outline a thorough overview of a topic."
    
    input :topic, String
    output :title, String
    # TODO: gonna need json schemas here
    output :sections, Array
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
  
  # DraftArticle module that composes the pipeline
  class DraftArticle < DSPy::Module
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
      
      # Return the complete article
      prediction(title: outline.title, sections: sections)
    end
  end

RSpec.describe DraftArticle do

  it 'drafts an article about World Cup 2002' do
    VCR.use_cassette('openai/gpt4o-mini/draft_article_worldcup') do
      # Set up the model
      lm = DSPy::LM.new('openai/gpt-4o-mini', api_key: ENV['OPENAI_API_KEY'])
      DSPy.configure(lm: lm)
      
      # Create the article drafter
      draft_article = DraftArticle.new
      
      # Draft an article about World Cup 2002
      article = draft_article.call("World Cup 2002")
      
      # Test the results
      expect(article).to be_a(DSPy::Prediction)
      expect(article.title).to be_a(String)
    end
  end
end 